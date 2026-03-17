# AzureML + JFrog Artifactory Integration

This project demonstrates how to build and run Azure Machine Learning (AzureML) jobs while sourcing packages, images, and model artifacts from/to JFrog Artifactory.
It focuses on secure credential handling, repeatable builds, and predictable promotion of trained models.

What’s inside:

- Opinionated Docker build that pulls base images and Python packages from Artifactory.
- AzureML training pipeline example that runs a sample training script producing a trained Iris model in a managed compute cluster (serverless).
- `frogml` JFrog SDK is used for working with Machine Learning models and datasets packages.

## Train Architecture

The following diagram illustrates the complete architecture and data flow of the system:

```mermaid
graph TB
    subgraph "Build Phase"
        Dev[Developer/Local Machine]
        Docker[Docker BuildKit]
        BaseImage[Artifactory<br/>Base Image]
    end

    subgraph "Train Pipeline"
        TrainDev[Developer/Local Machine]
        PipelineScript[Pipeline Script]        
    end

    subgraph "Azure Cloud Runtime"
        KV[Azure Key Vault<br/>Credentials Storage]
        AML[AzureML Workspace]
        Compute[AzureML<br/>Compute Cluster with managed identity]
        Container[Training Container]
        TrainScript[train.py<br/>Model Training]
        ArtifactoryHelper[ArtifactoryHelper<br/>frogml Integration]
        Model[Model Artifacts<br/>model.pkl, metrics.json]
    end

    subgraph "Artifactory"
        ArtifactoryPyPI2[Artifactory<br/>PyPI Repository]
        ArtifactoryDocker2[Artifactory<br/>Docker Registry]
        ArtifactoryML[Artifactory<br/>ML Repository]
    end

    %% Build Phase Flow
    Dev -->|1. Build with mounted secrets from pip.conf| Docker
    BaseImage -->|2. Pull base image| Docker
    Docker -->|3. Install packages| ArtifactoryPyPI2
    Docker -->|4. Build & push image| ArtifactoryDocker2

    %% Train Phase Flow
    TrainDev -->|1. Execute Train Pipeline| PipelineScript
    PipelineScript -->|2. Get JFrog Credentials| KV
    PipelineScript -->|3. Submit Training Job| AML

    %% Runtime Phase Flow
    AML -->|1. Create Compute and Run Job| Compute    
    Compute -->|2. Pull image| ArtifactoryDocker2
    Compute -->|3. Run container| Container
    Container -->|4. Execute Train script| TrainScript
    TrainScript -->|5. Train model| Model
    TrainScript -->|6. Upload model| ArtifactoryHelper
    ArtifactoryHelper -->|7. Get credentials| KV
    ArtifactoryHelper -->|8. Upload model using FrogML| ArtifactoryML    
    

    %% Styling
    classDef buildPhase fill:#e1f5ff,stroke:#01579b,stroke-width:2px
    classDef azure fill:#0078d4,stroke:#005a9e,stroke-width:2px,color:#fff
    classDef artifactory fill:#40a9ff,stroke:#096dd9,stroke-width:2px
    classDef runtime fill:#f0f9ff,stroke:#0284c7,stroke-width:2px

    class Dev,Docker,PipConf buildPhase
    class KV,AML,Compute,MI azure
    class ArtifactoryPyPI,ArtifactoryDocker,ArtifactoryPyPI2,ArtifactoryDocker2,ArtifactoryML artifactory
    class Container,TrainScript,ArtifactoryHelper,Model runtime
```



## Deploy Architecture

The following diagram illustrates the complete architecture and data flow of the deployment example:

```mermaid
graph TB
    subgraph "Deploy Pipeline"
        DeploymentDev[Developer/Local Machine]
        DeployPipelineScript[Deployment Script]
    end
    subgraph "Artifactory"
        ArtifactoryML[Artifactory<br/>ML Repository]
        ArtifactoryDocker2[Artifactory<br/>Docker Registry]
    end
    subgraph "Azure Cloud Runtime"
        ArtifactoryHelper[ArtifactoryHelper<br/>frogml Integration]
        KV[Azure Key Vault<br/>Credentials Storage]
        AML[AzureML Workspace]
        Compute[AzureML<br/>Compute Cluster with managed identity]
        deploy_and_inference[Deploy and Inference Script]
        Model[Deployed Model]

    end

    %% Deployment Phase Flow
    DeploymentDev -->|1. Execute Deployment Pipeline| DeployPipelineScript
    DeployPipelineScript -->|2. Get JFrog Credentials| KV
    DeployPipelineScript -->|3. Submit Deployment Job| AML

    %% Runtime Phase Flow    
    AML -->|1. Create Compute and Run Job| Compute
    Compute -->|2. Pull image  | ArtifactoryDocker2
    Compute -->|3. Run Deploy & Inference Container| deploy_and_inference
    deploy_and_inference -->|4. Pull model| ArtifactoryHelper    
    ArtifactoryHelper -->|5. Get credentials| KV
    ArtifactoryHelper -->|6. Pull Model| ArtifactoryML
    deploy_and_inference -->|7. Run model| Model
    deploy_and_inference -->|8. Inference Tests Calls| Model    

    %% Styling
    classDef Deploy Pipeline fill:#e1f5ff,stroke:#01579b,stroke-width:2px
    classDef azure fill:#0078d4,stroke:#005a9e,stroke-width:2px,color:#fff
    classDef artifactory fill:#40a9ff,stroke:#096dd9,stroke-width:2px
    classDef runtime fill:#f0f9ff,stroke:#0284c7,stroke-width:2px

    class DeploymentDev,DeployPipelineScript,Deploy Pipeline
    class KV,AML,Compute,MI azure
    class Container,TrainScript,ArtifactoryHelper,Model runtime

```



