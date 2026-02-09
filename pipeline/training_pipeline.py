"""
AzureML Pipeline for training ML models with Artifactory integration.
This pipeline demonstrates:
- Using Docker images from Artifactory
- Installing Python dependencies from Artifactory PyPI
- Uploading trained models to Artifactory Machine Learning Repository
- Authentication via Azure Key Vault
"""

from datetime import datetime
import os
import uuid
import json
import tempfile
import shutil
import glob

from azure.ai.ml import Input, MLClient, Output, command, dsl
from azure.ai.ml.constants._common import IdentityType
from azure.ai.ml.entities import Environment
from azure.ai.ml.entities import WorkspaceConnection
from azure.ai.ml.entities import UsernamePasswordConfiguration
from azure.ai.ml.entities._credentials import IdentityConfiguration
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
from azure.mgmt.authorization import AuthorizationManagementClient
import yaml
from azure.ai.ml.entities import ManagedIdentityConfiguration
import warnings
import logging

# Suppress AzureML SDK experimental class warnings
warnings.filterwarnings('ignore', message='.*experimental class.*')
warnings.filterwarnings('ignore', message='.*experimental.*')
warnings.filterwarnings('ignore', message='.*pathOnCompute.*')
warnings.filterwarnings('ignore', message='.*not a known attribute.*')

# Suppress specific AzureML SDK warnings
logging.getLogger('azure.ai.ml').setLevel(logging.ERROR)

def load_config(config_path: str = "config/config.yaml") -> dict:
    """Load configuration from YAML file."""
    with open(config_path, 'r') as f:
        return yaml.safe_load(f)


def get_ml_client(config: dict) -> MLClient:
    """Get AzureML MLClient."""
    credential = DefaultAzureCredential()
    
    return MLClient(
        credential=credential,
        subscription_id=config['azure']['subscription_id'],
        resource_group_name=config['azure']['resource_group'],
        workspace_name=config['azure']['workspace_name']
    )
def get_auth_client(config: dict) -> AuthorizationManagementClient:
    """Get AzureML MLClient."""
    return AuthorizationManagementClient(credential=DefaultAzureCredential(), subscription_id=config['azure']['subscription_id'])


@dsl.pipeline(
    name="artifactory-integration-training",
    description="Train ML model with Artifactory integration"
)
def training_pipeline():
    """
    AzureML pipeline for training with Artifactory integration.
    Configuration is loaded from config/config.yaml at pipeline definition time.
    """
    # Load configuration at pipeline definition time (not execution time)
    # This needs to be done outside the pipeline function or passed as a parameter
    # For now, we'll load it from the default location
    config_path = "config/config.yaml"
    with open(config_path, 'r') as f:
        config = yaml.safe_load(f)
    
    # Get Artifactory Docker image
    artifactory_host = config['artifactory']['artifactory_host']
    docker_repo = config['artifactory']['repositories']['docker']
    docker_host = artifactory_host.replace('https://', '').replace('http://', '')
    image_name = config['artifactory']['image_name']
    image_tag = config['artifactory']['image_tag']
    docker_image = f"{docker_host}/{docker_repo}/{image_name}:{image_tag}"
    
    # Create environment with Docker image from Artifactory
    # Note: AzureML will need to authenticate to pull from Artifactory
    # This is typically handled via image pull secrets or managed identity
    env = Environment(
        image=docker_image
    )
    
    # Build environment variables dictionary
    env_vars = {
        "AZURE_KEY_VAULT_NAME": config['key_vault']['name'],
        "ARTIFACTORY_HOST": config['artifactory']['artifactory_host'],
        "ARTIFACTORY_ML_REPO": config['artifactory']['repositories']['ml'],
        "MODEL_NAME": config['model']['name'],
        "AZURE_CLIENT_ID": config['azureml']['compute']['managed_identity_client_id'],
        "UPLOAD_TO_ARTIFACTORY": config['model']['upload_to_artifactory']
    }

    
    # Add optional access token secret if available (preferred for frogml)
    if 'artifactory_access_token_secret_name' in config['key_vault']['secrets']:
        env_vars["ARTIFACTORY_ACCESS_TOKEN_SECRET_NAME"] = config['key_vault']['secrets']['artifactory_access_token_secret_name']
    
    # Create training command component
        train_cmd = command(
            name="train_and_upload_model",
            display_name="Train ML Model and Upload to Artifactory",
            description="Train ML model and upload to Artifactory ML Repository",
            code="./src",
            command="python train.py --metadata_dir ${{outputs.metadata}}",
            environment=env,
            outputs={
        "metadata": Output(
            type="uri_folder", 
            mode="upload",
            # Ensure the datastore part 'workspaceblobstore' is exactly as named in your workspace
            #path="azureml://datastores/workspaceblobstore/paths/outputs/metadata_dir/"
        )
    },
            environment_variables=env_vars
        )
    
    # Create the training step
    train_step = train_cmd()
    train_step.compute = config['azureml']['compute']['cluster_name']
    
    return {
        "metadata": train_step.outputs.metadata
    }

