"""
Simple ML Model Training Script
Trains a scikit-learn model on the Iris dataset and saves the model.
"""

import os
import pickle
import json
import argparse
from datetime import datetime
from sklearn.datasets import load_iris
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score, classification_report


def train_model(output_dir: str = "./outputs") -> dict:
    """
    Train a RandomForest classifier on the Iris dataset.
    
    Args:
        output_dir: Directory to save the model and metrics
        
    Returns:
        Dictionary with model information and metrics
    """
    parser = argparse.ArgumentParser()
    parser.add_argument("--metadata_out", type=str, help="Path provided by Azure ML")
    args = parser.parse_args()

    metadata = {"model_name": "example", "version": "1.0.0"}
    # Create output directory
    os.makedirs(output_dir, exist_ok=True)
    
    # Load dataset
    print("Loading Iris dataset...")
    iris = load_iris()
    X, y = iris.data, iris.target
    
    # Split data
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )
    
    print(f"Training set size: {X_train.shape[0]}")
    print(f"Test set size: {X_test.shape[0]}")
    
    # Train model
    print("Training RandomForest classifier...")
    model = RandomForestClassifier(n_estimators=100, random_state=42)
    model.fit(X_train, y_train)
    
    # Evaluate model
    y_pred = model.predict(X_test)
    accuracy = accuracy_score(y_test, y_pred)
    
    print(f"Model accuracy: {accuracy:.4f}")
    
    # Generate classification report
    report = classification_report(y_test, y_pred, target_names=iris.target_names, output_dict=True)
    
    # Save model
    model_path = os.path.join(output_dir, "model.pkl")
    with open(model_path, 'wb') as f:
        pickle.dump(model, f)
    print(f"Model saved to {model_path}")
    
    # Save metrics
    metrics = {
        'accuracy': float(accuracy),
        'classification_report': report,
        'model_type': 'RandomForestClassifier',
        'n_estimators': 100,
        'training_samples': int(X_train.shape[0]),
        'test_samples': int(X_test.shape[0]),
        'timestamp': datetime.utcnow().isoformat()
    }
    
    metrics_path = os.path.join(output_dir, "metrics.json")
    with open(metrics_path, 'w') as f:
        json.dump(metrics, f, indent=2)
    print(f"Metrics saved to {metrics_path}")
    
    # Create metadata for Artifactory
    metadata = {
        'model_name': 'iris-classifier',
        'version': datetime.utcnow().strftime('v%Y%m%d%H%M%S'),
        'model_type': 'RandomForestClassifier',
        'dataset': 'Iris',
        'accuracy': float(accuracy),
        'training_date': datetime.utcnow().strftime('%Y%m%d%H%M%S'),
        'features': iris.feature_names,
        'target_classes': iris.target_names.tolist()
    }
    
    metadata_path = os.path.join(output_dir, "metadata.json")
    with open(metadata_path, 'w') as f:
        json.dump(metadata, f, indent=2)

    with open(args.metadata_out, 'w') as f:
        json.dump(metadata, f)  
    
    print(f"Metadata saved to {metadata_path}")
    
    return {
        'model_path': model_path,
        'metrics_path': metrics_path,
        'metadata_path': metadata_path,
        'metrics': metrics,
        'metadata': metadata
    }


if __name__ == "__main__":
    import sys
    import json
    
    # Use outputs directory (matches pipeline output definitions)
    # AzureML SDK v2 will automatically make files in this directory available as outputs
    output_dir = os.environ.get('AZUREML_SCRIPT_OUTPUT_DIR', 'outputs')
    result = train_model(output_dir)
    print("\nTraining completed successfully!")
    print(f"Model: {result['model_path']}")
    print(f"Accuracy: {result['metrics']['accuracy']:.4f}")
    
    # Upload to Artifactory if environment variables are set
    if all([
        os.environ.get('AZURE_KEY_VAULT_NAME'),
        os.environ.get('ARTIFACTORY_HOST'),
        os.environ.get('ARTIFACTORY_ML_REPO')
    ]) and os.environ.get('UPLOAD_TO_ARTIFACTORY') == 'true':
        try:
            sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
            from utils.artifactory_helper import ArtifactoryHelper
            
            print("\nUploading model to Artifactory ML Repository...")
            helper = ArtifactoryHelper(
                artifactory_host=os.environ['ARTIFACTORY_HOST'],
                key_vault_name=os.environ['AZURE_KEY_VAULT_NAME'],
                username_secret_name=os.environ.get('ARTIFACTORY_USERNAME_SECRET', 'artifactory-username'),
                access_token_secret_name=os.environ.get('ARTIFACTORY_ACCESS_TOKEN_SECRET')
            )
            
            # Load metadata
            with open(result['metadata_path'], 'r') as f:
                metadata = json.load(f)
            
            model_name = os.environ.get('MODEL_NAME', 'iris-classifier')
            ml_repo = os.environ['ARTIFACTORY_ML_REPO']
            
            upload_result = helper.upload_model_to_ml_repository(
                model_path=result['model_path'],
                ml_repo_name=ml_repo,
                model_name=model_name,
                version=metadata['version'],
                metadata=metadata
            )
            
            print(f"✓ Model uploaded to Artifactory: {upload_result['url']}")
                
        except Exception as e:
            print(f"⚠ Warning: Failed to upload to Artifactory: {str(e)}")
            print("Model training completed, but upload failed.")
            raise

