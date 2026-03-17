"""
Azure Function: JFrog Artifactory Token Rotation
Triggered by Timer or HTTP POST.
Exchanges an Azure Entra ID token for a new JFrog access token using OIDC token exchange,
then stores the new token back in Key Vault.
When invoked via HTTP (e.g. POST), returns appropriate HTTP status and error message on failure.
"""

import os
import json
import logging
import requests
import azure.functions as func
from azure.identity import DefaultAzureCredential, ManagedIdentityCredential
from azure.keyvault.secrets import SecretClient
from azure.core.exceptions import HttpResponseError, ResourceNotFoundError
from datetime import datetime, timezone

app = func.FunctionApp()

logger = logging.getLogger("jfrog-token-rotation")


class RotationError(Exception):
    """Error during token rotation with HTTP status code for invocation response."""
    def __init__(self, status_code: int, message: str, details: str = None):
        self.status_code = status_code
        self.message = message
        self.details = details
        super().__init__(message)


def _get_credential():
    """
    Get Azure credential.
    Uses a User-Assigned Managed Identity if 'UAMI_CLIENT_ID' is set,
    otherwise falls back to DefaultAzureCredential (which handles System-Assigned MI).
    """
    # Use a distinct variable for the Managed Identity's Client ID
    mi_client_id = os.environ.get("UAMI_CLIENT_ID") 
    
    if mi_client_id:
       logger.info("Using user-assigned managed identity with client_id: %s", mi_client_id)
       return ManagedIdentityCredential(client_id=mi_client_id)
    else:
      logger.info("Using DefaultAzureCredential")
      return DefaultAzureCredential()


def _get_key_vault_client(vault_name: str) -> SecretClient:
    """Get Azure Key Vault secret client."""
    vault_url = f"https://{vault_name}.vault.azure.net"
    credential = _get_credential()
    return SecretClient(vault_url=vault_url, credential=credential)


def _get_azure_ad_token(audience: str) -> str:
    """
    Acquire an Azure Entra ID token for the given audience (Entra ID app registration).
    This token will be exchanged for a JFrog access token.
    """
    try:
        credential = _get_credential()
        logger.info("Getting Azure Entra ID token for scope: %s", audience)
        token = credential.get_token(audience)
        logger.info("Azure Entra ID token obtained successfully.")
        return token.token
    except Exception as e:
        err_msg = str(e)
        if "AuthenticationFailed" in type(e).__name__ or "CredentialUnavailable" in type(e).__name__:
            raise RotationError(401, "Azure Entra ID authentication failed", err_msg)
        if "403" in err_msg or "Forbidden" in err_msg:
            raise RotationError(403, "Azure Entra ID access forbidden", err_msg)
        raise RotationError(502, "Failed to acquire Azure Entra ID token", err_msg)


def _exchange_token_for_jfrog_access_token(
    artifactory_url: str,
    azure_ad_token: str,
    provider_name: str,
) -> dict:
    """
    Exchange an Azure Entra ID token for a JFrog access token using OIDC token exchange.

    Args:
        artifactory_url: Base URL of the Artifactory instance
        azure_ad_token: Azure Entra ID token from Entra ID
        provider_name: Name of the OIDC provider configured in JFrog

    Returns:
        Dictionary with access_token, token_type, and expires_in
    """
    exchange_url = f"{artifactory_url.rstrip('/')}/access/api/v1/oidc/token"

    payload = {
        "grant_type": "urn:ietf:params:oauth:grant-type:token-exchange",
        "subject_token_type": "urn:ietf:params:oauth:token-type:id_token",
        "subject_token": f"{azure_ad_token}",
        "provider_name": f"{provider_name}",
        "provider_type": "oidc-azure",
    }
    payload_json = json.dumps(payload)
    try:
        response = requests.post(exchange_url, data=payload_json, timeout=30, headers={"Content-Type": "application/json"})
        response.raise_for_status()
        return response.json()
    except requests.exceptions.HTTPError as e:
        status = e.response.status_code if e.response is not None else 502
        body = (e.response.text or "") if e.response is not None else str(e)
        raise RotationError(status, f"JFrog OIDC token exchange failed: {e}", body)
    except requests.exceptions.RequestException as e:
        raise RotationError(502, "JFrog OIDC token exchange request failed", str(e))


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
    try:
        client = _get_key_vault_client(vault_name)
    except Exception as e:
        err_msg = str(e)
        if "403" in err_msg or "Forbidden" in err_msg:
            raise RotationError(403, "Key Vault access forbidden", err_msg)
        if "404" in err_msg or "Not Found" in err_msg:
            raise RotationError(404, "Key Vault not found", err_msg)
        raise RotationError(502, "Failed to create Key Vault client", err_msg)

    kwargs = {}
    if expires_in and expires_in > 0:
        from datetime import timedelta
        expiry_date = datetime.now(timezone.utc) + timedelta(seconds=expires_in)
        kwargs["expires_on"] = expiry_date
        logger.info("Setting secret expiry to %s", expiry_date.isoformat())

    try:
        client.set_secret(
            secret_name,
            token_value,
            content_type="application/json",
            **kwargs
        )
        logger.info("✓ Token stored in Key Vault secret: %s", secret_name)
    except ResourceNotFoundError as e:
        raise RotationError(404, "Key Vault or secret resource not found", str(e))
    except HttpResponseError as e:
        status = getattr(e, "status_code", 500)
        raise RotationError(status, "Key Vault request failed", str(e))
    except Exception as e:
        raise RotationError(500, "Failed to store secret in Key Vault", str(e))


