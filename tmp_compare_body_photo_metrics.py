import json
from pathlib import Path

import cv2
import requests

import main

items = [
    {
        'name': 'stock_body_photo_a.jpg',
        'url': 'https://images.unsplash.com/photo-1526506118085-60ce8714f8c5?auto=format&fit=crop&w=1200&q=80',
    },
    {
        'name': 'stock_body_photo_b.jpg',
        'url': 'https://images.unsplash.com/photo-1541534401786-2077eed87a74?auto=format&fit=crop&w=1200&q=80',
    },
]

main.ensure_body_pipeline_ready()
results = []
for item in items:
    path = Path(item['name'])
    if not path.exists():
        response = requests.get(item['url'], timeout=30)
        response.raise_for_status()
        path.write_bytes(response.content)

    img = cv2.imread(str(path))
    if img is None:
        raise RuntimeError(f'Could not decode image: {path}')

    result = main.analyze_body_silhouette(img)
    results.append({
        'photo': item['name'],
        'normalized_area_index': result['normalized_area_index'],
        'scale_reference_pixels': result['scale_reference_pixels'],
        'roi_pixel_count': result['roi_pixel_count'],
        'confidence': result['confidence'],
    })

if len(results) != 2:
    raise RuntimeError(f'Expected exactly 2 results, got {len(results)}')

a = results[0]['normalized_area_index']
b = results[1]['normalized_area_index']
raw_percentage_difference_vs_photo_a = 0.0 if a == 0 and b == 0 else (abs(a - b) / abs(a) * 100.0 if a != 0 else abs(b) * 100.0)

photo_a_metrics = main.analyze_body_silhouette(cv2.imread('stock_body_photo_a.jpg'))
photo_b_metrics = main.analyze_body_silhouette(cv2.imread('stock_body_photo_b.jpg'))

mixed_trend = main._compute_body_silhouette_trend(
    photo_b_metrics,
    photo_a_metrics,
    current_capture_quality='normal',
    baseline_capture_quality='normal',
)
self_trend = main._compute_body_silhouette_trend(
    photo_a_metrics,
    photo_a_metrics,
    current_capture_quality='normal',
    baseline_capture_quality='normal',
)

print(json.dumps({
    'summary_sanity_check': {
        'photo_a': results[0],
        'photo_b': results[1],
        'raw_percentage_difference_vs_photo_a': raw_percentage_difference_vs_photo_a,
    },
    'different_people_mismatch_case': {
        'baseline_photo': 'stock_body_photo_a.jpg',
        'current_photo': 'stock_body_photo_b.jpg',
        'baseline_values': {
            'normalized_area_index': photo_a_metrics['normalized_area_index'],
            'scale_reference_pixels': photo_a_metrics['scale_reference_pixels'],
            'confidence': photo_a_metrics['confidence'],
        },
        'current_values': {
            'normalized_area_index': photo_b_metrics['normalized_area_index'],
            'scale_reference_pixels': photo_b_metrics['scale_reference_pixels'],
            'confidence': photo_b_metrics['confidence'],
        },
        'trend_deltas': mixed_trend[0],
        'trend_status': mixed_trend[1],
        'honesty_band_percent': mixed_trend[2],
    },
    'same_photo_self_match_case': {
        'photo': 'stock_body_photo_a.jpg',
        'trend_deltas': self_trend[0],
        'trend_status': self_trend[1],
        'honesty_band_percent': self_trend[2],
    },
}, sort_keys=True, indent=2))
