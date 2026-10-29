import asyncio
import base64
import json
import inspect
import threading
from io import BytesIO
from unittest import mock

import pytest
import cv2
import numpy as np
from fastapi import HTTPException, Request, UploadFile
from fastapi.testclient import TestClient

import main


def _request(body: bytes, path: str = "/api/ai-coach") -> Request:
    async def receive():
        return {"type": "http.request", "body": body, "more_body": False}

    return Request({"type": "http", "method": "POST", "path": path, "headers": []}, receive)


def _png(width=4, height=4):
    success, encoded = cv2.imencode(".png", np.zeros((height, width, 3), dtype=np.uint8))
    assert success
    return encoded.tobytes()


def _mock_analysis(monkeypatch):
    monkeypatch.setattr(main, "ensure_pipeline_ready", lambda: None)
    monkeypatch.setattr(main, "ensure_body_pipeline_ready", lambda: None)
    monkeypatch.setattr(main, "validate_camera_hardware_qa", lambda image: None)

    def assess(raw, *args, **kwargs):
        image = main._decode_image_bytes(raw)
        return image, {}, image.copy()

    monkeypatch.setattr(main, "_assess_and_normalize_image_with_pre_white_balance", assess)
    monkeypatch.setattr(main, "analyze_skin_patch", lambda image, **kwargs: {"metric_matrix": {}})
    monkeypatch.setattr(main, "analyze_body_silhouette", lambda image: {
        "normalized_area_index": 1.0, "scale_reference_pixels": 1.0,
        "roi_pixel_count": 1, "confidence": 1.0,
    })


async def _call_analysis(endpoint, raw=None, encoded=None):
    raw = _png() if raw is None else raw
    if endpoint == "multipart":
        arguments = {key: None for key in inspect.signature(main.analyze_skin_single).parameters if key != "image"}
        return await main.analyze_skin_single(
            image=UploadFile(file=BytesIO(raw), filename="scan.png"), **arguments
        )
    image = encoded if encoded is not None else base64.b64encode(raw).decode()
    request = _request(json.dumps({"image": image}).encode())
    if endpoint == "body":
        return await main.analyze_body_silhouette_endpoint(request)
    return await main.analyze_skin(request)


@pytest.mark.parametrize("endpoint", ["face", "body"])
def test_main_image_endpoint_accepts_raw_and_data_url(monkeypatch, endpoint):
    _mock_analysis(monkeypatch)
    encoded = base64.b64encode(_png()).decode()
    for image in (encoded, f"data:image/png;base64,{encoded}"):
        result = asyncio.run(_call_analysis(endpoint, encoded=image))
        assert result["status"] == "success"


@pytest.mark.parametrize("endpoint", ["face", "body", "multipart"])
def test_oversized_upload_endpoint_returns_400(monkeypatch, endpoint):
    _mock_analysis(monkeypatch)
    monkeypatch.setattr(main, "MAX_IMAGE_BYTES", 16)
    with pytest.raises(HTTPException) as caught:
        asyncio.run(_call_analysis(endpoint, raw=b"x" * 17))
    assert caught.value.status_code == 400


@pytest.mark.parametrize("endpoint", ["face", "body", "multipart"])
def test_oversized_image_edge_endpoint_returns_400(monkeypatch, endpoint):
    _mock_analysis(monkeypatch)
    with pytest.raises(HTTPException) as caught:
        asyncio.run(_call_analysis(endpoint, raw=_png(width=12001, height=1)))
    assert caught.value.status_code == 400


@pytest.mark.parametrize("endpoint", ["face", "body", "multipart"])
@pytest.mark.parametrize("error,status", [
    (RuntimeError("private-model-or-file-path"), 503),
    (ValueError("private-unexpected-analysis-text"), 500),
])
def test_analysis_endpoint_does_not_expose_server_faults(monkeypatch, endpoint, error, status):
    _mock_analysis(monkeypatch)
    target = "analyze_body_silhouette" if endpoint == "body" else "analyze_skin_patch"
    monkeypatch.setattr(main, target, mock.Mock(side_effect=error))
    with pytest.raises(HTTPException) as caught:
        asyncio.run(_call_analysis(endpoint))
    assert caught.value.status_code == status
    assert caught.value.detail == "Skin analysis is temporarily unavailable. Try again."
    assert str(error) not in caught.value.detail


@pytest.mark.parametrize("endpoint", ["face", "body", "multipart"])
def test_pipeline_initialization_failure_is_generic_503(monkeypatch, endpoint):
    _mock_analysis(monkeypatch)
    target = "ensure_body_pipeline_ready" if endpoint == "body" else "ensure_pipeline_ready"
    monkeypatch.setattr(main, target, mock.Mock(side_effect=FileNotFoundError("private-model-path")))
    with pytest.raises(HTTPException) as caught:
        asyncio.run(_call_analysis(endpoint))
    assert caught.value.status_code == 503
    assert caught.value.detail == main.ANALYSIS_UNAVAILABLE_DETAIL


