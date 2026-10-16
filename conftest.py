"""Fails test_metric_regression_batch.py up front, with a clear message, when
the interpreter or MediaPipe is not the one the regression fixtures were
recorded with -- so a wrong environment cannot show up as a face-detection
("Could not derive dynamic facial regions") or import failure.

Kept free of Python 3.10+ syntax so it still loads on older interpreters.
"""
from __future__ import annotations

import sys
from importlib import metadata

import pytest

REGRESSION_FILE = "test_metric_regression_batch.py"
REQUIRED_PYTHON = (3, 10)
REQUIRED_MEDIAPIPE = "0.10.14"


def regression_environment_problems() -> list[str]:
    """What is wrong with this environment for the regression file, if
    anything. Reads installed package metadata only (nothing is imported)."""
    problems: list[str] = []
    if sys.version_info[:2] < REQUIRED_PYTHON:
        problems.append(
            "Python %d.%d is too old (need %d.%d+); use the project venv, e.g. "
            "~/.venvs/aestheticskin/bin/python -m pytest"
            % (sys.version_info[0], sys.version_info[1], *REQUIRED_PYTHON)
        )
    try:
        mediapipe_version = metadata.version("mediapipe")
    except metadata.PackageNotFoundError:
        mediapipe_version = None
    if mediapipe_version != REQUIRED_MEDIAPIPE:
        found = (
            "mediapipe is not installed"
            if mediapipe_version is None
            else "mediapipe %s is installed" % mediapipe_version
        )
        problems.append(
            "%s (need %s, as pinned in requirements.txt)"
            % (found, REQUIRED_MEDIAPIPE)
        )
    return problems


class _WrongEnvironmentItem(pytest.Item):
    def __init__(self, *, problems: list[str], **kwargs) -> None:
        super().__init__(**kwargs)
        self.problems = problems

    def runtest(self) -> None:
        pytest.fail(
            "Metric regression tests need the project environment:\n- "
            + "\n- ".join(self.problems),
            pytrace=False,
        )

    def reportinfo(self):
        return self.path, None, "regression environment check"


class _WrongEnvironmentFile(pytest.File):
    def __init__(self, *, problems: list[str], **kwargs) -> None:
        super().__init__(**kwargs)
        self.problems = problems

    def collect(self):
        yield _WrongEnvironmentItem.from_parent(
            self, name="environment_check", problems=self.problems
        )


def pytest_pycollect_makemodule(module_path, parent):
    """Replaces the regression module with a single failing check (before the
    module, and so main.py, is imported) when the environment is wrong."""
    if module_path.name != REGRESSION_FILE:
        return None
    problems = regression_environment_problems()
    if not problems:
        return None
    return _WrongEnvironmentFile.from_parent(
        parent, path=module_path, problems=problems
    )
