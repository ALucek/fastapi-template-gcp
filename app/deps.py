from fastapi import Depends
from app.security import require_api_key

# Common dependency for protected endpoints
def auth_dep(_: None = Depends(require_api_key)):
    return True
