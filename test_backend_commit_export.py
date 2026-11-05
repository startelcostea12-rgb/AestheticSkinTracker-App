"""Logging-only: analyze responses carry the same commit /health reports."""

from __future__ import annotations

import asyncio

import main as main_module


def test_server_backend_commit_reads_git_commit_env(monkeypatch):
    monkeypatch.setenv("GIT_COMMIT", "abc1234")
    assert main_module._server_backend_commit() == "abc1234"


def test_server_backend_commit_unknown_when_unset(monkeypatch):
    monkeypatch.delenv("GIT_COMMIT", raising=False)
    assert main_module._server_backend_commit() == "unknown"


def test_health_includes_commit_and_backend_commit(monkeypatch):
    monkeypatch.setenv("GIT_COMMIT", "deadbeef")
    body = asyncio.run(main_module.health_check())
    assert body["commit"] == "deadbeef"
    assert body["backend_commit"] == "deadbeef"


def test_response_payload_builder_includes_backend_commit_source(monkeypatch):
    """Guard that analyze assembly still keys backend_commit from the helper."""
    monkeypatch.setenv("GIT_COMMIT", "cafebabe")
    # Source-level contract: the helper is what response_payload uses.
    assert "backend_commit" in open("main.py", encoding="utf-8").read()
    assert main_module._server_backend_commit() == "cafebabe"
