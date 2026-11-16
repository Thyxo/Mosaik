#!/usr/bin/env python3
"""App-ikonet: klippet ud af et skærmbillede af den rigtige Fotos-app (mørkt iOS 26-ikon, ref/home-icon.jpeg).
Hjørnerne (tapetet) erstattes med ikonets egen baggrund, så iOS' maske ikke viser blå kanter."""
import os, numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src = Image.open(os.path.join(ROOT, 'ref/home-icon.jpeg')).convert('RGB')
crop = src.crop((63, 279, 288, 504))           # ikonets kant i skærmbilledet
S = 1024
big = np.asarray(crop.resize((S, S), Image.LANCZOS), dtype=np.float32)
r = S * 0.235                                    # lidt større hjørne end iOS' maske
ys, xs = np.mgrid[0:S, 0:S].astype(np.float32) + 0.5
cx = np.clip(xs, r, S - r); cy = np.clip(ys, r, S - r)
dx, dy = xs - cx, ys - cy
d = np.sqrt(dx * dx + dy * dy)
out = d > r - 6
# flyt punkter uden for hjørnet ind mod hjørnets centrum
k = np.where(out, (r - 10) / np.maximum(d, 1e-3), 1)
sx = np.clip((cx + dx * k).astype(int), 0, S - 1); sy = np.clip((cy + dy * k).astype(int), 0, S - 1)
res = big.copy()
res[out] = big[sy[out], sx[out]]
# også de yderste pixels langs kanterne (kan have tapet i sig)
m = 10
res[:m, :] = res[m:m + 1, :]; res[-m:, :] = res[-m - 1:-m, :]
res[:, :m] = res[:, m:m + 1]; res[:, -m:] = res[:, -m - 1:-m]
img = Image.fromarray(res.clip(0, 255).astype(np.uint8)).filter(ImageFilter.UnsharpMask(radius=3, percent=60, threshold=2))
img.save(os.path.join(ROOT, 'ios/Mosaik/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png'))
img.resize((512, 512), Image.LANCZOS).save(os.path.join(ROOT, 'icons/icon-512.png'))
print('ok')
