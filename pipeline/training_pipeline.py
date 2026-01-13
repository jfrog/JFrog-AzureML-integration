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
    artifactory_artifactory_host = config['artifactory']['artifactory_host']
    docker_repo = config['artifactory']['repositories']['docker']
    docker_host = artifactory_artifactory_host.replace('https://', '').replace('http://', '')
    image_name = config['artifactory']['image_name']
    image_tag = config['artifactory']['image_tag']
    docker_image = f"{docker_host}/{docker_repo}/{image_name}:{image_tag}"
    
    # Create environment with Docker image from Artifactory
    # Note: AzureML will need to authenticate to pull from Artifactory
    # This is typically handled via image pull secrets or managed identity
    env = Environment(
        name="artifactory-training-env",
        image=docker_image
    )
    
    # Build environment variables dictionary
    env_vars = {
        "AZURE_KEY_VAULT_NAME": config['key_vault']['name'],
        "ARTIFACTORY_artifactory_host": config['artifactory']['artifactory_host'],
        "ARTIFACTORY_PYPI_REPO": config['artifactory']['repositories']['pypi'],
        "ARTIFACTORY_ML_REPO": config['artifactory']['repositories']['ml'],
        "ARTIFACTORY_USERNAME_SECRET": config['key_vault']['secrets']['artifactory_username'],
        "MODEL_NAME": config['model']['name'],
        "AZURE_CLIENT_ID": config['azureml']['compute']['managed_identity_client_id']
    }

    
    # Add optional access token secret if available (preferred for frogml)
    if 'artifactory_access_token' in config['key_vault']['secrets']:
        env_vars["ARTIFACTORY_ACCESS_TOKEN_SECRET"] = config['key_vault']['secrets']['artifactory_access_token']
    
    # Create training command component
    train_cmd = command(
        name="train_and_upload_model",
        display_name="Train ML Model and Upload to Artifactory",
        description="Train ML model and upload to Artifactory ML Repository",
        code="./src",
        command="python train.py",
        environment=env,
        outputs={
            "model": Output(type="uri_file"),
            "metrics": Output(type="uri_file"),
            "metadata": Output(type="uri_file")
        },
        environment_variables=env_vars
    )
    
    # Create the training step
    train_step = train_cmd()
    train_step.compute = config['azureml']['compute']['cluster_name']
    
    return train_step

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
        
        # Prefer access token, fallback to API key
        access_token = None
        if 'artifactory_access_token' in config['key_vault']['secrets']:
            try:
                access_token = kv_client.get_secret(config['key_vault']['secrets']['artifactory_access_token']).value
            except Exception as e:
                print(f"Warning: Could not retrieve access token: {e}")
        
        username = None
        password = None
        
        if 'artifactory_username' in config['key_vault']['secrets']:
            try:
                username = kv_client.get_secret(config['key_vault']['secrets']['artifactory_username']).value
            except Exception as e:
                print(f"Warning: Could not retrieve username: {e}")
        
        # Prefer access token for API key auth, fallback to username/password
        if access_token and username:
            # Create workspace connection with username/password credentials
            credentials = UsernamePasswordConfiguration(username=username, password=access_token)
            artifactory_artifactory_host = config['artifactory']['artifactory_host']
            
            ws_connection = WorkspaceConnection(
                name="JFrogArtifactory",
                target=artifactory_artifactory_host,
                type="GenericContainerRegistry",
                credentials=credentials
            )
            
            try:
                ml_client.connections.create_or_update(ws_connection)
                print("✓ Workspace connection created/updated for Artifactory")
            except Exception as e:
                print(f"Warning: Could not create workspace connection: {e}")
                print("  You may need to configure Docker registry authentication manually")
        elif username and password:
            # Use username/password if access token not available
            credentials = UsernamePasswordConfiguration(username=username, password=password)
            artifactory_artifactory_host = config['artifactory']['artifactory_host']
            
            ws_connection = WorkspaceConnection(
                name="JFrogArtifactory",
                target=artifactory_artifactory_host,
                type="GenericContainerRegistry",
                credentials=credentials
            )
            
            try:
                ml_client.connections.create_or_update(ws_connection)
                print("✓ Workspace connection created/updated for Artifactory (using username/password)")
            except Exception as e:
                print(f"Warning: Could not create workspace connection: {e}")
                print("  You may need to configure Docker registry authentication manually")
        else:
            print("Warning: No credentials found. Docker image pull may fail.")
            print("  Ensure your Artifactory registry allows anonymous access or configure authentication manually")
    
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
    
    return submitted_job


if __name__ == "__main__":
    main()

