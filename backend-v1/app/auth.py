"""Bearer token authentication for the WoundOS API."""

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.config import Settings, get_settings

_scheme = HTTPBearer()


async def verify_token(
    credentials: HTTPAuthorizationCredentials = Depends(_scheme),
    settings: Settings = Depends(get_settings),
) -> str:
    """Validate the bearer token against the configured API token.

    Returns the token string on success; raises 401 on failure.
    """
    if credentials.credentials != settings.api_token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"error": "unauthorized", "detail": "Invalid or missing bearer token"},
        )
    return credentials.credentials
