"""
Azure Function: JFrog Artifactory Token Rotation
Triggered by Key Vault SecretNearExpiry event via Event Grid.
Exchanges an Azure AD token for a new JFrog access token using OIDC token exchange,
then stores the new token back in Key Vault.
"""

import os
import json
import logging
import requests
import azure.functions as func
from azure.identity import DefaultAzureCredential, ManagedIdentityCredential
from azure.keyvault.secrets import SecretClient
from datetime import datetime, timezone

app = func.FunctionApp()

logger = logging.getLogger("jfrog-token-rotation")


def _get_credential():
    """
    Get Azure credential.
    Prefers user-assigned managed identity if AZURE_CLIENT_ID is set,
    otherwise falls back to DefaultAzureCredential.
    """
    client_id = os.environ.get("AZURE_CLIENT_ID")
    if client_id:
        logger.info("Using user-assigned managed identity with client_id: %s", client_id)
        return ManagedIdentityCredential(client_id=client_id)
    logger.info("Using DefaultAzureCredential")
    return DefaultAzureCredential()


def _get_key_vault_client(vault_name: str) -> SecretClient:
    """Get Azure Key Vault secret client."""
    vault_url = f"https://{vault_name}.vault.azure.net"
    credential = _get_credential()
    return SecretClient(vault_url=vault_url, credential=credential)


def _get_azure_ad_token(audience: str) -> str:
    """
    Acquire an Azure AD token for the given audience (Entra ID app registration).
    This token will be exchanged for a JFrog access token.
    """
    credential = _get_credential()
    token = credential.get_token(audience)
    return token.token


def _exchange_token_for_jfrog_access_token(
    artifactory_url: str,
    azure_ad_token: str,
    provider_name: str
) -> dict:
    """
    Exchange an Azure AD token for a JFrog access token using OIDC token exchange.

    Args:
        artifactory_url: Base URL of the Artifactory instance
        azure_ad_token: Azure AD token from Entra ID
        provider_name: Name of the OIDC provider configured in JFrog

    Returns:
        Dictionary with access_token, token_type, and expires_in
    """
    exchange_url = f"{artifactory_url.rstrip('/')}/access/api/v1/oidc/token"

    payload = {
        "grant_type": "urn:ietf:params:oauth:grant-type:token-exchange",
        "subject_token_type": "urn:ietf:params:oauth:token-type:id_token",
        "subject_token": azure_ad_token,
        "provider_name": provider_name,
    }

    response = requests.post(exchange_url, data=payload, timeout=30)
    response.raise_for_status()

    return response.json()


def _store_token_in_key_vault(
    vault_name: str,
    secret_name: str,
    token_value: str,
    expires_in: int = None
) -> None:
    """
    Store the new JFrog access token in Key Vault.
    Optionally sets expiry based on the token's expires_in value.
    """
    client = _get_key_vault_client(vault_name)

    # Set expiry if token has an expiration
    kwargs = {}
    if expires_in and expires_in > 0:
        from datetime import timedelta
        expiry_date = datetime.now(timezone.utc) + timedelta(seconds=expires_in)
        kwargs["expires_on"] = expiry_date
        logger.info("Setting secret expiry to %s", expiry_date.isoformat())

    client.set_secret(
        secret_name,
        token_value,
        content_type="application/json",
        **kwargs
    )
    logger.info("✓ Token stored in Key Vault secret: %s", secret_name)


def rotate_token() -> None:
    """
    Core rotation logic: exchange Azure AD token for a new JFrog token
    and store it in Key Vault.
    """
    # Read configuration from environment variables
    vault_name = os.environ["KEY_VAULT_NAME"]
    artifactory_url = os.environ["ARTIFACTORY_URL"]
    provider_name = os.environ["JFROG_OIDC_PROVIDER_NAME"]
    audience = os.environ["AZURE_AD_TOKEN_AUDIENCE"]
    secret_ttl = os.environ["SECRET_TTL"]

    token_secret_name = os.environ.get("ARTIFACTORY_TOKEN_SECRET_NAME", "artifactory-access-token")



    logger.info("Starting token rotation for secret: %s", token_secret_name)

    # Step 1: Get Azure AD token for the Entra ID app registration
    logger.info("Acquiring Azure AD token for audience: %s", audience)
    azure_ad_token = _get_azure_ad_token(audience)
    logger.info("✓ Azure AD token acquired")

    # Step 2: Exchange for JFrog access token
    logger.info("Exchanging token with JFrog at: %s", artifactory_url)
    token_response = _exchange_token_for_jfrog_access_token(
        artifactory_url=artifactory_url,
        azure_ad_token=azure_ad_token,
        provider_name=provider_name,
    )
    jfrog_access_token = token_response["access_token"]
    jfrog_username = token_response["username"]
    expires_in = token_response.get("expires_in")
    logger.info("✓ JFrog access token obtained (expires_in=%s seconds)", expires_in)

    # Step 3: Store new token in Key Vault
    secret_json = json.dumps({
        "access_token": jfrog_access_token,
        "username": jfrog_username,
    })
    _store_token_in_key_vault(
        vault_name=vault_name,
        secret_name=token_secret_name,
        token_value=secret_json,
        expires_in=expires_in,
    )

    logger.info("✓ Token rotation completed for secret: %s", token_secret_name)

def _ttl_seconds_to_cron() -> str:
    ttl_seconds = int(os.environ.get("SECRET_TTL", "21600"))  # e.g. 6 hours
    # Run at 80% of TTL
    interval_seconds = int(ttl_seconds * 0.8)
    logger.info("Interval seconds: %s", interval_seconds)
    
    if interval_seconds < 3600:
        minutes = max(1, interval_seconds // 60)
        return f"0 */{minutes} * * * *"
    if interval_seconds < 86400:
        hours = max(1, interval_seconds // 3600)
        return f"0 0 */{hours} * * *"

@app.function_name(name="KeyVaultSecretRotation")

@app.timer_trigger(schedule=_ttl_seconds_to_cron(), arg_name="myTimer", run_on_startup=False,
              use_monitor=False)
# @app.timer_trigger(schedule="0 0 */4 * * *", arg_name="myTimer", run_on_startup=False,
#               use_monitor=False)
def key_vault_secret_rotation(myTimer: func.TimerRequest) -> None:
    """
    Azure Function triggered by Key Vault SecretNearExpiry event via Event Grid.
    Rotates the JFrog Artifactory access token by performing OIDC token exchange.
    """

    logger.info("Event subject: %s", event.subject)



    try:
        rotate_token()
    except KeyError as e:
        logger.error("Missing required environment variable: %s", e)
        raise
    except requests.exceptions.HTTPError as e:
        logger.error("HTTP error during token exchange: %s", e)
        logger.error("Response body: %s", e.response.text if e.response else "N/A")
        raise
    except Exception as e:
        logger.error("Token rotation failed: %s", e)
        raise