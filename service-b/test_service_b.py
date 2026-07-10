"""Tests for service-b.

Loads the service's app.py by file path so the suite runs both in isolation
(``pytest service-b``) and as part of a whole-repo run without module-name
collisions between the three services' identically named ``app`` modules.
"""
import importlib.util
import os
from unittest.mock import patch

import pytest

_APP_PATH = os.path.join(os.path.dirname(__file__), "app.py")
_spec = importlib.util.spec_from_file_location("service_b_app", _APP_PATH)
service_b = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(service_b)


@pytest.fixture
def client():
    service_b.app.config["TESTING"] = True
    with service_b.app.test_client() as c:
        yield c


def test_health_returns_ok(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.get_json() == {"service": "service-b", "status": "ok"}


def test_process_forwards_to_service_c(client):
    with patch.object(service_b.requests, "post") as mock_post:
        mock_post.return_value.status_code = 200
        resp = client.post("/process", json={"hello": "world"})

    assert resp.status_code == 200
    assert resp.get_json() == {"status": "forwarded"}
    mock_post.assert_called_once()


def test_process_returns_502_when_service_c_unavailable(client):
    with patch.object(service_b.requests, "post", side_effect=Exception("boom")):
        resp = client.post("/process", json={})

    assert resp.status_code == 502
    assert resp.get_json() == {"error": "service-c unavailable"}


def test_unknown_route_returns_404(client):
    resp = client.get("/does-not-exist")
    assert resp.status_code == 404
    assert resp.get_json() == {"error": "not found"}
