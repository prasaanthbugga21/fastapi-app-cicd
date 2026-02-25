"""
Unit tests for FastAPI application.
Tests cover health endpoints, API routes, and error handling.
"""

import pytest
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


class TestHealthEndpoints:
    def test_liveness_returns_200(self):
        response = client.get("/healthz/live")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "alive"
        assert "version" in data

    def test_readiness_returns_200_when_healthy(self):
        response = client.get("/healthz/ready")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "ready"
        assert "checks" in data


class TestRootEndpoint:
    def test_root_returns_service_info(self):
        response = client.get("/")
        assert response.status_code == 200
        data = response.json()
        assert data["service"] == "fastapi-app"
        assert "version" in data
        assert "environment" in data


class TestItemsEndpoints:
    def test_list_items_returns_empty_list(self):
        response = client.get("/api/v1/items")
        assert response.status_code == 200
        data = response.json()
        assert "items" in data
        assert data["total"] == 0

    def test_get_item_returns_item(self):
        response = client.get("/api/v1/items/1")
        assert response.status_code == 200
        data = response.json()
        assert data["id"] == 1

    def test_get_item_invalid_id_returns_422(self):
        response = client.get("/api/v1/items/-1")
        assert response.status_code == 422

    def test_metrics_endpoint_accessible(self):
        response = client.get("/metrics")
        assert response.status_code == 200
        assert "http_requests_total" in response.text
