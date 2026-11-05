"""Per-client rate limit for /api/ai-coach only."""

from __future__ import annotations

from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

import main


@pytest.fixture
def client(monkeypatch):
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)
    monkeypatch.delenv("BACKEND_API_KEY", raising=False)
    monkeypatch.delenv("COACH_TRUST_PROXY", raising=False)
    # Fresh limiter for each test.
    main._coach_rate_limiter = main._CoachRateLimiter(max_calls=10, window_seconds=60.0)
    return TestClient(main.app)


def _post_coach(client, payload=None):
    body = payload or {"userPrompt": "hello", "coachContext": {}}
    return client.post("/api/ai-coach", json=body)


def test_allows_up_to_limit_then_returns_try_again(client):
    for _ in range(10):
        response = _post_coach(client)
        assert response.status_code == 200
        body = response.json()
        assert body["status"] != "rate_limited"
        assert "text" in body
    limited = _post_coach(client)
    assert limited.status_code == 200
    body = limited.json()
    assert body["status"] == "rate_limited"
    assert body["modelUsed"] == "rate-limit"
    assert body["attempts"] == 0
    assert "try again" in body["text"].lower()


def test_recovers_after_window(client, monkeypatch):
    clock = {"now": 1000.0}

    def fake_monotonic():
        return clock["now"]

    monkeypatch.setattr(main.time, "monotonic", fake_monotonic)
    main._coach_rate_limiter = main._CoachRateLimiter(max_calls=2, window_seconds=60.0)

    assert _post_coach(client).json()["status"] != "rate_limited"
    assert _post_coach(client).json()["status"] != "rate_limited"
    assert _post_coach(client).json()["status"] == "rate_limited"

    clock["now"] += 61.0
    recovered = _post_coach(client).json()
    assert recovered["status"] != "rate_limited"


def test_independent_clients(client, monkeypatch):
    main._coach_rate_limiter = main._CoachRateLimiter(max_calls=1, window_seconds=60.0)

    def allow_as(client_id: str):
        return main._coach_rate_limiter.allow(client_id)

    assert allow_as("1.1.1.1") is True
    assert allow_as("1.1.1.1") is False
    assert allow_as("2.2.2.2") is True


def test_ignores_forwarded_headers_without_trusted_proxy(monkeypatch):
    monkeypatch.delenv("COACH_TRUST_PROXY", raising=False)
    request = SimpleNamespace(
        client=SimpleNamespace(host="9.9.9.9"),
        headers={"x-forwarded-for": "8.8.8.8", "x-real-ip": "7.7.7.7"},
    )
    assert main._coach_client_id(request) == "9.9.9.9"


def test_uses_forwarded_headers_when_trusted_proxy_enabled(monkeypatch):
    monkeypatch.setenv("COACH_TRUST_PROXY", "1")
    request = SimpleNamespace(
        client=SimpleNamespace(host="9.9.9.9"),
        headers={"x-forwarded-for": "8.8.8.8, 1.1.1.1", "x-real-ip": "7.7.7.7"},
    )
    assert main._coach_client_id(request) == "8.8.8.8"


def test_non_coach_health_unaffected(client):
    # Exhaust coach limit.
    main._coach_rate_limiter = main._CoachRateLimiter(max_calls=1, window_seconds=60.0)
    assert _post_coach(client).status_code == 200
    assert _post_coach(client).json()["status"] == "rate_limited"
    health = client.get("/health")
    assert health.status_code == 200
    assert health.json()["status"] == "ok"


def test_backend_api_key_still_optional(client, monkeypatch):
    monkeypatch.delenv("BACKEND_API_KEY", raising=False)
    response = _post_coach(client)
    assert response.status_code == 200
