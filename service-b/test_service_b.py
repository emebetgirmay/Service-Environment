import pytest
from unittest.mock import patch, MagicMock
import sys
import os

# Clean up module cache to prevent conflict across directories
sys.modules.pop("app", None)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(1, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
from app import app

@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as client:
        yield client

def test_health(client):
    response = client.get("/health")
    assert response.status_code == 200
    data = response.get_json()
    assert data["service"] == "service-b"
    assert data["status"] == "ok"

@patch("app.requests.post")
def test_process_success(mock_post, client):
    mock_response = MagicMock()
    mock_response.status_code = 200
    mock_post.return_value = mock_response

    response = client.post("/process", json={"key": "value"})
    assert response.status_code == 200
    data = response.get_json()
    assert data["status"] == "forwarded"

@patch("app.requests.post")
def test_process_failure(mock_post, client):
    mock_post.side_effect = Exception("Connection refused")

    response = client.post("/process", json={"key": "value"})
    assert response.status_code == 502
    data = response.get_json()
    assert data["error"] == "service-c unavailable"

def test_404(client):
    response = client.get("/non-existent-route")
    assert response.status_code == 404
    data = response.get_json()
    assert data["error"] == "not found"
