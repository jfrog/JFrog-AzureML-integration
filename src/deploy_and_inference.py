# (c) JFrog Ltd (2026).
"""
Deployment and Batch Inference Script
Downloads model from Artifactory, loads it, and runs batch inference on test data.
"""

import os
import sys
import json
import pickle
import argparse
from datetime import datetime, timezone
from sklearn.datasets import load_iris
from sklearn.model_selection import train_test_split


def download_model_from_artifactory(
    model_name: str,
    model_version: str,
    ml_repo: str,
    download_dir: str,
    artifactory_host: str,
    key_vault_name: str,
    access_token_secret_name: str = None,
    client_id: str = None
) -> str:
    """
    Download model from Artifactory using ArtifactoryHelper.
    
    Args:
        model_name: Name of the model in Artifactory
        model_version: Version of the model
        ml_repo: Artifactory ML repository name
        download_dir: Local directory to download model to
        artifactory_host: Artifactory host URL
        key_vault_name: Azure Key Vault name
        username_secret_name: Secret name for Artifactory username
        access_token_secret_name: Optional secret name for access token
        client_id: Optional Azure client ID for managed identity
        
    Returns:
        Path to downloaded model file
    """
    # Add parent directory to path for imports
    sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
    from utils.artifactory_helper import ArtifactoryHelper
    
    print(f"Initializing ArtifactoryHelper...")
    helper = ArtifactoryHelper(
        artifactory_host=artifactory_host,
        key_vault_name=key_vault_name,
        access_token_secret_name=access_token_secret_name
    )
    
    # Set client ID if provided (for managed identity)
    if client_id:
        os.environ['AZURE_CLIENT_ID'] = client_id
    
    print(f"Downloading model from Artifactory...")
    print(f"  Repository: {ml_repo}")
    print(f"  Model: {model_name}")
    print(f"  Version: {model_version}")
    
    # Download model
    model_path = helper.download_model_from_ml_repository(
        ml_repo_name=ml_repo,
        model_name=model_name,
        version=model_version,
        download_path=download_dir
    )
    
    print(f"✓ Model downloaded to: {model_path}")
    return model_path


def run_batch_inference(model_path: str, test_size: float = 0.2) -> dict:
    """
    Load model and run batch inference on test data.
    
    Args:
        model_path: Path to the model file (pickle)
        test_size: Proportion of data to use for testing
        
    Returns:
        Dictionary containing inference results
    """
    print(f"Loading model from {model_path}...")
    
    # Load model
    with open(model_path, 'rb') as f:
        model = pickle.load(f)
    
    print(f"Model loaded successfully. Type: {type(model).__name__}")
    
    # Generate test data (same as training script)
    print("Loading Iris dataset for inference...")
    iris = load_iris()
    X, y = iris.data, iris.target
    
    # Split data (same random_state as training for consistency)
    _, X_test, _, y_test = train_test_split(
        X, y, test_size=test_size, random_state=42
    )
    
    print(f"Running inference on {X_test.shape[0]} samples...")
    
    # Run predictions
    predictions = model.predict(X_test)
    
    # Get prediction probabilities if available
    probabilities = None
    if hasattr(model, 'predict_proba'):
        try:
            probabilities = model.predict_proba(X_test).tolist()
        except Exception as e:
            print(f"Warning: Could not get prediction probabilities: {e}")
    
    # Calculate accuracy
    from sklearn.metrics import accuracy_score
    accuracy = accuracy_score(y_test, predictions)
    
    # Create results dictionary
    # Handle feature_names and target_names - they might be lists or numpy arrays
    target_names_list = iris.target_names.tolist() if hasattr(iris.target_names, 'tolist') else list(iris.target_names)
    feature_names_list = iris.feature_names.tolist() if hasattr(iris.feature_names, 'tolist') else list(iris.feature_names)
    
    results = {
        'model_path': model_path,
        'model_type': type(model).__name__,
        'inference_timestamp': datetime.now(timezone.utc).isoformat(),
        'test_samples': int(X_test.shape[0]),
        'accuracy': float(accuracy),
        'predictions': predictions.tolist(),
        'true_labels': y_test.tolist(),
        'target_names': target_names_list,
        'features': feature_names_list,
        'input_data': X_test.tolist()
    }
    
    if probabilities:
        results['probabilities'] = probabilities
    
    print(f"Inference completed. Accuracy: {accuracy:.4f}")
    
    return results


