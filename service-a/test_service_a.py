"""Tests for service-a.

Loads the service's app.py by file path so the suite runs both in isolation
(``pytest service-a``) and as part of a whole-repo run without module-name
collisions between the three services' identically named ``app`` modules.
"""
import importlib.util
import os
from unittest.mock import patch

import pytest

_APP_PATH = os.path.join(os.path.dirname(__file__), "app.py")
_spec = importlib.util.spec_from_file_location("service_a_app", _APP_PATH)
service_a = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(service_a)


@pytest.fixture
def client():
    service_a.app.config["TESTING"] = True
    with service_a.app.test_client() as c:
        yield c


def test_health_returns_ok(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.get_json() == {"service": "service-a", "status": "ok"}


def test_request_forwards_to_service_b(client):
    with patch.object(service_a.requests, "post") as mock_post:
        mock_post.return_value.status_code = 200
        resp = client.post("/request", json={"hello": "world"})

    assert resp.status_code == 200
    body = resp.get_json()
    assert body["status"] == "accepted"
    assert body["trace_id"]  # a trace id is always generated/propagated
    mock_post.assert_called_once()


def test_request_returns_502_when_service_b_unavailable(client):
    with patch.object(service_a.requests, "post", side_effect=Exception("boom")):
        resp = client.post("/request", json={})

    assert resp.status_code == 502
    assert resp.get_json() == {"error": "service-b unavailable"}


def test_unknown_route_returns_404(client):
    resp = client.get("/does-not-exist")
    assert resp.status_code == 404
    assert resp.get_json() == {"error": "not found"}
