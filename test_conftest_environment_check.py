"""The conftest.py environment check for the metric regression file."""
from __future__ import annotations

from importlib import metadata

import conftest


def test_project_venv_passes():
    assert conftest.regression_environment_problems() == []


def test_wrong_mediapipe_is_reported(monkeypatch):
    monkeypatch.setattr(metadata, "version", lambda name: "0.10.21")
    problems = conftest.regression_environment_problems()
    assert problems == [
        "mediapipe 0.10.21 is installed (need 0.10.14, as pinned in requirements.txt)"
    ]


def test_missing_mediapipe_is_reported(monkeypatch):
    def missing(name):
        raise metadata.PackageNotFoundError(name)

    monkeypatch.setattr(metadata, "version", missing)
    assert conftest.regression_environment_problems() == [
        "mediapipe is not installed (need 0.10.14, as pinned in requirements.txt)"
    ]


def test_old_python_is_reported(monkeypatch):
    monkeypatch.setattr(conftest.sys, "version_info", (3, 9, 6))
    problems = conftest.regression_environment_problems()
    assert problems[0].startswith("Python 3.9 is too old (need 3.10+)")
