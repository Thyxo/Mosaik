#!/usr/bin/env python3
"""Ikon: hvid baggrund med en blomst af 8 farvede, gennemsigtige kronblade (iOS maskerer hjørnerne)."""
import math, os
from PIL import Image, ImageDraw, ImageChops

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
S = 1024 * 2
img = Image.new('RGB', (S, S), (255, 255, 255))
cols = [(250, 184, 30), (240, 123, 38), (232, 66, 84), (196, 72, 166), (128, 92, 200), (60, 140, 230), (42, 182, 196), (120, 196, 72)]
cx = cy = S / 2
for k, c in enumerate(cols):
    ang = -math.pi / 2 + k * math.pi / 4
    petal = Image.new('RGB', (S, S), (255, 255, 255))
    d = ImageDraw.Draw(petal)
    L, W = S * 0.205, S * 0.105
    mx, my = cx + math.cos(ang) * L * 0.95, cy + math.sin(ang) * L * 0.95
    pts = []
    for t in range(0, 360, 3):
        a = math.radians(t)
        x, y = math.cos(a) * L, math.sin(a) * W
        pts.append((mx + x * math.cos(ang) - y * math.sin(ang), my + x * math.sin(ang) + y * math.cos(ang)))
    d.polygon(pts, fill=c)
    img = ImageChops.multiply(img, petal)
img = img.resize((1024, 1024), Image.LANCZOS)
img.save(os.path.join(ROOT, 'ios/Mosaik/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png'))
img.resize((512, 512), Image.LANCZOS).save(os.path.join(ROOT, 'icons/icon-512.png'))