### Architecture Components

#### Build Phase

1. **Docker Build Process:**
  - Mounts `pip.conf` as a Docker secret for secure credential handling
  - Uses base image from JFrog Artifactory (e.g. `python:3.13.11-slim` from Artifactory Docker registry)
  - Installs Python packages from Artifactory PyPI repository during build
  - Creates multi-stage Docker image with optimized layers and pushes it to JFrog Docker registry
  - Result: Image is ready for use in AzureML pipelines!
  - *At this point, the image will potentially be scanned by JFrog Xray and undergo the customer's SDLC pipeline.*

#### Train Runtime Phase

1. **Train Pipeline:**
  - A developer or a CI job runs the pipeline script
  - The pipeline script submits a training job to AzureML workspace
  - The AzureML workspace creates a compute cluster and runs the training job on it
  - AzureML compute cluster:
    - Retrieves JFrog short-lived credentials from AzureML Workspace Key Vault
    - Pulls the training image from Artifactory Docker registry
    - Runs the training image
  - The training container executes the training script (`train.py`)
2. **Model Training & Upload:**
  - Training script trains ML model (e.g. Iris classifier)
  - Model artifacts are generated (model.pkl, metrics.json, metadata.json)
  - `ArtifactoryHelper` class retrieves JFrog short-lived credentials from AzureML Workspace Key Vault
  - [optional] Model is uploaded to Artifactory ML Repository using `frogml` package

#### Deployment & Inference Phase

1. **Deployment Pipeline:**
  - A developer or a CI job runs the deployment_pipeline script, which is responsible for retrieving JFrog short-lived credentials from AzureML Workspace Key Vault
  - The pipeline script submits a deployment job to AzureML workspace
  - The AzureML workspace creates or uses an existing compute cluster and runs the training job on it (in this example we reuse the existing compute cluster)
  - AzureML compute cluster:        
    - Pulls the trained model image from Artifactory Docker registry (using the previously retrieved credentials)
  - The trained model container:
    - Retrieves JFrog short-lived credentials from AzureML Workspace Key Vault
    - Downloads the model
    - Runs the model
    - Performs inference test calls (`model.predict(...)`)

**Important**: This deployment example is ephemeral. Once inference test calls are done, the container completes and, as min_nodes is set to 0, within a few minutes the inference is removed.

#### Authentication & Security

1. **AzureML Workspace's Azure Key Vault:**
  - Stores Artifactory Access Token and Username securely
2. **Authentication Methods:**
  - **Local Development:** Uses Azure user or application registry credentials (e.g. az login)
  - **AzureML Runtime:** Uses Managed Identity (automatic, no credentials needed) for retrieving JFrog access token from the AzureML Workspace Key Vault
  - **Docker Build:** Uses Docker secrets (credentials not stored in image)

#### Advanced Authentication: JFrog token auto-rotation

