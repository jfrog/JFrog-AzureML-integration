"""
AzureML Pipeline for deploying models and running batch inference.
This pipeline:
- Downloads a trained model from Artifactory
- Deploys it to AzureML compute cluster
- Runs batch inference on test data
"""

import os
import yaml
import json
import tempfile
import shutil
import glob
from azure.ai.ml import Input, MLClient, Output, command, dsl
from azure.ai.ml.entities import Environment
from azure.ai.ml.entities import WorkspaceConnection
from azure.ai.ml.entities import UsernamePasswordConfiguration
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
import warnings
import logging

# Suppress AzureML SDK experimental class warnings
warnings.filterwarnings('ignore', message='.*experimental class.*')
warnings.filterwarnings('ignore', message='.*experimental.*')

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


@dsl.pipeline(
    name="artifactory-integration-deployment",
    description="Deploy model from Artifactory and run batch inference"
)
def deployment_pipeline(
    model_name: str = None,
    model_version: str = None
):
    """
    AzureML pipeline for deploying models and running inference.
    
    Args:
        model_name: Name of the model in Artifactory (if not provided, uses config)
        model_version: Version of the model in Artifactory (required)
    """
    # Load configuration
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
    env = Environment(
        image=docker_image
    )
    
    # Build environment variables dictionary
    # Note: MODEL_NAME env var uses config value, actual model name comes from input
    env_vars = {
        "AZURE_KEY_VAULT_NAME": config['key_vault']['name'],
        "ARTIFACTORY_HOST": config['artifactory']['artifactory_host'],
        "ARTIFACTORY_ML_REPO": config['artifactory']['repositories']['ml'],
        "ARTIFACTORY_USERNAME_SECRET": config['key_vault']['secrets']['artifactory_username'],
        "MODEL_NAME": model_name,  # Default from config, can be overridden by input
        "AZURE_CLIENT_ID": config['azureml']['compute']['managed_identity_client_id'],
    }
    
    # Add optional access token secret if available
    if 'artifactory_access_token' in config['key_vault']['secrets']:
        env_vars["ARTIFACTORY_ACCESS_TOKEN_SECRET"] = config['key_vault']['secrets']['artifactory_access_token']
    
    # Create deployment and inference command component
    # IMPORTANT: Input defaults must be literal values (strings), not PipelineInput objects
    # The pipeline function arguments (model_name, model_version) are PipelineInput objects
    # So we use config values as defaults, and pass the arguments to deploy_step to override them
    deploy_cmd = command(
        name="deploy_and_inference",
        display_name="Deploy Model and Run Batch Inference",
        description="Download model from Artifactory, deploy to compute, and run batch inference",
        code="./src",
        command="python deploy_and_inference.py --model-name ${{inputs.model_name}} --model-version ${{inputs.model_version}}",
        environment=env,
        inputs={
            "model_name": Input(type="string"),
            "model_version": Input(type="string")
        },
        outputs={
            "inference_results": Output(type="uri_file")
        },
        environment_variables=env_vars
    )
    
    # Create deployment step
    # Pass pipeline function arguments directly - they will override the Input defaults
    # PipelineInput objects can be passed here, but not as Input defaults
    deploy_step = deploy_cmd(
        model_name=model_name,
        model_version=model_version
    )
    deploy_step.compute = config['azureml']['compute']['cluster_name']
    
    return {
        "inference_results": deploy_step.outputs.inference_results
    }


