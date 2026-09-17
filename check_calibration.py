import cv2
import numpy as np
import main

with open('C:/Users/Admin/Pictures/clear face.jfif', 'rb') as f:
    raw_bytes = f.read()

# Decode, then resize up to a reasonable working size (matches smoke test behavior)
arr = np.frombuffer(raw_bytes, dtype=np.uint8)
img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
resized = cv2.resize(img, (512, 512), interpolation=cv2.INTER_CUBIC)

success, encoded = cv2.imencode('.jpg', resized)
image_bytes = encoded.tobytes()

normalized_bgr, quality_profile = main.assess_and_normalize_image(image_bytes)
main.validate_camera_hardware_qa(normalized_bgr)
result = main.analyze_skin_patch(normalized_bgr, quality_profile=quality_profile)

print("calibration:", result.get("calibration"))
print("localized_redness:", result.get("metric_matrix", {}).get("localized_redness"))