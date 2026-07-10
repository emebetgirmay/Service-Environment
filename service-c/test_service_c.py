"""Tests for service-c.

Loads the service's app.py by file path so the suite runs both in isolation
(``pytest service-c``) and as part of a whole-repo run without module-name
collisions between the three services' identically named ``app`` modules.
"""
import importlib.util
import os
from unittest.mock import patch

import pytest

_APP_PATH = os.path.join(os.path.dirname(__file__), "app.py")
_spec = importlib.util.spec_from_file_location("service_c_app", _APP_PATH)
service_c = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(service_c)


@pytest.fixture
def client():
    service_c.app.config["TESTING"] = True
    with service_c.app.test_client() as c:
        yield c


def test_health_returns_ok(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.get_json() == {"service": "service-c", "status": "ok"}


def test_execute_calls_back_to_service_a(client):
    with patch.object(service_c.requests, "post") as mock_post:
        mock_post.return_value.status_code = 200
        resp = client.post("/execute", json={"hello": "world"})

    assert resp.status_code == 200
    assert resp.get_json() == {"status": "executed"}
    mock_post.assert_called_once()


def test_execute_returns_502_when_callback_fails(client):
    with patch.object(service_c.requests, "post", side_effect=Exception("boom")):
        resp = client.post("/execute", json={})

    assert resp.status_code == 502
    assert resp.get_json() == {"error": "callback failed"}


def test_unknown_route_returns_404(client):
    resp = client.get("/does-not-exist")
    assert resp.status_code == 404
    assert resp.get_json() == {"error": "not found"}