def main():
    """Main function to orchestrate deployment and inference."""
    parser = argparse.ArgumentParser(description='Deploy model and run batch inference')
    parser.add_argument(
        '--model-name',
        type=str,
        required=True,
        help='Model name in Artifactory'
    )
    parser.add_argument(
        '--model-version',
        type=str,
        required=True,
        help='Model version in Artifactory'
    )
    parser.add_argument(
        '--inference_results_dir',
        type=str,
        default=None,
        help='Inference results directory (default: AZUREML_SCRIPT_OUTPUT_DIR or ./outputs)'
    )
    
    args = parser.parse_args()
    
    # Determine output directory
    output_dir = os.environ.get('AZUREML_SCRIPT_OUTPUT_DIR', './outputs')
    os.makedirs(output_dir, exist_ok=True)

    inference_results_dir = args.inference_results_dir
    os.makedirs(inference_results_dir, exist_ok=True)
    
    print("=" * 60)
    print("Deployment and Batch Inference")
    print("=" * 60)
    
    try:
        # Step 1: Get model information
        print("\n[Step 1] Model Information...")
        model_name = args.model_name
        model_version = args.model_version
        print(f"  Model name: {model_name}")
        print(f"  Version: {model_version}")
        
        # Step 2: Download model from Artifactory
        print("\n[Step 2] Downloading model from Artifactory...")
        
        # Get environment variables
        artifactory_host = os.environ.get('ARTIFACTORY_HOST')
        ml_repo = os.environ.get('ARTIFACTORY_ML_REPO')
        key_vault_name = os.environ.get('AZURE_KEY_VAULT_NAME')
        access_token_secret_name = os.environ.get('ARTIFACTORY_ACCESS_TOKEN_SECRET_NAME')
        client_id = os.environ.get('AZURE_CLIENT_ID')
        
        if not all([artifactory_host, ml_repo, key_vault_name]):
            raise ValueError(
                "Missing required environment variables: "
                "ARTIFACTORY_HOST, ARTIFACTORY_ML_REPO, AZURE_KEY_VAULT_NAME"
            )
        
        # Create download directory
        download_dir = os.path.join(output_dir, 'downloaded_model')
        os.makedirs(download_dir, exist_ok=True)
        
        # Download model
        model_path = download_model_from_artifactory(
            model_name=model_name,
            model_version=model_version,
            ml_repo=ml_repo,
            download_dir=download_dir,
            artifactory_host=artifactory_host,
            key_vault_name=key_vault_name,
            access_token_secret_name=access_token_secret_name,
            client_id=client_id
        )
        
        # Step 3: Run batch inference
        print("\n[Step 3] Running batch inference...")
        inference_results = run_batch_inference(model_path)
        
        # Step 4: Save results
        print("\n[Step 4] Saving inference results...")
        results_path = os.path.join(inference_results_dir, 'inference_results.json')
        with open(results_path, 'w') as f:
            json.dump(inference_results, f, indent=2)
        
        print(f"✓ Inference results saved to: {results_path}")
        
        print("\n" + "=" * 60)
        print("Deployment and Inference Completed Successfully!")
        print("=" * 60)
        print(f"Model: {model_name} v{model_version}")
        print(f"Test Accuracy: {inference_results['accuracy']:.4f}")
        print(f"Test Samples: {inference_results['test_samples']}")
        
    except Exception as e:
        print(f"\n❌ Error during deployment and inference: {str(e)}")
        import traceback
        traceback.print_exc()
        raise


if __name__ == "__main__":
    main()
