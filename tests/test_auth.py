from fastapi.testclient import TestClient
from app.main import create_app

def test_requires_api_key(monkeypatch):
    monkeypatch.setenv("API_KEY", "secret123")
    client = TestClient(create_app())

    # missing key -> 401
    r = client.get("/v1/hello")
    assert r.status_code == 401

    # wrong key -> 401
    r = client.get("/v1/hello", headers={"x-api-key": "bad"})
    assert r.status_code == 401

    # correct key -> 200
    r = client.get("/v1/hello", headers={"x-api-key": "secret123"})
    assert r.status_code == 200
    assert r.json()["message"] == "hello, authorized client"
