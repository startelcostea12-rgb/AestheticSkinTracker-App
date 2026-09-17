import cv2
import numpy as np
import main

def center_crop_resize(image, fraction, sz=512):
    h, w = image.shape[:2]
    side = int(min(h, w) * fraction)
    cx, cy = w // 2, h // 2
    x0 = max(0, cx - side // 2)
    y0 = max(0, cy - side // 2)
    x1 = min(w, x0 + side)
    y1 = min(h, y0 + side)
    crop = image[y0:y1, x0:x1]
    return cv2.resize(crop, (sz, sz), interpolation=cv2.INTER_CUBIC)

img = cv2.imread('C:/Users/Admin/Pictures/nikki2.jpg')

lm = None
for fraction in [0.9, 0.82, 0.75, 0.68, 0.62, 0.56, 0.50]:
    cropped = center_crop_resize(img, fraction)
    rgb = cv2.cvtColor(cropped, cv2.COLOR_BGR2RGB)
    lm, cnt, src = main._extract_primary_landmarks(rgb)
    if lm is not None:
        print(f"Face found at crop_fraction={fraction}")
        img = cropped
        break

if lm is None:
    print("Still no face detected at any crop fraction.")
else:
    pts = main._landmarks_to_points(lm, img.shape[1], img.shape[0])
    aligned, _ = main._align_and_crop_face(img, pts)

    before_lab = cv2.cvtColor(aligned, cv2.COLOR_BGR2LAB)
    after = main.normalize_lighting_and_shadows(aligned)
    after_lab = cv2.cvtColor(after, cv2.COLOR_BGR2LAB)

    print("mean a BEFORE normalize:", before_lab[:, :, 1].mean())
    print("mean a AFTER normalize:", after_lab[:, :, 1].mean())