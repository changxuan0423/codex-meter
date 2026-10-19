"""Compare the actual style renderer against the supplied 392x68, 2x reference.

This is an offscreen component audit, not a claim to capture the live menu bar.
Requires Pillow and NumPy. No reference pixels or screenshots are modified.
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

reference = np.asarray(Image.open(sys.argv[1]).convert("L"), dtype=float)
directory = Path(sys.argv[2])
standard_icon = "--standard-icon" in sys.argv[3:]
if reference.shape != (68, 392):
    raise SystemExit("Use the original 392x68 reference; don't rescale the screenshot.")


def image(name):
    return np.asarray(Image.open(directory / name).convert("L"), dtype=float)


def bounds(array, threshold=40):
    ys, xs = np.where(array > threshold)
    return [int(xs.min()), int(ys.min()), int(xs.max() + 1), int(ys.max() + 1)]


def spans(array, threshold=40):
    occupied = np.any(array > threshold, axis=0)
    result = []
    start = None
    for index, active in enumerate(list(occupied) + [False]):
        if active and start is None:
            start = index
        if not active and start is not None:
            result.append([start, index])
            start = None
    return result


def crop(array):
    left, top, right, bottom = bounds(array, 25)
    return array[top:bottom, left:right]


# Locate ink in the left Weather item; no metrics are copied from implementation.
weather = reference[:, :110]
weather_spans = spans(weather)
weather_icon = weather[:, weather_spans[0][0]:weather_spans[0][1]]
weather_bounds = bounds(weather)
weather_icon_bounds = bounds(weather_icon)
weather_height = weather_bounds[3] - weather_bounds[1]
weather_icon_height = weather_icon_bounds[3] - weather_icon_bounds[1]
weather_gap = weather_spans[1][0] - weather_spans[0][1]

row = image("row-probe.png")
row_bounds = bounds(row)
row_spans = spans(row)
icon_bounds = bounds(image("icon-probe.png"))
actual_height = row_bounds[3] - row_bounds[1]
actual_icon_height = icon_bounds[3] - icon_bounds[1]
actual_gap = row_spans[1][0] - row_spans[0][1]

# Compare the same glyphs, rather than judging dissimilar digits by eye.
# Fit only translation and foreground intensity, never scale or stroke width.
target = crop(np.maximum(reference[17:49, 50:105] - 1, 0))
candidate = crop(image("font-probe.png"))
best = float("inf")
intensity = None
for dx in range(-2, 3):
    for dy in range(-2, 3):
        actual = np.zeros((40, 80))
        expected = np.zeros_like(actual)
        expected[5:5 + target.shape[0], 5:5 + target.shape[1]] = target
        actual[5 + dy:5 + dy + candidate.shape[0], 5 + dx:5 + dx + candidate.shape[1]] = candidate
        factor = np.sum(actual * expected) / max(np.sum(actual * actual), 1)
        error = np.sum((expected - factor * actual) ** 2) / np.sum(expected ** 2)
        if error < best:
            best, intensity = float(error), float(factor)

checks = {
    "same_visible_row_height": actual_height == weather_height,
    "same_visible_icon_height": actual_icon_height == weather_icon_height,
    "same_icon_to_digit_gap": actual_gap == weather_gap,
    "same_font_glyph_bounds": candidate.shape == target.shape,
    "same_font_shape": best < 0.01,
    "only_row_width_increases": row_bounds[2] - row_bounds[0] > weather_bounds[2] - weather_bounds[0],
    "original_badge_keeps_square_aspect": icon_bounds[2] - icon_bounds[0] == actual_icon_height,
    "native_image_title_spacing_is_measured": json.loads((directory / "metrics.json").read_text())["nativeImageTitleGapPoints"] == 2,
}
if standard_icon:
    # 1.0.5: the user explicitly approved larger icon ink; keep the accepted font
    # and spacing contract while checking the new standard-size icon separately.
    del checks["same_visible_row_height"]
    del checks["same_visible_icon_height"]
    del checks["only_row_width_increases"]
    checks["standard_16pt_icon"] = 30 <= actual_icon_height <= 32
    checks["row_fits_icon_height"] = actual_height == actual_icon_height
    checks["wider_row"] = row_bounds[2] - row_bounds[0] > weather_bounds[2] - weather_bounds[0]
    checks["original_badge_keeps_square_aspect"] = abs(icon_bounds[2] - icon_bounds[0] - actual_icon_height) <= 1
report = {
    "contract": "1.0.5 standard icon, preserved typography and gap" if standard_icon else "1.0.4 Weather height",
    "scope": "Offscreen source rendering versus user reference at 2x; live screenshot not captured",
    "reference_visible_height_px": weather_height,
    "actual_visible_height_px": actual_height,
    "reference_icon_height_px": weather_icon_height,
    "actual_icon_height_px": actual_icon_height,
    "reference_icon_digit_gap_px": weather_gap,
    "actual_icon_digit_gap_px": actual_gap,
    "glyph_normalized_squared_error": round(best, 6),
    "reference_foreground_fit": round(intensity, 4),
    "font": json.loads((directory / "metrics.json").read_text()),
    "checks": checks,
    "passed": all(checks.values()),
}
(directory / "audit.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
print(json.dumps(report, indent=2, ensure_ascii=False))
if not all(checks.values()):
    raise SystemExit(1)