@pytest.mark.parametrize("endpoint", ["face", "multipart"])
def test_yunet_message_is_400_through_face_endpoints(monkeypatch, endpoint):
    _mock_analysis(monkeypatch)
    monkeypatch.setattr(main, "analyze_skin_patch", mock.Mock(side_effect=RuntimeError(main.YUNET_PRECISE_LANDMARKS_MESSAGE)))
    with pytest.raises(HTTPException) as caught:
        asyncio.run(_call_analysis(endpoint))
    assert caught.value.status_code == 400
    assert caught.value.detail == main.YUNET_PRECISE_LANDMARKS_MESSAGE


@pytest.mark.parametrize("endpoint", ["face", "multipart"])
def test_camera_qa_message_is_preserved(monkeypatch, endpoint):
    _mock_analysis(monkeypatch)
    message = "Camera hardware QA failed: retake the photo."
    monkeypatch.setattr(main, "validate_camera_hardware_qa", mock.Mock(side_effect=HTTPException(status_code=400, detail=message)))
    with pytest.raises(HTTPException) as caught:
        asyncio.run(_call_analysis(endpoint))
    assert caught.value.status_code == 400
    assert caught.value.detail == message


@pytest.mark.parametrize("endpoint", [main.analyze_skin, main.analyze_body_silhouette_endpoint])
def test_bad_analysis_json_stays_400(endpoint):
    with pytest.raises(HTTPException) as caught:
        asyncio.run(endpoint(_request(b"invalid-json")))
    assert caught.value.status_code == 400


@pytest.mark.parametrize("endpoint,target", [
    ("face", "ensure_pipeline_ready"),
    ("face", "_decode_image_bytes"),
    ("face", "_assess_and_normalize_image_with_pre_white_balance"),
    ("face", "analyze_skin_patch"),
    ("multipart", "analyze_skin_patch"),
    ("body", "ensure_body_pipeline_ready"),
    ("body", "_decode_image_bytes"),
    ("body", "analyze_body_silhouette"),
])
def test_to_thread_keeps_health_and_event_loop_responsive(monkeypatch, endpoint, target):
    _mock_analysis(monkeypatch)
    started = threading.Event()
    release = threading.Event()
    event_loop_thread = threading.get_ident()

    def blocking_stage(*args, **kwargs):
        assert threading.get_ident() != event_loop_thread
        started.set()
        release.wait(5)
        raise RuntimeError("worker-finished")

    monkeypatch.setattr(main, target, blocking_stage)

    async def scenario():
        analysis = asyncio.create_task(_call_analysis(endpoint))
        try:
            assert await asyncio.wait_for(asyncio.to_thread(started.wait, 2), 3)
            assert not analysis.done()
            health = await asyncio.wait_for(main.health_check(), 0.5)
            assert health["status"] == "ok"
            assert not analysis.done()
        finally:
            release.set()
            with pytest.raises(HTTPException) as caught:
                await analysis
            assert caught.value.status_code == 503

    asyncio.run(scenario())


def test_data_url_and_raw_base64_decode_to_identical_bytes():
    raw = _png()
    encoded = base64.b64encode(raw).decode()
    assert main._decode_base64_image(encoded) == raw
    assert main._decode_base64_image(f"data:image/png;base64,{encoded}") == raw


def test_oversized_base64_is_400(monkeypatch):
    monkeypatch.setattr(main, "MAX_IMAGE_BYTES", 8)
    with pytest.raises(HTTPException) as caught:
        main._decode_base64_image(base64.b64encode(b"x" * 9).decode())
    assert caught.value.status_code == 400


def test_oversized_json_payload_is_400(monkeypatch):
    monkeypatch.setattr(main, "MAX_IMAGE_BYTES", 8)
    with pytest.raises(HTTPException) as caught:
        asyncio.run(main._read_analysis_json(_request(b"x" * 9)))
    assert caught.value.status_code == 400


def test_image_edge_over_12000_is_rejected():
    with pytest.raises(HTTPException) as caught:
        main._decode_image_bytes(_png(width=12001, height=1))
    assert caught.value.status_code == 400


def test_image_at_dimension_limits_is_not_resized():
    decoded = main._decode_image_bytes(_png(width=12000, height=1))
    assert decoded.shape == (1, 12000, 3)
    main._check_image_dimensions(10000, 6000)


def test_gray_card_cannot_swallow_image_dimension_limits():
    with pytest.raises(HTTPException) as caught:
        main._sample_gray_card_patch(_png(width=12001, height=1))
    assert caught.value.status_code == 400
    assert main._sample_gray_card_patch(b"not-an-image")["reason"] == "card_image_unreadable"


@pytest.mark.parametrize("path", ["/api/analyze-skin", "/api/body/analyze-silhouette", "/api/skin/analyze-single"])
def test_oversized_http_request_rejected_before_parsing(monkeypatch, path):
    assert main.MAX_IMAGE_BYTES == 20 * 1024 * 1024
    monkeypatch.setattr(main, "_BACKEND_API_KEY", "")
    client = TestClient(main.app)
    response = client.post(path, content=b"x", headers={"Content-Length": str(main.MAX_IMAGE_BYTES + 1)})
    assert response.status_code == 400
    assert response.json()["detail"] == "Image upload exceeds 20 MB."


