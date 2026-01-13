"""
Artifactory Helper Module
Provides functions to interact with JFrog Artifactory for:
- Authentication using Azure Key Vault credentials
- Uploading models to Artifactory Machine Learning Repository using frogml
- Downloading models from Artifactory Machine Learning Repository using frogml
- Configuring pip to use Artifactory PyPI repository
- Docker registry operations
"""

import os
import base64
import requests
from typing import Optional, Dict, Any
from azure.identity import DefaultAzureCredential, ManagedIdentityCredential
from azure.keyvault.secrets import SecretClient

try:
    import frogml
    FROGML_AVAILABLE = True
except ImportError:
    FROGML_AVAILABLE = False
    frogml = None


class ArtifactoryHelper:
    """Helper class for Artifactory operations with Azure Key Vault integration."""
    
    def __init__(
        self,
        artifactory_host: str,
        key_vault_name: str,
        username_secret_name: str,
        access_token_secret_name: Optional[str] = None
    ):
        """
        Initialize Artifactory helper.
        
        Args:
            artifactory_host: Base URL of Artifactory instance
            key_vault_name: Name of Azure Key Vault
            username_secret_name: Name of secret containing Artifactory username
            password_secret_name: Name of secret containing Artifactory password
            api_key_secret_name: Optional name of secret containing Artifactory API key
            access_token_secret_name: Optional name of secret containing Artifactory access token
                                   (preferred for frogml authentication)
        """
        self.artifactory_host = artifactory_host.rstrip('/')
        self.key_vault_name = key_vault_name
        self.username_secret_name = username_secret_name
        self.access_token_secret_name = access_token_secret_name
        
        self._credentials = None
        self._session = None
        self._frogml_configured = False
    
    def _get_key_vault_client(self) -> SecretClient:
        """Get Azure Key Vault secret client."""
        # In AzureML compute, use ManagedIdentityCredential
        # Try user-assigned first (if client_id is provided), then system-assigned
        vault_url = f"https://{self.key_vault_name}.vault.azure.net"
        credential = None
        client_id = os.environ.get('AZURE_CLIENT_ID')
    
        if client_id:
           # User-assigned managed identity
           print(f"Using user-assigned managed identity with client_id: {client_id}")
           credential = ManagedIdentityCredential(client_id=client_id)
        else:
           # System-assigned managed identity (no parameters)
           print("Using system-assigned managed identity")
           credential = ManagedIdentityCredential()
        return SecretClient(vault_url=vault_url, credential=credential)
    
    def _get_credentials(self) -> Dict[str, str]:
        """Retrieve Artifactory credentials from Azure Key Vault."""
        if self._credentials is None:
            client = self._get_key_vault_client()
            
            username = client.get_secret(self.username_secret_name).value
            
            self._credentials = {
                'username': username,
            }
            
            # Prefer access token for frogml authentication
            if self.access_token_secret_name:
                try:
                    access_token = client.get_secret(self.access_token_secret_name).value
                    self._credentials['access_token'] = access_token
                except Exception:
                    # Access token not available
                    pass

        
        return self._credentials
    
    
    def _configure_frogml(self):
        """
        Configure frogml with credentials from Azure Key Vault.
        frogml uses environment variables JF_URL and JF_ACCESS_TOKEN for authentication.
        """
        if not FROGML_AVAILABLE:
            raise ImportError(
                "frogml package is not installed. Please install it with: pip install frogml"
            )
        
        if self._frogml_configured:
            return
        
        creds = self._get_credentials()
        
        # Set JF_URL environment variable (required by frogml)
        os.environ['JF_URL'] = self.artifactory_host
        
        # Prefer access token, then API key, then use username/password
        # According to JFrog documentation, JF_ACCESS_TOKEN is the preferred authentication method
        if 'access_token' in creds:
            os.environ['JF_ACCESS_TOKEN'] = creds['access_token']
            os.environ['JF_USER'] = creds['username']        
        self._frogml_configured = True
    
    def upload_model_to_ml_repository(
        self,
        model_path: str,
        ml_repo_name: str,
        model_name: str,
        version: str,
        metadata: Optional[Dict[str, Any]] = None,
        properties: Optional[Dict[str, str]] = None,
        dependencies: Optional[list] = None,
        code_dir: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Upload model to Artifactory Machine Learning Repository using frogml.
        Uses frogml.files.log_model() as per JFrog documentation.
        
        Args:
            model_path: Local path to the model file
            ml_repo_name: Name of the ML repository in Artifactory
            model_name: Name of the model
            version: Version of the model
            metadata: Optional metadata dictionary (converted to properties)
            properties: Optional properties dictionary to attach to the model
            dependencies: Optional list of dependencies (e.g., ['pandas==1.2.3'])
            code_dir: Optional path to directory containing code related to the model
            
        Returns:
            Dictionary with upload result information
        """
        # Configure frogml with credentials from Key Vault
        self._configure_frogml()
        
        if not FROGML_AVAILABLE:
            raise ImportError(
                "frogml package is not installed. Please install it with: pip install frogml"
            )
        
        # Convert metadata to properties if provided
        properties = {}
        ######
        #Comment because getting error when using metadata:
        #2025-12-02 23:16:08,020 - ERROR - frogml.storage.logging._log_config.frog_ml.__upload_entity_version:253 - Max length for Properties is 60 characters.
        #ERROR:FilesModelVersionManager:An error occurred while logging model iris-classifier to azureml-ml-local

        # if metadata and not properties:
        #     for key, value in metadata.items():
        #         properties[str(key)] = str(value) if not isinstance(value, (dict, list)) else str(value)
        
        try:
            # Upload model using frogml.files.log_model()
            frogml.files.log_model(
                source_path=model_path,
                repository=ml_repo_name,
                model_name=model_name,
                version=version,
                properties=properties,
                dependencies=dependencies,
                code_dir=code_dir
            )
            
            # Construct repository path for return value
            filename = os.path.basename(model_path)
            repo_path = f"{ml_repo_name}/{model_name}/{version}/{filename}"
            upload_url = f"{self.artifactory_host}/artifactory/{repo_path}"
            
            return {
                'success': True,
                'url': upload_url,
                'repo_path': repo_path,
                'model_name': model_name,
                'version': version,
                'properties': properties,
                'dependencies': dependencies
            }
            
        except Exception as e:
            raise Exception(f"Failed to upload model using frogml: {str(e)}")
    
    def verify_model_upload(
        self,
        ml_repo_name: str,
        model_name: str,
        version: str,
        filename: str
    ) -> bool:
        """
        Verify that a model was successfully uploaded to Artifactory ML Repository.
        Uses frogml to check if model exists.
        
        Args:
            ml_repo_name: Name of the ML repository
            model_name: Name of the model
            version: Version of the model
            filename: Name of the uploaded file
            
        Returns:
            True if model exists, False otherwise
        """
        # Configure frogml with credentials from Key Vault
        self._configure_frogml()
        
        try:
            # Try using frogml to verify model existence
            if FROGML_AVAILABLE:
                try:
                    # Use frogml.files.get_model_version() to check if model exists
                    model_version = frogml.files.get_model_version(
                        repository=ml_repo_name,
                        model_name=model_name,
                        version=version
                    )
                    # If we can get the model version, it exists
                    return model_version is not None
                except (AttributeError, Exception) as e:
                    # frogml method may not be available or model doesn't exist
                    # Fall back to REST API
                    pass
        except Exception:
            return False

    
    def download_model_from_ml_repository(
        self,
        ml_repo_name: str,
        model_name: str,
        version: str,
        download_path: str,
        filename: Optional[str] = None
    ) -> str:
        """
        Download model from Artifactory Machine Learning Repository using frogml.
        Uses frogml.files.download_model() or frogml.files.get_model_version().download().
        
        Args:
            ml_repo_name: Name of the ML repository
            model_name: Name of the model
            version: Version of the model
            download_path: Local directory path to save the downloaded model
            filename: Optional specific filename to save (defaults to model name)
            
        Returns:
            Path to the downloaded model file
        """
        # Configure frogml with credentials from Key Vault
        self._configure_frogml()
        
        if not FROGML_AVAILABLE:
            raise ImportError(
                "frogml package is not installed. Please install it with: pip install frogml"
            )
        
        # Ensure download directory exists
        os.makedirs(download_path, exist_ok=True)
        
        try:
            # Try using frogml.files.download_model() first
            try:
                frogml.files.download_model(
                    repository=ml_repo_name,
                    model_name=model_name,
                    version=version,
                    destination_path=download_path
                )
            except AttributeError:
                # If download_model doesn't exist, try get_model_version().download()
                model_version = frogml.files.get_model_version(
                    repository=ml_repo_name,
                    model_name=model_name,
                    version=version
                )
                if filename:
                    target_path = os.path.join(download_path, filename)
                else:
                    target_path = download_path
                model_version.download(target_path)
            
            # Determine the downloaded file path
            if filename:
                downloaded_file = os.path.join(download_path, filename)
            else:
                # Try to find the downloaded file
                # frogml may download with the model name or version
                possible_names = [
                    os.path.join(download_path, f"{model_name}-{version}.pkl"),
                    os.path.join(download_path, f"{model_name}.pkl"),
                    os.path.join(download_path, model_name),
                    os.path.join(download_path, f"{model_name}-{version}")
                ]
                
                downloaded_file = None
                for possible_path in possible_names:
                    if os.path.exists(possible_path):
                        downloaded_file = possible_path
                        break
                
                if not downloaded_file:
                    # List files in download_path to find what was downloaded
                    files = [f for f in os.listdir(download_path) if os.path.isfile(os.path.join(download_path, f))]
                    if files:
                        downloaded_file = os.path.join(download_path, files[0])
            
            if downloaded_file and os.path.exists(downloaded_file):
                return downloaded_file
            else:
                raise Exception(
                    f"Downloaded file not found. Expected in: {download_path}. "
                    f"Please check the download_path directory."
                )
                
        except Exception as e:
            raise Exception(f"Failed to download model using frogml: {str(e)}")
    