def main():
    """Main function to submit the pipeline."""
    # Load configuration
    config = load_config()
    
    # Get ML client
    ml_client = get_ml_client(config)

    # Get auth client to set the RBAC role for the key vault to enable AzureML to access the key vault secrets
    auth_client = get_auth_client(config)
    
    # Create or get compute cluster
    from azure.ai.ml.entities import AmlCompute
    
    try:
        compute = ml_client.compute.get(config['azureml']['compute']['cluster_name'])
        print(f"Using existing compute cluster: {compute.name}")
        # Check if compute has managed identity, if not we'll need to update it
        if not hasattr(compute, 'identity') or compute.identity is None:
            print("Warning: Compute cluster does not have managed identity configured.")
            print("  You may need to enable it manually in Azure Portal or update the compute.")
    except Exception:
        print(f"Creating compute cluster: {config['azureml']['compute']['cluster_name']}")
        # Create compute with system-assigned managed identity
        compute = AmlCompute(
            name=config['azureml']['compute']['cluster_name'],
            size=config['azureml']['compute']['vm_size'],
            min_instances=config['azureml']['compute']['min_nodes'],
            max_instances=config['azureml']['compute']['max_nodes'],
            identity=IdentityConfiguration(type="user_assigned",user_assigned_identities=[ManagedIdentityConfiguration(resource_id=config['azureml']['compute']['managed_identity'])])
            
        )
        ml_client.compute.begin_create_or_update(compute).result()

    # Create workspace connection for Artifactory Docker registry authentication
    # This allows AzureML to pull the Docker image from Artifactory
    try:
        # Get credentials from Key Vault
        from azure.identity import DefaultAzureCredential
        from azure.keyvault.secrets import SecretClient
        
        credential = DefaultAzureCredential()
        vault_url = f"https://{config['key_vault']['name']}.vault.azure.net"
        kv_client = SecretClient(vault_url=vault_url, credential=credential)
        
        username = None
        access_token = None
        if 'artifactory_access_token_secret_name' in config['key_vault']['secrets']:
            try:
                 secret_value = kv_client.get_secret(config['key_vault']['secrets']['artifactory_access_token_secret_name']).value
                 secret_value_json = json.loads(secret_value)
                 access_token = secret_value_json['access_token']
                 username = secret_value_json['username']
            except Exception as e:
                print(f"Warning: Could not retrieve access and username token: {e}")
        
        

        
        # Prefer access token for API key auth, fallback to username/password
        if access_token and username:
            # Create workspace connection with username/password credentials
            credentials = UsernamePasswordConfiguration(username=username, password=access_token)
            artifactory_host = config['artifactory']['artifactory_host']
            
            ws_connection = WorkspaceConnection(
                name="JFrogArtifactory",
                target=artifactory_host,
                type="GenericContainerRegistry",
                credentials=credentials
            )
            
            try:
                ml_client.connections.create_or_update(ws_connection)
                print("✓ Workspace connection created/updated for Artifactory")
            except Exception as e:
                print(f"Warning: Could not create workspace connection: {e}")
                print("  You may need to configure Docker registry authentication manually")

            
   
    except Exception as e:
        print(f"Warning: Could not set up workspace connection: {e}")
        print("  Docker image pull may fail if authentication is required")
    
    # Create pipeline (no arguments needed - config is loaded inside)
    pipeline_job = training_pipeline()
    
    # Submit pipeline
    print("Submitting pipeline to AzureML...")
    submitted_job = ml_client.jobs.create_or_update(pipeline_job)
    
    print(f"Pipeline submitted: {submitted_job.name}")
    print(f"Job ID: {submitted_job.name}")
    print(f"View in Azure Portal: {submitted_job.studio_url}")
    print("\n" + "=" * 60)
    print("Waiting for pipeline to complete...")
    print("=" * 60)
    
    # Wait for the pipeline to complete and extract model information
    print("\n💡 Tip: You can check the pipeline status in Azure Portal or wait for it to complete.")
    print("   After completion, model name and version will be displayed below.\n")
    
    # Optionally wait for completion (user can interrupt with Ctrl+C)
    try:
        print("Waiting for pipeline to complete (press Ctrl+C to exit and check later)...")
        ml_client.jobs.stream(submitted_job.name)
    except KeyboardInterrupt:
        print("\n⚠️  Pipeline streaming interrupted.")
        print("   You can check the status in Azure Portal and get model info from the metadata output.")
    
    # Try to get model information from the completed job
    try:
        completed_job = ml_client.jobs.get(submitted_job.name)
        
        if completed_job.status == "Completed":
            print("\n" + "=" * 60)
            print("✓ Training Pipeline Completed Successfully!")
            print("=" * 60)
            
            # Extract model name and version from metadata output
            # Create a temporary directory to download the metadata
            temp_dir = "./downloaded_artifacts"
            os.makedirs(temp_dir, exist_ok=True)
            
            try:
                    # Download the metadata output
                    ml_client.jobs.download(
                    name=submitted_job.name,
                    download_path=temp_dir,
                    output_name="metadata") # This is the name of the output in the pipeline

                    metadata_file_path = os.path.join(temp_dir, "named-outputs", "metadata", "metadata.json")
                    
                    if os.path.exists(metadata_file_path):
                        with open(metadata_file_path, "r") as f:
                            data = json.load(f)
                        model_name = data.get('model_name')
                        model_version = data.get('version')
                        print(f"Retrieved Model: {model_name}, Version: {model_version}")
                        
                        print(f"\n📦 Model Information:")
                        print(f"   Model Name: {model_name}")
                        print(f"   Model Version: {model_version}")
                        print(f"\n🚀 To deploy this model, run:")
                        print(f"   python pipeline/deployment_pipeline.py --model-name {model_name} --model-version {model_version}")
                        print("\n" + "=" * 60)
                    else:
                        print(f"Error: Could not find metadata.json in {temp_dir}")
                        print(f"   Check the metadata output in Azure Portal for the version.")
                        print(f"   The version format is: vYYYYMMDDHHMMSS (e.g., v20260118123456)")
            except Exception as e:
                  print(f"Error: Could not download metadata output: {e}")
                  print(f"   Check Azure Portal for pipeline status: {submitted_job.studio_url}")
                  print(f"   Once completed, you can:")
                  print(f"   1. Download the metadata output from Azure Portal")
                  print(f"   2. Or check the training job logs for the version (format: vYYYYMMDDHHMMSS)")
                  print(f"   3. Model name is: {config['model']['name']}")
        elif completed_job.status == "Failed":
            print(f"\n❌ Pipeline failed. Check Azure Portal for details: {submitted_job.studio_url}")
        else:
            print(f"\n⏳ Pipeline status: {completed_job.status}")
            print(f"   Check Azure Portal for details: {submitted_job.studio_url}")
            print(f"   Once completed, check the metadata output for model name and version.")
    except Exception as e:
        print(f"\n⚠️  Could not retrieve job status: {e}")
        print(f"   Check Azure Portal for pipeline status: {submitted_job.studio_url}")
        print(f"   Once completed, you can:")
        print(f"   1. Download the metadata output from Azure Portal")
        print(f"   2. Or check the training job logs for the version (format: vYYYYMMDDHHMMSS)")
        print(f"   3. Model name is: {config['model']['name']}")
    
    return submitted_job


if __name__ == "__main__":
    main()