@pytest.mark.parametrize("attachment", ["baseline_image", "gray_card_image"])
def test_combined_multipart_images_cannot_exceed_upload_limit(monkeypatch, attachment):
    _mock_analysis(monkeypatch)
    raw = _png()
    monkeypatch.setattr(main, "MAX_IMAGE_BYTES", len(raw) + 1)
    arguments = {key: None for key in inspect.signature(main.analyze_skin_single).parameters if key != "image"}
    arguments[attachment] = UploadFile(file=BytesIO(raw), filename="attachment.png")
    with pytest.raises(HTTPException) as caught:
        asyncio.run(main.analyze_skin_single(
            image=UploadFile(file=BytesIO(raw), filename="scan.png"), **arguments
        ))
    assert caught.value.status_code == 400


def test_image_over_60_million_pixels_is_rejected_before_decode(monkeypatch):
    header = mock.MagicMock()
    header.__enter__.return_value.size = (8000, 8000)
    monkeypatch.setattr(main.Image, "open", mock.Mock(return_value=header))
    decoder = mock.Mock()
    monkeypatch.setattr(main.cv2, "imdecode", decoder)
    with pytest.raises(HTTPException) as caught:
        main._decode_image_bytes(b"encoded-image")
    assert caught.value.status_code == 400
    decoder.assert_not_called()


@pytest.mark.parametrize("error,status", [
    (RuntimeError("private-runtime-error"), 503),
    (ValueError("private-value-error"), 500),
])
def test_server_faults_have_generic_details(error, status):
    result = main._analysis_http_exception(error)
    assert result.status_code == status
    assert result.detail == main.ANALYSIS_UNAVAILABLE_DETAIL
    assert str(error) not in result.detail


def test_yunet_precise_landmarks_message_stays_400():
    result = main._analysis_http_exception(RuntimeError(main.YUNET_PRECISE_LANDMARKS_MESSAGE))
    assert result.status_code == 400
    assert result.detail == main.YUNET_PRECISE_LANDMARKS_MESSAGE


def test_coach_models_use_only_requested_versions():
    assert main.COACH_MODELS == (
        "gemini-3.8-flash", "gemini-3.6-flash", "gemini-2.5-flash"
    )
    assert not {"gemini-2.0-flash", "gemini-1.5-flash", "gemini-2.0-flash-exp"}.intersection(main.COACH_MODELS)


def test_remembered_face_pipeline_error_is_retried(monkeypatch):
    monkeypatch.setattr(main, "_PIPELINE_READY", False)
    monkeypatch.setattr(main, "_PIPELINE_ERROR", "remembered-private-error")
    attempt = mock.Mock(side_effect=RuntimeError("fresh-attempt"))
    monkeypatch.setattr(main, "_seed_everything", attempt)
    with pytest.raises(RuntimeError, match="fresh-attempt"):
        main.ensure_pipeline_ready()
    attempt.assert_called_once()
    assert main._PIPELINE_ERROR == ""


def test_remembered_body_pipeline_error_is_retried(monkeypatch):
    monkeypatch.setattr(main, "_BODY_PIPELINE_READY", False)
    monkeypatch.setattr(main, "_BODY_PIPELINE_ERROR", "remembered-private-error")
    monkeypatch.setattr(main, "mp", None)
    with pytest.raises(RuntimeError, match="MediaPipe is not installed"):
        main.ensure_body_pipeline_ready()
    assert main._BODY_PIPELINE_ERROR != "remembered-private-error"


def test_bad_coach_body_is_not_written_to_log(caplog):
    secret = "private-patient-body-and-api-key"
    with pytest.raises(HTTPException) as caught:
        asyncio.run(main.ai_coach(_request(secret.encode())))
    assert caught.value.status_code == 400
    messages = [record.getMessage() for record in caplog.records if record.name == main.__name__]
    assert messages == ["JSON decode failed for /api/ai-coach"]
    assert secret not in caplog.text
    assert all(record.exc_info is None for record in caplog.records)


def test_coach_failure_reports_type_only_and_generic_502(monkeypatch, caplog):
    monkeypatch.setenv("GEMINI_API_KEY", "test-key")
    monkeypatch.setattr(main.genai, "Client", mock.Mock(side_effect=RuntimeError("private-provider-text")))
    with pytest.raises(HTTPException) as caught:
        asyncio.run(main.ai_coach(_request(json.dumps({"userPrompt": "private-prompt"}).encode())))
    assert caught.value.status_code == 502
    assert caught.value.detail == "AI coach is temporarily unavailable. Try again."
    assert [record.getMessage() for record in caplog.records if record.name == main.__name__] == ["RuntimeError"]
    assert "private-provider-text" not in caplog.text
    assert "private-prompt" not in caplog.text