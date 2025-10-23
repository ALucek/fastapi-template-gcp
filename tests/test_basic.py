import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app.config import Settings
from app.main import create_app


def test_healthz_ok():
    client = TestClient(create_app())
    r = client.get("/v1/healthz")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


def test_hello_ok_without_app_auth():
    client = TestClient(create_app())
    r = client.get("/v1/hello")
    assert r.status_code == 200
    assert r.json()["message"] == "hello, authorized client"


def test_invalid_port_value(monkeypatch):
    monkeypatch.setenv("PORT", "not-a-number")

    with pytest.raises(ValidationError):
        Settings()

