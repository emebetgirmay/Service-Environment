import pytest
from fastapi.testclient import TestClient
from app import app

client = TestClient(app)

def test_health():
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["service"] == "service-b"
    assert data["status"] == "healthy"

def test_not_found():
    response = client.get("/nonexistent")
    assert response.status_code == 404
