import cv2
import json
import requests
from pathlib import Path
import main

urls = [
    'https://images.unsplash.com/photo-1526506118085-60ce8714f8c5?auto=format&fit=crop&w=1200&q=80',
    'https://images.unsplash.com/photo-1517836357463-d25dfeac3438?auto=format&fit=crop&w=1200&q=80',
    'https://images.unsplash.com/photo-1541534401786-2077eed87a74?auto=format&fit=crop&w=1200&q=80',
    'https://images.unsplash.com/photo-1515886657613-9f3515b0c78f?auto=format&fit=crop&w=1200&q=80',
    'https://images.unsplash.com/photo-1524504388940-b1c1722653e1?auto=format&fit=crop&w=1200&q=80',
    'https://images.unsplash.com/photo-1571019614242-c5c5dee9f50b?auto=format&fit=crop&w=1200&q=80',
    'https://images.unsplash.com/photo-1549060279-7e168fcee0c2?auto=format&fit=crop&w=1200&q=80',
]

main.ensure_body_pipeline_ready()
for idx, url in enumerate(urls, 1):
    path = Path(f'candidate_body_{idx}.jpg')
    try:
        r = requests.get(url, timeout=30)
        r.raise_for_status()
        path.write_bytes(r.content)
        img = cv2.imread(str(path))
        print(f'candidate {idx}: shape={None if img is None else img.shape}')
        if img is None:
            continue
        rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
        lm = main._body_pose_landmarks_for_image(rgb)
        print(f'candidate {idx}: landmarks={None if lm is None else len(lm)}')
        if lm is not None:
            try:
                result = main.analyze_body_silhouette(img)
                print(f'candidate {idx}: result={json.dumps(result, sort_keys=True)}')
            except Exception as exc:
                print(f'candidate {idx}: analysis_error={type(exc).__name__}: {exc}')
    except Exception as exc:
        print(f'candidate {idx}: download_error={type(exc).__name__}: {exc}')
