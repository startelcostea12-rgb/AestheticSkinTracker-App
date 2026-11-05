"""Logging-only head pose fields on image_quality; gates unchanged."""

from __future__ import annotations

import inspect

import main as main_module


def test_pose_helper_signature_unchanged():
    sig = inspect.signature(main_module._compute_pose_pitch_yaw_from_landmarks)
    assert list(sig.parameters) == ["points"]


def test_image_quality_includes_head_pose_keys_in_source():
    src = open("main.py", encoding="utf-8").read()
    assert '"head_pose_pitch"' in src
    assert '"head_pose_yaw"' in src
    # Must not introduce a new reject based on export fields.
    assert "head_pose_pitch" not in src.split("pose_ok =")[1].split("\n", 5)[0]
