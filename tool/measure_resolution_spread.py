"""Score the same fixture faces at several upload resolutions and print, per
metric, the (max - min) spread across resolutions for each fixture.

Usage (from the repo root): python tool/measure_resolution_spread.py out.json
"""
import json
import logging
import math
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
os.chdir(ROOT)
import cv2, numpy as np
logging.disable(logging.CRITICAL)
import main
FIX = {
 'clear_face': 'test_fixtures/metric_regression/clear_face.jfif',
 'st1': 'test_fixtures/metric_regression/st1.jpg',
 'nikki2': 'test_fixtures/metric_regression/nikki2.jpg',
 'nikki3': 'test_fixtures/metric_regression/nikki3.jpg',
 'portrait_09': 'calibration_stock_batch/portrait_09_woman_outdoor.jpg',
}
LONG = [512, 768, 1024, 1536]
out = {}
for name, p in FIX.items():
    img = cv2.imread(p)
    h, w = img.shape[:2]
    out[name] = {}
    for L in LONG:
        s = L / max(h, w)
        interp = cv2.INTER_AREA if s < 1 else cv2.INTER_CUBIC
        im = cv2.resize(img, (round(w*s), round(h*s)), interpolation=interp)
        ok, buf = cv2.imencode('.png', im)
        try:
            n, q = main.assess_and_normalize_image(buf.tobytes())
            r = main.analyze_skin_patch(n, quality_profile=q)
            m = {k: float(v) for k, v in (r.get('metric_matrix') or {}).items() if isinstance(v,(int,float)) and v is not None and math.isfinite(v)}
        except Exception as e:
            m = {'ERROR': str(e)[:80]}
        out[name][L] = m
json.dump(out, open(sys.argv[1], 'w'), indent=1)
# summary
metrics = sorted({k for n in out.values() for m in n.values() for k in m})
print('metric: per-fixture spread (max-min across sizes)')
agg = {}
for k in metrics:
    row = []
    for n in out:
        vals = [out[n][L].get(k) for L in LONG]
        vals = [v for v in vals if v is not None]
        if len(vals) == len(LONG): row.append(max(vals)-min(vals))
        else: row.append(None)
    agg[k] = row
    r = [x for x in row if x is not None]
    print(f"{k:34s} " + ' '.join(f"{('  -  ' if x is None else '%5.1f'%x)}" for x in row) + f"   max={max(r) if r else None}")
print('fixtures', list(out))