def main():
    """Main function to submit the deployment pipeline."""
    import argparse
    
    parser = argparse.ArgumentParser(description='Submit deployment and inference pipeline')
    parser.add_argument('--model-name', type=str, default=None, help='Model name in Artifactory')
    parser.add_argument('--model-version', type=str, required=True, help='Model version in Artifactory (required)')
    args = parser.parse_args()
    
    # Load configuration
    config = load_config()
    
    # Get ML client
    ml_client = get_ml_client(config)
    
    # Create or get compute cluster
    from azure.ai.ml.entities import AmlCompute
    from azure.ai.ml.entities._credentials import IdentityConfiguration
    from azure.ai.ml.entities import ManagedIdentityConfiguration
    
    try:
        compute = ml_client.compute.get(config['azureml']['compute']['cluster_name'])
        print(f"Using existing compute cluster: {compute.name}")
    except Exception:
        print(f"Creating compute cluster: {config['azureml']['compute']['cluster_name']}")
        compute = AmlCompute(
            name=config['azureml']['compute']['cluster_name'],
            size=config['azureml']['compute']['vm_size'],
            min_instances=config['azureml']['compute']['min_nodes'],
            max_instances=config['azureml']['compute']['max_nodes'],
            identity=IdentityConfiguration(
                type="user_assigned",
                user_assigned_identities=[ManagedIdentityConfiguration(
                    resource_id=config['azureml']['compute']['managed_identity']
                )]
            )
        )
        ml_client.compute.begin_create_or_update(compute).result()
    
    # Create workspace connection for Artifactory Docker registry authentication
    try:
        from azure.identity import DefaultAzureCredential
        from azure.keyvault.secrets import SecretClient
        
        credential = DefaultAzureCredential()
        vault_url = f"https://{config['key_vault']['name']}.vault.azure.net"
        kv_client = SecretClient(vault_url=vault_url, credential=credential)
        
        access_token = None
        if 'artifactory_access_token' in config['key_vault']['secrets']:
            try:
                access_token = kv_client.get_secret(config['key_vault']['secrets']['artifactory_access_token']).value
            except Exception as e:
                print(f"Warning: Could not retrieve access token: {e}")
        
        username = None
        if 'artifactory_username' in config['key_vault']['secrets']:
            try:
                username = kv_client.get_secret(config['key_vault']['secrets']['artifactory_username']).value
            except Exception as e:
                print(f"Warning: Could not retrieve username: {e}")
        
        if access_token and username:
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
    
    # Create pipeline with arguments
    pipeline_job = deployment_pipeline(
        model_name=args.model_name,
        model_version=args.model_version
    )
    
    # Submit pipeline
    print("Submitting deployment pipeline to AzureML...")
    submitted_job = ml_client.jobs.create_or_update(pipeline_job)
    
    print(f"Pipeline submitted: {submitted_job.name}")
    print(f"Job ID: {submitted_job.name}")
    print(f"View in Azure Portal: {submitted_job.studio_url}")
    print("\n" + "=" * 60)
    print("Waiting for pipeline to complete...")
    print("=" * 60)
    
    # Wait for the pipeline to complete
    try:
        print("Waiting for pipeline to complete (press Ctrl+C to exit and check later)...")
        ml_client.jobs.stream(submitted_job.name)
    except KeyboardInterrupt:
        print("\n⚠️  Pipeline streaming interrupted.")
        print("   You can check the status in Azure Portal and get results from the inference_results output.")
    
    # Try to get inference results from the completed job
    try:
        completed_job = ml_client.jobs.get(submitted_job.name)
        
        if completed_job.status == "Completed":
            print("\n" + "=" * 60)
            print("✓ Deployment Pipeline Completed Successfully!")
            print("=" * 60)
            
            # Download and display inference results
            try:
                # Create a temporary directory to download the inference results
                temp_dir = "./downloaded_artifacts/named-outputs/inference_results"
                os.makedirs(temp_dir, exist_ok=True)
                
                try:
                    # Download the inference_results output
                    print(f"\nDownloading inference results to {temp_dir}...")
                    ml_client.jobs.download(
                        name=submitted_job.name,
                        output_name="inference_results",
                        download_path=temp_dir
                    )
                    
                    # Find the inference_results.json file
                    inference_files = glob.glob(
                        os.path.join(temp_dir, "**", "inference_results.json"), 
                        recursive=True
                    )
                    
                    if inference_files and os.path.exists(inference_files[0]):
                        inference_file_path = inference_files[0]
                        print(f"Found inference results at: {inference_file_path}")
                        
                        with open(inference_file_path, "r") as f:
                            results = json.load(f)
                        
                        print("\n" + "=" * 60)
                        print("📊 Inference Results")
                        print("=" * 60)
                        print(f"Model Type: {results.get('model_type', 'N/A')}")
                        print(f"Test Samples: {results.get('test_samples', 'N/A')}")
                        print(f"Accuracy: {results.get('accuracy', 0):.4f}")
                        print(f"Inference Timestamp: {results.get('inference_timestamp', 'N/A')}")
                        print(f"\nFeatures: {', '.join(results.get('features', []))}")
                        print(f"Target Classes: {', '.join(results.get('target_names', []))}")
                        
                        # Show sample predictions if available
                        predictions = results.get('predictions', [])
                        true_labels = results.get('true_labels', [])
                        target_names = results.get('target_names', [])
                        
                        if predictions and true_labels and target_names:
                            print(f"\n📈 Sample Predictions (first 10):")
                            print("-" * 60)
                            for i in range(min(10, len(predictions))):
                                pred_name = target_names[predictions[i]] if predictions[i] < len(target_names) else str(predictions[i])
                                true_name = target_names[true_labels[i]] if true_labels[i] < len(target_names) else str(true_labels[i])
                                match = "✓" if predictions[i] == true_labels[i] else "✗"
                                print(f"  {match} Sample {i+1}: Predicted={pred_name}, Actual={true_name}")
                        
                        print("\n" + "=" * 60)
                    else:
                        print(f"\n⚠️  Could not find inference_results.json in {temp_dir}")
                        print(f"   Check the inference_results output in Azure Portal")
                except Exception as e:
                    print(f"\n⚠️  Could not download inference results: {e}")
                    print(f"   Check the inference_results output in Azure Portal: {submitted_job.studio_url}")
            except Exception as e:
                print(f"\n⚠️  Error extracting inference results: {e}")
                print(f"   Check the inference_results output in Azure Portal: {submitted_job.studio_url}")
        elif completed_job.status == "Failed":
            print(f"\n❌ Pipeline failed. Check Azure Portal for details: {submitted_job.studio_url}")
        else:
            print(f"\n⏳ Pipeline status: {completed_job.status}")
            print(f"   Check Azure Portal for details: {submitted_job.studio_url}")
    except Exception as e:
        print(f"\n⚠️  Could not retrieve job status: {e}")
        print(f"   Check Azure Portal for pipeline status: {submitted_job.studio_url}")
    
    return submitted_job


if __name__ == "__main__":
    main()