For a more advanced security setup, a JFrog short-lived Access Token can be added and rotated automatically through an Azure Function based on the OIDC token exchange protocol.
For this setup, see the optional Terraform and function under 
[Advanced Setup (with automatic secret rotation)](#advanced-setup-with-automatic-secret-rotation).

### Key Integration Points

#### JFrog Repositories Used

- **Docker Registry:** Stores and serves Docker images; preferably use a virtual Docker repository to simplify usage
- **PyPI Remote/Virtual Repository:** Proxies Python packages used by the training scripts
- **ML Repository:** Stores trained ML models with versioning
- **HuggingFace Repository:** Proxies HF packages used by the training script

#### Packages

- **Docker Images:** Pulled from Artifactory Docker registry during pipeline execution
- **Python Packages:** Installed from Artifactory PyPI repository during Docker build
- **Docker Base Images:** Pulled from Artifactory Docker registry during Docker build
- **Used Models & Datasets:** Pulled from Artifactory using Frogml SDK
- **Resulting Models:** Uploaded to Artifactory ML Repository using Frogml SDK

#### Authentication

- **JFrog Credentials:** The authentication is based on a JFrog access token stored in Azure Key Vault, with an optional setup of an Azure Function for rotating this access token automatically based on the OIDC token exchange protocol

### Sequence Diagram

#### Training

The following sequence diagram shows the temporal flow of operations:

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant Docker as Docker BuildKit
    participant ArtPyPI as Artifactory PyPI
    participant ArtDocker as Artifactory Docker
    participant KV as Azure Key Vault
    participant AML as AzureML
    participant Compute as Compute Cluster
    participant Container as Training Container
    participant ArtML as Artifactory ML Repo

    Note over Dev,ArtDocker: Build Phase
    Dev->>Docker: Build with pip.conf secret
    Docker->>ArtDocker: Pull base image
    Docker->>ArtPyPI: Install packages from PyPI repo
    Docker->>ArtDocker: Build, tag and push image

    Note over AML,ArtML: Runtime Phase
    Dev->>KV: Get credentials (based on AZ login)
    Dev->>AML: Submit training pipeline
    AML->>Compute: Provision compute cluster
    Compute->>ArtDocker: Pull Docker image
    Compute->>Container: Create container from image
    Container->>KV: Get credentials (Managed Identity)
    Container->>Container: Execute train.py
    Container->>Container: Train ML model
    Container->>KV: Get credentials for upload
    Container->>ArtML: Upload model (via frogml)
    Container->>AML: Return pipeline outputs
    AML-->>Dev: Pipeline completed
```



#### Deployment and Inference

The following sequence diagram shows the temporal flow of deployment operations:

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant AML as AzureML
    participant Compute as Compute Cluster       
    participant KV as Azure Key Vault
    participant deploy_and_inference as Deploy & Inference script
    participant ArtDocker as Artifactory Docker
    participant ArtML as Artifactory ML repository 
    participant Model as Trained Model

    Note over Dev,ArtML: Setup Phase
    Dev->>KV: Get credentials (based on AZ login)
    Dev->>AML: Submit Deploy & Inference    
    AML->>Compute: Provision/Reuse compute cluster
    Compute->>KV: Get credentials (Managed Identity)
    Compute->> ArtDocker: Pull Image    
    Compute->> Compute: Run Image     
    
    Note over deploy_and_inference,Model: Run Phase
    Compute->>deploy_and_inference: Run Script
    deploy_and_inference->>KV: Get credentials (Managed Identity)
    deploy_and_inference->>ArtML: Pull Model
    deploy_and_inference->>Model: Run model   
    deploy_and_inference->>Model: Test model (inference)   
    deploy_and_inference->>AML: Log results   
    AML-->>Dev: Job completed
```



### Architectural decisions explained

#### Docker Build Process

- **Multi-stage build:** This example uses a multi-stage Docker build for optimized image size.
- **Docker secrets:** Using a Docker secret for allowing the access into the JFrog private registry allows for a secure credential handling (pip.conf) without the secret leaving traces on the created image.
- **Artifactory base image:** Using a base image pulled from the JFrog Docker registry ensures security protection for used images, i.e. Xray and Curation.
- **Package installation:** Python packages are pulled through Artifactory PyPI repository during build for security and control reasons, providing protection against harmful external dependencies.

#### AzureML Training Pipeline

- **Environment:** Using a custom Docker image from Artifactory allows for traceability, management, and repeatability of the training process along with security protections as described above.
- **Compute:** AzureML compute cluster with Managed Identity allows for passwordless and seamless operation of the training process when working with Azure and with JFrog services.
- **Outputs:** Model files, metrics, and metadata produced by the training process allow deep analytics and understanding of the training process for evaluating the resulting models.

#### Security Model

- **Build Time:** Docker secrets (credentials not in image layers)
- **Runtime:** Azure Key Vault + Managed Identity (no hardcoded secrets)
- **Network:** All communications over HTTPS
- **Access Control:** Role-based access via Azure and Artifactory
- **Used Credentials:** JFrog access token stored in Azure Key Vault, with an optional enhanced setup allowing for auto-rotated access tokens managed by an Azure Function, with token rotation based on OIDC and Azure App Registration & Managed Identity (see advanced setup under secret_rotation_function sub folder)

## Quick Start (Bring Your Own Workspace)

### Initialize Setup Environment (R&R: Azure Administrator)

### Prerequisites

- AzureML Workspace
- Compute Cluster with system assigned managed identities
- In the Azure Machine Learning workspace resource, add Contributor role to the relevant users or identities.
- Azure CLI configured
- Azure CLI requires the `ml extension`, run `az extension add --name ml` if the command is not found.
- Artifactory Access Token and Username

### Set Up

The AzureML Compute Cluster uses a **system-assigned managed identity** to access Key Vault secrets and storage at runtime. Assign the following RBAC roles to the compute cluster's system-assigned identity:

- **Key Vault Secrets User** on the AzureML workspace Key Vault — allows the compute to retrieve JFrog credentials during training/deployment jobs.
- **Storage Blob Data Contributor** on the workspace Storage Account — allows the compute to read/write data used by training pipelines.

For more information, see [Assign Azure roles using Azure CLI](https://learn.microsoft.com/en-us/azure/role-based-access-control/role-assignments-cli).

```bash

RESOURCE_GROUP="<your-resource-group>"
WORKSPACE_NAME="<workspace-name>"
COMPUTE_CLUSTER_NAME="<compute-cluster-name>"
SUBSCRIPTION_ID="<subscription-id>"
KEY_VAULT_NAME="<key-vault-name>"
STORAGE_ACCOUNT="<storage-account-name>"

# Get the compute cluster's principal ID
COMPUTE_PRINCIPAL_ID=$(az ml compute show \
  --name $COMPUTE_CLUSTER_NAME \
  --resource-group $RESOURCE_GROUP \
  --workspace-name $WORKSPACE_NAME \
  --query "identity.principal_id" -o tsv)

# Assign Key Vault Secrets User role
az role assignment create \
  --assignee-object-id "$COMPUTE_PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Key Vault Secrets User" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KEY_VAULT_NAME"

# Assign Storage Blob Data Contributor role
az role assignment create \
  --assignee-object-id "$COMPUTE_PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT"
```

- In the Azure Key Vault IAM, add **Key Vault Administrator** role to the relevant users or identities to enable one-time secret creation. For more information, see [Assign Azure roles using Azure CLI](https://learn.microsoft.com/en-us/azure/role-based-access-control/role-assignments-cli).
- Create a Key Vault secret containing the JFrog access token and username. For more information, see [Quickstart: Set and retrieve a secret from Azure Key Vault using Azure CLI](https://learn.microsoft.com/en-us/azure/key-vault/secrets/quick-create-cli).

```bash
az keyvault secret set \
  --vault-name $KEY_VAULT_NAME \
  --name artifactory-access-token-secret \
  --value '{"access_token":"<ACCESS TOKEN>","username":"<USERNAME>"}'
```

### JFrog Setup (R&R: JFrog Administrator or Project Admin)

### Prerequisites

- JFrog PyPI remote repository
- JFrog Docker virtual, local, and remote repositories
- JFrog Machine Learning Repository

### Configure Training (R&R: ML Engineer)

### Prerequisites

- Python >= 3.11
- Create pip.conf pointing to your JFrog platform (see pip.example.conf for reference)
- Azure CLI configured
- Login to Azure account, e.g. `az login --tenant <Tenant id>`, or any other preferred method.
- Ensure Docker BuildKit is enabled for secret support: `export DOCKER_BUILDKIT=1`

### 1. Set Up Python virtual environment

```bash
cd <project directory>
export PIP_CONFIG_FILE=<pip.conf file you want to use>
source setup_venv.sh
```

### 2. Build, Tag, and Push Docker Image

This step builds the training image. You can use the example as-is or replace its training logic in the `src/train.py` script.

Build the Docker image with the specified tag. The build uses Docker secrets for secure pip configuration:

```bash
export ARTIFACTORY_HOST=PLACEHOLDER, i.e. <my jfrog platform host> without http schema
export ARTIFACTORY_DOCKER_REPO=PLACEHOLDER i.e. local/virtual repository name
TAG=<DOCKER_TAG>
docker login ${ARTIFACTORY_HOST}

# Use Artifactory base image (if available)
docker build \
  --platform linux/amd64 \
  -t ${ARTIFACTORY_HOST}/${ARTIFACTORY_DOCKER_REPO}/azureml-training:${TAG} \
  -f docker/Dockerfile \
  --secret id=pipconfig,src=${PIP_CONFIG_FILE} \
  --build-arg BASE_IMAGE="${ARTIFACTORY_HOST}/${ARTIFACTORY_DOCKER_REPO}/python:3.13.11-slim" \
  --push \
  .
```

### 3. Run Training Pipeline

This step creates a new training job inside the AzureML workspace and runs it. The job uses the training Docker container we built and pushed in the previous steps.

- Clone config/config.example.yaml into config/config.yaml and update the missing 'PLACEHOLDER' values

```bash
cp config/config.example.yaml config/config.yaml
```

Submit the training pipeline:

```bash
cd <project directory>
python pipeline/training_pipeline.py
```

Once the training pipeline completes, you will get a URL for the Azure ML job it created. Use that to open the training job and follow its progress.

Deployment (with specific version):

```bash
cd <project directory>
python pipeline/deployment_pipeline.py --model-name iris-classifier --model-version v20260118123456
```

---

## Advanced Setup (With automatic secret rotation)

### 1. Initialize Setup Environment (R&R: Azure Administrator)

### Prerequisites

Before you begin, ensure you have the following:

- **Azure CLI** installed and authenticated (`az login`) 
- **Access to JFrog Artifactory** with admin permissions

### Create Azure Entra ID App Registration

```bash
# Set variables
APP_DISPLAY_NAME="jfrog-credentials-provider-azureml"
TENANT_ID=$(az account show --query tenantId -o tsv)

# Create the application
APP_CLIENT_ID=$(az ad app create \
  --display-name "$APP_DISPLAY_NAME" \
  --query appId -o tsv)

echo "Application Client ID: $APP_CLIENT_ID"
echo "Tenant ID: $TENANT_ID"
```

> **Important:** Save these values for later use:
>
> - `APP_CLIENT_ID` (also called `azure_app_client_id`)
> - `TENANT_ID` (also called `azure_tenant_id`)

### Create Service Principal

```bash
# Create Service Principal for the application
az ad sp create --id "$APP_CLIENT_ID"
```

### Configure Access Token Version

The credential provider uses `https://login.microsoftonline.com` as the issuer URL (instead of the older `https://sts.windows.net/`). Azure requires you to set `requestedAccessTokenVersion` to `2` for this to work.

```bash
# Get the object ID of the app created above
OBJECT_ID=$(az ad app show --id "$APP_CLIENT_ID" --query "id" -o tsv)

# Update the access token version
az rest --method PATCH \
  --headers "Content-Type=application/json" \
  --uri "https://graph.microsoft.com/v1.0/applications/$OBJECT_ID" \
  --body '{"api":{"requestedAccessTokenVersion": 2}}'
```

**Alternative: Configure via Azure Portal**

1. Navigate to **Azure Portal** → **Azure Active Directory** → **App registrations**
2. Search for your application by name or client ID
3. Go to **Manifest**
4. Set `"requestedAccessTokenVersion": 2` in the JSON
5. Click **Save**

---

### 2. Set Up AzureML Workspace and Azure Function for Token Rotation (R&R: Azure Administrator)

### Option 1 - Manual

### Prerequisites

- Artifactory Access Token and Username

### Set Up

#### 2a. Create AzureML Workspace with VNet

Create the AzureML Workspace and its dependent resources. For detailed guidance, see [Create workspaces with Azure CLI](https://learn.microsoft.com/en-us/azure/machine-learning/how-to-manage-workspace-cli?view=azureml-api-2).

**Create a Resource Group:**

```bash
RESOURCE_GROUP="<your-resource-group>"
LOCATION="swedencentral"

az group create --name $RESOURCE_GROUP --location $LOCATION
```

**Create a Virtual Network with two subnets:**

Subnet 1 is used for service endpoints and Function App VNet integration. Subnet 2 is used for the AzureML workspace private endpoint. For more information, see [Create a virtual network using Azure CLI](https://learn.microsoft.com/en-us/azure/virtual-network/manage-virtual-network#create-a-virtual-network).

```bash
VNET_NAME="<your-vnet-name>"

# Create VNet
az network vnet create \
  --name $VNET_NAME \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --address-prefix 10.0.0.0/16

# Create Subnet 1 — service endpoints + Function App delegation
az network vnet subnet create \
  --name subnet-1 \
  --resource-group $RESOURCE_GROUP \
  --vnet-name $VNET_NAME \
  --address-prefix 10.0.0.0/24 \
  --service-endpoints Microsoft.KeyVault Microsoft.Storage \
  --delegations Microsoft.App/environments

# Create Subnet 2 — workspace private endpoint (disable network policies to allow PE creation)
az network vnet subnet create \
  --name subnet-2 \
  --resource-group $RESOURCE_GROUP \
  --vnet-name $VNET_NAME \
  --address-prefix 10.0.1.0/24 \
  --private-endpoint-network-policies Disabled
```

**Create a Key Vault (RBAC-enabled):**

For more information, see [Create a Key Vault using Azure CLI](https://learn.microsoft.com/en-us/azure/key-vault/general/quick-create-cli).

```bash
KEY_VAULT_NAME="<your-key-vault-name>"

az keyvault create \
  --name $KEY_VAULT_NAME \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --enable-rbac-authorization true \
  --enable-purge-protection true
```

**Create a Storage Account:**

For more information, see [Create a storage account using Azure CLI](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-create?tabs=azure-cli).

```bash
STORAGE_ACCOUNT_NAME="<your-storage-account-name>"

az storage account create \
  --name $STORAGE_ACCOUNT_NAME \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --sku Standard_LRS \
  --kind StorageV2
```

**Create the AzureML Workspace:**

```bash
WORKSPACE_NAME="<your-workspace-name>"

az ml workspace create \
  --name $WORKSPACE_NAME \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --storage-account $STORAGE_ACCOUNT_NAME \
  --key-vault $KEY_VAULT_NAME
```

**Restrict workspace inbound access to deployer IPs (recommended):**

After creating the workspace and its private endpoint, restrict public network access to specific deployer IPs. The `ipAllowlist` property is only available via the REST API:

```bash
DEPLOYER_IPS='["<your-ip>", "<your-nat-ip>"]'

WORKSPACE_ID=$(az ml workspace show \
  --name $WORKSPACE_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "id" -o tsv)

az rest --method PATCH \
  --uri "https://management.azure.com${WORKSPACE_ID}?api-version=2024-04-01-preview" \
  --headers "Content-Type=application/json" \
  --body "{\"properties\": {\"ipAllowlist\": $DEPLOYER_IPS}}"
```

**RBAC — workspace and Key Vault:**

- In the Azure Machine Learning workspace IAM, add **Contributor** role to the relevant users or identities.
- In the Azure Key Vault IAM, add **Key Vault Administrator** role to enable one-time secret creation for the relevant users or identities.

For more information, see [Assign Azure roles using Azure CLI](https://learn.microsoft.com/en-us/azure/role-based-access-control/role-assignments-cli).

**Create the initial Key Vault secret:**

For more information, see [Quickstart: Set and retrieve a secret from Azure Key Vault using Azure CLI](https://learn.microsoft.com/en-us/azure/key-vault/secrets/quick-create-cli).

```bash
az keyvault secret set \
  --vault-name $KEY_VAULT_NAME \
  --name artifactory-access-token-secret \
  --value '{"access_token":"<ACCESS TOKEN>","username":"<USERNAME>"}'
```

---

#### 2b. Create the Azure Function App for Token Rotation

The Function App performs automatic OIDC-based token exchange with JFrog Artifactory and stores the resulting short-lived access token in Key Vault.

For detailed guidance, see [Create and manage function apps in a Flex Consumption plan](https://learn.microsoft.com/en-us/azure/azure-functions/flex-consumption-how-to).

**Create a blob container for the function deployment artifacts:**

```bash
az storage container create \
  --name azure-function-token-rotation \
  --account-name $STORAGE_ACCOUNT_NAME \
  --auth-mode login
```

**Create the Function App (Flex Consumption):**

For more information, see [Create a function in Azure from the command line](https://learn.microsoft.com/en-us/azure/azure-functions/how-to-create-function-azure-cli).

```bash
FUNCTION_APP_NAME="<your-function-app-name>"

az functionapp create \
  --name $FUNCTION_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --storage-account $STORAGE_ACCOUNT_NAME \
  --flexconsumption-location $LOCATION \
  --runtime python \
  --runtime-version 3.13 \
  --functions-version 4
```

**Restrict SCM (deployment) access to deployer IPs (recommended):**

The main site stays open so the HTTP trigger remains callable, but the SCM endpoint (used for zip deployment) is restricted to deployer IPs only:

```bash
DEPLOYER_IP="<your-deployer-ip>/32"

# Set SCM default action to Deny
az functionapp config access-restriction set \
  --name $FUNCTION_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --use-same-restrictions-for-scm-site false

az functionapp config access-restriction add \
  --name $FUNCTION_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --scm-site true \
  --rule-name "deployer" \
  --action Allow \
  --ip-address "$DEPLOYER_IP" \
  --priority 100

az functionapp config access-restriction set \
  --name $FUNCTION_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --scm-site true \
  --default-action Deny
```

**Enable system-assigned managed identity:**

For more information, see [Managed identities for App Service and Azure Functions](https://learn.microsoft.com/en-us/azure/app-service/overview-managed-identity).

```bash
FUNCTION_PRINCIPAL_ID=$(az functionapp identity assign \
  --name $FUNCTION_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "principalId" -o tsv)

echo "Function App Principal ID: $FUNCTION_PRINCIPAL_ID"
```

**Configure VNet integration (recommended):**

```bash
SUBNET_ID=$(az network vnet subnet show \
  --name subnet-1 \
  --resource-group $RESOURCE_GROUP \
  --vnet-name $VNET_NAME \
  --query "id" -o tsv)

az functionapp vnet-integration add \
  --name $FUNCTION_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --vnet $VNET_NAME \
  --subnet subnet-1
```

**Assign RBAC roles to the Function App managed identity:**

The function needs to read and write Key Vault secrets (for token rotation) and access storage (for Flex Consumption runtime). For more information, see [Assign Azure roles using Azure CLI](https://learn.microsoft.com/en-us/azure/role-based-access-control/role-assignments-cli).

```bash
# Key Vault Secrets Officer — read/write secrets for token rotation
az role assignment create \
  --assignee-object-id "$FUNCTION_PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Key Vault Secrets Officer" \
  --scope "/subscriptions/<subscription-id>/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KEY_VAULT_NAME"

# Storage Blob Data Owner — Flex Consumption deployment container
az role assignment create \
  --assignee-object-id "$FUNCTION_PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Owner" \
  --scope "/subscriptions/<subscription-id>/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT_NAME"

# Storage Account Contributor — Flex Consumption runtime operations
az role assignment create \
  --assignee-object-id "$FUNCTION_PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Storage Account Contributor" \
  --scope "/subscriptions/<subscription-id>/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT_NAME"

# Storage Table Data Contributor — Flex Consumption host runtime (timer triggers, etc.)
az role assignment create \
  --assignee-object-id "$FUNCTION_PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Storage Table Data Contributor" \
  --scope "/subscriptions/<subscription-id>/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT_NAME"

# Storage Queue Data Contributor — Flex Consumption host runtime (queue-based triggers)
az role assignment create \
  --assignee-object-id "$FUNCTION_PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Storage Queue Data Contributor" \
  --scope "/subscriptions/<subscription-id>/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT_NAME"
```

**Configure Function App settings:**

These environment variables control the token rotation behavior. For more information, see [Configure function app settings](https://learn.microsoft.com/en-us/azure/azure-functions/functions-how-to-use-azure-function-app-settings).

```bash
az functionapp config appsettings set \
  --name $FUNCTION_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --settings \
    KEY_VAULT_NAME="$KEY_VAULT_NAME" \
    ARTIFACTORY_URL="https://<your-jfrog-instance>.jfrog.io" \
    JFROG_OIDC_PROVIDER_NAME="<oidc-provider-name>" \
    AZURE_AD_TOKEN_AUDIENCE="<azure-app-client-id>" \
    ARTIFACTORY_TOKEN_SECRET_NAME="artifactory-access-token-secret" \
    SECRET_TTL="21600" \
    AzureWebJobsStorage__accountName="$STORAGE_ACCOUNT_NAME"
```

| Setting | Description |
|---------|-------------|
| `KEY_VAULT_NAME` | Name of the AzureML workspace Key Vault |
| `ARTIFACTORY_URL` | Base URL of your JFrog platform (e.g. `https://myorg.jfrog.io`) |
| `JFROG_OIDC_PROVIDER_NAME` | Name of the OIDC provider configured in JFrog (created in [step 6](#6-jfrog-artifactory-oidc-configuration-rr-jfrog-administrator-or-project-admin)) |
| `AZURE_AD_TOKEN_AUDIENCE` | Azure Entra ID App Registration Client ID (from [step 1](#create-azure-entra-id-app-registration)) |
| `ARTIFACTORY_TOKEN_SECRET_NAME` | Key Vault secret name where the rotated token is stored |
| `SECRET_TTL` | Token time-to-live in seconds (default: `21600` = 6 hours) |

---

#### 2c. Deploy the Function Code

Package and deploy the token rotation function to the Function App. For more information, see [Zip push deployment for Azure Functions](https://learn.microsoft.com/en-us/azure/azure-functions/deployment-zip-push).

```bash
# Create deployment package
cd 2_secret_rotation_function
zip -r function_app.zip . \
  -x "terraform/*" "__pycache__/*" ".venv/*" "*.pyc" \
     ".pytest_cache/*" "local.settings.json" ".env"

# Deploy to Azure
az functionapp deployment source config-zip \
  --resource-group $RESOURCE_GROUP \
  --name $FUNCTION_APP_NAME \
  --src function_app.zip \
  --build-remote true \
  --timeout 600

# Clean up
rm function_app.zip
cd -
```

**Invoke the function once** to perform the initial token rotation (otherwise the Key Vault secret is only updated on the next timer invocation):

```bash
FUNCTION_KEY=$(az functionapp keys list \
  --resource-group $RESOURCE_GROUP \
  --name $FUNCTION_APP_NAME \
  --query "functionKeys.default" -o tsv)

FUNCTION_URL="https://${FUNCTION_APP_NAME}.azurewebsites.net"

curl -s -X POST "$FUNCTION_URL/api/KeyVaultSecretRotation" \
  -H "x-functions-key: $FUNCTION_KEY" \
  -H "Content-Type: application/json"
```

A `200` response with `{"status": "ok", ...}` confirms the rotation is working. In case of any error or failure, see [Azure Function App troubleshooting documentation](https://learn.microsoft.com/en-us/troubleshoot/azure/azure-functions/welcome-azure-functions).

> **Important:** Save these values for later use:
>
> - `Function App Enterprise Application Object ID` (also called `function_app_identity_principal_id`) — this is the `$FUNCTION_PRINCIPAL_ID` value from the identity assignment step above

---

### Option 2 - Automation

### Set Up

#### Create AzureML Workspace, Storage Account and Azure Key Vault

### Prerequisites

- See [1_azure_machine_learning_workspace/README.md — Prerequisites](1_azure_machine_learning_workspace/README.md#prerequisites)

### Deploy

- See [1_azure_machine_learning_workspace/README.md — Usage](1_azure_machine_learning_workspace/README.md#usage).
  
  This creates the workspace, VNet, subnets, Key Vault, storage, compute, and a **private endpoint** for the workspace in subnet 2.

#### Create Azure Function App for Token Rotation

### Prerequisites

- See [2_secret_rotation_function/terraform/README.md — Prerequisites](2_secret_rotation_function/terraform/README.md#prerequisites)

### Deploy

- See [2_secret_rotation_function/terraform/README.md — Usage](2_secret_rotation_function/terraform/README.md#usage).

---

## 3. Federated Identity Credentials (R&R: Azure Administrator)

Federated credentials allow the Function App managed identity to exchange tokens with the Azure Entra ID App Registration. This establishes trust between your Function App and Azure Entra ID.

For more information, see the [Azure Managed Identities documentation](https://learn.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/).

### Prerequisites

```bash
APP_CLIENT_ID=<Entra ID App Registration client ID> #(also called `azure_app_client_id`)
TENANT_ID=<tenant id> #(also called `azure_tenant_id`)
FUNCTION_APP_NAME="<your-function-app-name>" #e.g. artifactory-token-rotation
RESOURCE_GROUP="<your-resource-group>"
```

### Get Function App principalId 

```bash

PRINCIPAL_ID=$(az functionapp identity show \
  --name $FUNCTION_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "principalId" \
  -o tsv)
```

### 4. Create Federated Identity Credential

```bash

FEDERATED_CREDENTIAL_NAME="function-app-federated-credential"
AUDIENCE="api://AzureADTokenExchange"
ISSUER="https://login.microsoftonline.com/$TENANT_ID/v2.0"

# Create the federated credential
az ad app federated-credential create \
  --id "$APP_CLIENT_ID" \
  --parameters "{
    \"name\": \"$FEDERATED_CREDENTIAL_NAME\",
    \"issuer\": \"$ISSUER\",
    \"subject\": \"$PRINCIPAL_ID\",
    \"audiences\": [\"$AUDIENCE\"],
    \"description\": \"Federated credential for Function App managed identity\"
  }"
```

### Verify Federated Credential

```bash
# List federated credentials
az ad app federated-credential list --id "$APP_CLIENT_ID"
```

You should see your federated credential with:

- `issuer`: `https://login.microsoftonline.com/<TENANT_ID>/v2.0`
- `subject`: Your Function App identity object ID
- `audiences`: `["api://AzureADTokenExchange"]`

### 5. Update Azure Entra ID App Registration by enabling Assignment Required (R&R: Azure Administrator)

By default, **Assignment Required** is set to **No** on the enterprise application. This means any user or service principal in your tenant can acquire an access token from the app registration. Since the JFrog Credential Provider exchanges this token with Artifactory for image pull credentials, leaving this open is a security concern.

Setting **Assignment Required** to **Yes** ensures that only explicitly assigned principals can obtain tokens from the app.

**Enable via Azure Portal:**

1. Navigate to **Azure Portal** → **Enterprise applications**
2. Search for your application by name
3. Go to **Properties**
4. Set **Assignment required?** to **Yes**
5. Click **Save**

**Enable via Azure CLI:**

```bash
SPN_OBJECT_ID=$(az ad sp list --filter "appId eq '$APP_CLIENT_ID'" --query "[0].id" -o tsv)

az rest --method PATCH \
  --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$SPN_OBJECT_ID" \
  --headers "Content-Type=application/json" \
  --body '{"appRoleAssignmentRequired": true}'
```

After enabling this, the credential provider will fail to obtain tokens because the Function App's own service principal is not assigned. To fix this, assign the Function App service principal to the App Registration service principal by creating an app role and assigning it:

**1. Create an App Role**

Navigate to **Azure Portal** → **App registrations** → your app → **App roles** → **Create app role**:

- **Display name**: e.g., `Task.Read`
- **Allowed member types**: Applications
- **Value**: `Task.Read`
- **Description**: Role for credential provider access

Or via CLI:

```bash
OBJECT_ID=$(az ad app show --id "$APP_CLIENT_ID" --query "id" -o tsv)

az rest --method PATCH \
  --uri "https://graph.microsoft.com/v1.0/applications/$OBJECT_ID" \
  --headers "Content-Type=application/json" \
  --body '{
    "appRoles": [{
      "allowedMemberTypes": ["Application"],
      "displayName": "Task.Read",
      "id": "'$(uuidgen)'",
      "isEnabled": true,
      "description": "Role for credential provider access",
      "value": "Task.Read"
    }]
  }'
```

**2. Get the SPN Object ID and Role ID**

```bash
RESOURCE_SPN_OBJECT_ID=$(az ad sp show --id "$APP_CLIENT_ID" --query "id" -o tsv)
ROLE_ID=$(az ad sp show --id "$RESOURCE_SPN_OBJECT_ID" --query "appRoles[?value=='Task.Read'].id" -o tsv)
```

**3. Get the Principal ID of the Caller (Function App Managed Identity)**

```bash

PRINCIPAL_ID=$(az functionapp identity show \
  --name $FUNCTION_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "principalId" \
  -o tsv)
```

**4. Assign the Function App Managed Identity to Entra ID App Registration principal ID**

```bash
az rest --method POST \
  --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$PRINCIPAL_ID/appRoleAssignments" \
  --headers "Content-Type=application/json" \
  --body "{
    \"principalId\": \"$PRINCIPAL_ID\",
    \"resourceId\": \"$RESOURCE_SPN_OBJECT_ID\",
    \"appRoleId\": \"$ROLE_ID\"
  }"
```

After this, the credential provider will continue to work via the federated credentials on the Function App managed identity, but other apps in your tenant will no longer be able to obtain tokens from this app registration.

---

### 6. JFrog Artifactory OIDC Configuration (R&R: JFrog Administrator or Project Admin)

Configure JFrog Artifactory to accept OIDC tokens from Azure. This involves creating an OIDC provider and an identity mapping in Artifactory.

For more information, see the [JFrog Artifactory OIDC Documentation](https://www.jfrog.com/confluence/display/JFROG/Access+Tokens#AccessTokens-OIDCIntegration).

### Prerequisites
```bash
TENANT_ID=<tenant id> #(also called `azure_tenant_id`)
APP_CLIENT_ID=<Entra ID App Registration client ID> #(also called `azure_app_client_id`)
PRINCIPAL_ID=<Function App principalId> #Principal ID of the caller (Function App Managed Identity)
```

#### Get Artifactory Admin Token

You'll need an Artifactory admin access token to configure OIDC. If you don't have one, create it in Artifactory under **Administration** → **Identity and Access** → **Access Tokens**.

```bash
# Set your Artifactory details
ARTIFACTORY_URL="your-instance.jfrog.io"
ARTIFACTORY_ADMIN_TOKEN="your-admin-access-token"
ARTIFACTORY_USER="azure-ml-user"  # User that will be mapped to OIDC tokens
OIDC_PROVIDER_NAME="azure-ml-oidc-provider"  # Choose a name
```

### Create OIDC Provider in Artifactory

```bash
curl -X POST "https://$ARTIFACTORY_URL/access/api/v1/oidc" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ARTIFACTORY_ADMIN_TOKEN" \
  -d "{
    \"name\": \"$OIDC_PROVIDER_NAME\",
    \"issuer_url\": \"https://login.microsoftonline.com/$TENANT_ID/v2.0\",
    \"description\": \"OIDC provider for Azure ML\",
    \"provider_type\": \"Azure\",
    \"token_issuer\": \"https://login.microsoftonline.com/$TENANT_ID/v2.0\",
    \"audience\": \"$APP_CLIENT_ID\",
    \"use_default_proxy\": false
  }"
```

For more details, see the [JFrog REST API documentation for creating OIDC configuration](https://jfrog.com/help/r/jfrog-rest-apis/create-oidc-configuration).

### Create Identity Mapping for OIDC Provider in Artifactory

The identity mapping tells Artifactory how to map Azure OIDC tokens to Artifactory users.

> **Important:** The default is **6 hours (21600 seconds)**. The example below uses 21600 seconds to verify the token is revocable.

For more details, see the [JFrog Revocable Expiry Threshold](https://jfrog.com/help/r/jfrog-platform-administration-documentation/use-the-revocable-and-persistency-thresholds).

```bash
curl -X POST "https://$ARTIFACTORY_URL/access/api/v1/oidc/$OIDC_PROVIDER_NAME/identity_mappings" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ARTIFACTORY_ADMIN_TOKEN" \
  -d "{
    \"name\": \"$OIDC_PROVIDER_NAME\",
    \"description\": \"Azure OIDC identity mapping\",
    \"claims\": {
      \"aud\": \"$APP_CLIENT_ID\",
      \"sub\": \"$PRINCIPAL_ID\",
      \"iss\": \"https://login.microsoftonline.com/$TENANT_ID/v2.0\"
    },
    \"token_spec\": {
      \"username\": \"$ARTIFACTORY_USER\",
      \"scope\": \"applied-permissions/user\",
      \"audience\": \"*@*\",
      \"expires_in\": 21600
    },
    \"priority\": 1
  }"
```

**📝 Configuration Notes**

- The `claims.aud` must match your `azure_app_client_id`
- The `claims.iss` must match the Azure AD issuer URL: `https://login.microsoftonline.com/$TENANT_ID/v2.0`
- The `claims.sub` must match the Function App Enterprise Application Object ID (use `function_app_identity_principal_id` from Terraform output) 
- The `token_spec.username` must be an existing Artifactory user
- Ensure the user has permissions to pull images from your repositories



For more information, see the [JFrog Platform Administration documentation on identity mappings](https://jfrog.com/help/r/jfrog-platform-administration-documentation/identity-mappings).

### Verify OIDC Provider

```bash
# List OIDC providers
curl -X GET "https://$ARTIFACTORY_URL/access/api/v1/oidc" \
  -H "Authorization: Bearer $ARTIFACTORY_ADMIN_TOKEN" | jq

# Get specific provider details
curl -X GET "https://$ARTIFACTORY_URL/access/api/v1/oidc/$OIDC_PROVIDER_NAME" \
  -H "Authorization: Bearer $ARTIFACTORY_ADMIN_TOKEN" | jq
```

---

### 7. Deploy function code

```bash
cd 2_secret_rotation_function/terraform
./deploy-function.sh
```

#### The script deploys the function and then **invokes it once** so the Key Vault secret is updated immediately with a real Artifactory access token (otherwise the token would only be refreshed on the next timer invocation). In case of any error or failure, please see [Azure Function App troubleshooting documentation](https://learn.microsoft.com/en-us/troubleshoot/azure/azure-functions/welcome-azure-functions).

---

### 8. You are ready to set up the AzureML and JFrog development environment

See: [JFrog Setup (R&R: JFrog Administrator or Project Admin)](#jfrog-setup-rr-jfrog-administrator-or-project-admin)

---

## Troubleshooting

### Docker Build Issues

- Ensure BuildKit is enabled: `export DOCKER_BUILDKIT=1`
- Verify `pip.conf` exists and contains valid credentials
- Check that Artifactory Docker registry is accessible

### Pipeline Issues

- Verify Azure credentials are correctly set
- Check that the Docker image was successfully pushed to Artifactory
- Ensure Azure Key Vault has the required secrets

## Cleanup

To tear down the automation, destroy in this order: first [2_secret_rotation_function/terraform/README.md — Cleanup](2_secret_rotation_function/terraform/README.md#cleanup) (function app), then [1_azure_machine_learning_workspace/README.md — Cleanup](1_azure_machine_learning_workspace/README.md#cleanup) (workspace, VNet, Key Vault, storage).

## License

See LICENSE file for details.