def rotate_token() -> None:
    """
    Core rotation logic: exchange Azure Entra ID token for a new JFrog token
    and store it in Key Vault.
    Raises RotationError with appropriate status_code and message on failure.
    """
    required_env = ["KEY_VAULT_NAME", "ARTIFACTORY_URL", "JFROG_OIDC_PROVIDER_NAME", "AZURE_AD_TOKEN_AUDIENCE", "SECRET_TTL"]
    missing = [k for k in required_env if not os.environ.get(k)]
    if missing:
        raise RotationError(503, "Missing required environment variable(s)", ", ".join(missing))

    vault_name = os.environ["KEY_VAULT_NAME"]
    artifactory_url = os.environ["ARTIFACTORY_URL"]
    provider_name = os.environ["JFROG_OIDC_PROVIDER_NAME"]
    audience = os.environ["AZURE_AD_TOKEN_AUDIENCE"]
    token_secret_name = os.environ.get("ARTIFACTORY_TOKEN_SECRET_NAME", "artifactory-access-token-secret")

    logger.info("Starting token rotation for secret: %s", token_secret_name)

    # Step 1: Get Azure Entra ID token for the Entra ID app registration
    logger.info("Acquiring Azure Entra ID token for audience: %s", audience)
    azure_ad_token = _get_azure_ad_token(audience)

    # Step 2: Exchange for JFrog access token
    logger.info("Exchanging token with JFrog at: %s", artifactory_url)
    token_response = _exchange_token_for_jfrog_access_token(
        artifactory_url=artifactory_url,
        azure_ad_token=azure_ad_token,
        provider_name=provider_name,
    )
    jfrog_access_token = token_response.get("access_token")
    jfrog_username = token_response.get("username")
    if not jfrog_access_token or not jfrog_username:
        raise RotationError(502, "JFrog token response missing access_token or username", json.dumps(token_response))
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


def _error_response(status_code: int, message: str, details: str = None):
    """Build JSON body and dict for HTTP error response."""
    body = {"error": message}
    if details:
        body["details"] = details
    return json.dumps(body), body


# ─────────────────────────────────────────────────────────────────────────────
# HTTP trigger: invoke via POST to get HTTP status and error message in response
# e.g. curl -X POST "https://${HOSTNAME}/api/KeyVaultSecretRotation"
# ─────────────────────────────────────────────────────────────────────────────

@app.function_name(name="KeyVaultSecretRotationHttp")
@app.route(route="KeyVaultSecretRotation", methods=["POST"])
def key_vault_secret_rotation_http(req: func.HttpRequest) -> func.HttpResponse:
    """
    HTTP-triggered rotation. Returns appropriate status code and JSON body on error.
    Use this for direct invocation when you need the response status (e.g. 404, 401, 502).
    """
    try:
        rotate_token()
        return func.HttpResponse(
            body=json.dumps({"status": "ok", "message": "Token rotation completed"}),
            status_code=200,
            mimetype="application/json",
        )
    except RotationError as e:
        body_str, _ = _error_response(e.status_code, e.message, e.details)
        logger.error("Token rotation failed [%s]: %s - %s", e.status_code, e.message, e.details)
        return func.HttpResponse(body=body_str, status_code=e.status_code, mimetype="application/json")
    except Exception as e:
        body_str, _ = _error_response(500, "Token rotation failed", str(e))
        logger.exception("Token rotation failed")
        return func.HttpResponse(body=body_str, status_code=500, mimetype="application/json")


# ─────────────────────────────────────────────────────────────────────────────
# Timer trigger: runs on schedule; on failure, run is marked failed (admin invoke returns 500)
# ─────────────────────────────────────────────────────────────────────────────

@app.function_name(name="KeyVaultSecretRotation")
@app.timer_trigger(schedule=_ttl_seconds_to_cron(), arg_name="myTimer", run_on_startup=False, use_monitor=False)
def key_vault_secret_rotation(myTimer: func.TimerRequest) -> None:
    """
    Azure Function triggered by Timer.
    Rotates the JFrog Artifactory access token by performing OIDC token exchange.
    For direct invocation with HTTP status and error message, use POST /api/KeyVaultSecretRotation instead.
    """
    try:
        rotate_token()
    except RotationError as e:
        logger.error("Token rotation failed [%s]: %s - %s", e.status_code, e.message, e.details)
        raise
    except Exception as e:
        logger.exception("Token rotation failed")
        raise