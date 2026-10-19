import asyncio
import json
import pytest
from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect

from server.main import app, estimate_metric_distance, centroid_to_clock_zone

client = TestClient(app)

def test_health_endpoint():
    """Verify Kubernetes / Cloud Run health probe."""
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert data["version"] == "3.5.0"

def test_pinhole_distance_and_clock_estimation():
    """Verify calibrated ~62° Vertical FOV optical pinhole distance calculations."""
    # Person (prior: height=1.70m)
    dist_person, hazard_cat = estimate_metric_distance("person", 0.1, 0.4)
    assert 2.0 <= dist_person <= 7.0
    assert hazard_cat == "waypoint"

    # Car (prior: width=1.80m)
    dist_car, hazard_cat_car = estimate_metric_distance("car", 0.5, 0.3)
    assert 1.0 <= dist_car <= 6.0
    assert hazard_cat_car == "critical"

    # Clock zone mapping
    assert centroid_to_clock_zone(0.05) == "9 o'clock"
    assert centroid_to_clock_zone(0.50) == "12 o'clock"
    assert centroid_to_clock_zone(0.95) == "3 o'clock"

def test_websocket_unauthorized_token_1008_rejection():
    """Verify WebSocket 1008 Policy Violation on invalid token."""
    with pytest.raises(WebSocketDisconnect) as excinfo:
        with client.websocket_connect("/ws/vision-stream?token=invalid_unauthorized_token") as ws:
            ws.receive_text()
    assert excinfo.value.code == 1008

def test_websocket_authorized_connection_and_ping_pong():
    """Verify WebSocket accepts valid token and responds to ping/pong."""
    with client.websocket_connect("/ws/vision-stream?token=orbisnav-live-key-2026") as ws:
        ws.send_text("ping")
        data = ws.receive_text()
        parsed = json.loads(data)
        assert parsed["type"] == "pong"
        assert "timestamp" in parsed

def test_omni_scan_summarize_rest_endpoint():
    """Verify REST OCR summarization endpoint with entity extraction."""
    payload = {
        "text": "Electric Utility Bill. Account: 987654. Payment due: $84.50. Due date: Nov 15, 2026.",
        "max_sentences": 3
    }
    response = client.post(
        "/api/v1/omni-scan/summarize",
        json=payload,
        headers={"Content-Type": "application/json"}
    )
    assert response.status_code == 200
    data = response.json()
    assert data["document_type"] == "Utility Bill"
    assert any("84.50" in a for a in data["action_items"])
    assert "spoken_summary" in data
    assert "executive_summary" in data
