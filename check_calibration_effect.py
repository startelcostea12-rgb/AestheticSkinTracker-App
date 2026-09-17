import cv2
import numpy as np
import main

def get_cheek_a_mean(bgr_image):
    """Run full landmark pipeline and return mean 'a' (redness) value in the cheek region."""
    rgb = cv2.cvtColor(bgr_image, cv2.COLOR_BGR2RGB)
    lm, cnt, src = main._extract_primary_landmarks(rgb)
    if lm is None:
        return None
    pts = main._landmarks_to_points(lm, bgr_image.shape[1], bgr_image.shape[0])
    aligned, aligned_pts = main._align_and_crop_face(bgr_image, pts)

    norm_rgb = cv2.cvtColor(aligned, cv2.COLOR_BGR2RGB)
    n_lm, n_cnt, n_src = main._extract_primary_landmarks(norm_rgb)
    if n_lm is None:
        return None
    n_pts = main._landmarks_to_points(n_lm, aligned.shape[1], aligned.shape[0])

    mask = main._skin_mask(aligned)
    regions = main._region_masks(aligned.shape[:2], mask, n_pts)
    cheek_mask = cv2.bitwise_or(regions["left_cheek"], regions["right_cheek"])

    lab = cv2.cvtColor(aligned, cv2.COLOR_BGR2LAB)
    a_channel = lab[:, :, 1]
    cheek_pixels = a_channel[cheek_mask > 0]
    if cheek_pixels.size == 0:
        return None
    return float(np.mean(cheek_pixels))


with open('C:/Users/Admin/Pictures/92560746_539286527020227_3378383054119632896_n.jpg', 'rb') as f:
    image_bytes = f.read()

# Stage 1: raw decoded image, no processing at all
arr = np.frombuffer(image_bytes, dtype=np.uint8)
raw_img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
raw_img = cv2.resize(raw_img, (512, 512), interpolation=cv2.INTER_CUBIC)
a_raw = get_cheek_a_mean(raw_img)
print("Stage 1 - raw decoded, no processing: cheek mean a =", a_raw)

# Stage 2: after white balance calibration only (no lighting normalization)
calibrated_img, calib_info = main.apply_white_balance_calibration(raw_img)
a_calibrated = get_cheek_a_mean(calibrated_img)
print("Stage 2 - after white balance calibration only: cheek mean a =", a_calibrated)
print("  calibration info:", calib_info)

# Stage 3: full pipeline (calibration + lighting normalization, matches real behavior)
normalized_bgr, quality_profile = main.assess_and_normalize_image(image_bytes)
a_full = get_cheek_a_mean(normalized_bgr)
print("Stage 3 - full pipeline (calibration + normalize_lighting_and_shadows): cheek mean a =", a_full)