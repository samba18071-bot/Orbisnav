"""
OrbisNav Comprehensive Assistive Navigation & Lost Item Dataset Generator.
Procedurally generates structured YOLOv8 training and validation datasets with 
realistic bounding box annotations for all 32 assistive obstacles and everyday items:
0: person
1: tree
2: chair
3: table
4: door
5: stairs
6: signboard
7: vehicle
8: pole
9: laptop
10: bottle
11: potted_plant
12: bench
13: trash_bin
14: bicycle
15: fire_hydrant
16: ironbox
17: keys
18: wallet
19: white_cane
20: glasses
21: cell_phone
22: charger
23: shoes
24: cup
25: plate
26: spoon
27: medicine_bottle
28: headphones
29: watch
30: remote
31: pen
"""

import os
import random
import math
from typing import List, Tuple
import cv2
import numpy as np

CLASSES = [
    "person",          # 0
    "tree",            # 1
    "chair",           # 2
    "table",           # 3
    "door",            # 4
    "stairs",          # 5
    "signboard",       # 6
    "vehicle",         # 7
    "pole",            # 8
    "laptop",          # 9
    "bottle",          # 10
    "potted_plant",    # 11
    "bench",           # 12
    "trash_bin",       # 13
    "bicycle",         # 14
    "fire_hydrant",    # 15
    "ironbox",         # 16
    "keys",            # 17
    "wallet",          # 18
    "white_cane",      # 19
    "glasses",         # 20
    "cell_phone",      # 21
    "charger",         # 22
    "shoes",           # 23
    "cup",             # 24
    "plate",           # 25
    "spoon",           # 26
    "medicine_bottle", # 27
    "headphones",      # 28
    "watch",           # 29
    "remote",          # 30
    "pen",             # 31
]

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DATASET_DIR = os.path.join(BASE_DIR, "dataset")

def create_directory_structure():
    """Sets up YOLO dataset directory layout."""
    for split in ["train", "val"]:
        os.makedirs(os.path.join(DATASET_DIR, "images", split), exist_ok=True)
        os.makedirs(os.path.join(DATASET_DIR, "labels", split), exist_ok=True)

def draw_shadow(canvas: np.ndarray, x1: int, y2: int, w: int):
    """Draws a subtle ground contact shadow beneath an obstacle."""
    center = (x1 + w // 2, min(canvas.shape[0] - 2, y2 + 3))
    axes = (max(8, w // 2), max(4, w // 7))
    overlay = canvas.copy()
    cv2.ellipse(overlay, center, axes, 0, 0, 360, (25, 25, 25), -1)
    cv2.addWeighted(overlay, 0.40, canvas, 0.60, 0, canvas)

def draw_person(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    draw_shadow(canvas, x1, y2, w)
    head_r = max(4, int(w * 0.22))
    head_cx = x1 + w // 2
    head_cy = y1 + int(h * 0.16)
    skin_color = (random.randint(140, 210), random.randint(170, 225), random.randint(200, 245))
    hair_color = (random.randint(20, 50), random.randint(20, 50), random.randint(20, 50))
    cv2.circle(canvas, (head_cx, head_cy), head_r, skin_color, -1)
    cv2.circle(canvas, (head_cx, head_cy - int(head_r * 0.4)), int(head_r * 0.8), hair_color, -1)
    shirt_color = (random.randint(30, 230), random.randint(30, 230), random.randint(30, 230))
    body_top = head_cy + head_r
    body_bot = y1 + int(h * 0.58)
    cv2.rectangle(canvas, (x1 + int(w * 0.16), body_top), (x2 - int(w * 0.16), body_bot), shirt_color, -1)
    arm_w = max(2, int(w * 0.12))
    cv2.rectangle(canvas, (x1 + int(w * 0.04), body_top + 2), (x1 + int(w * 0.16), body_bot - 4), shirt_color, -1)
    cv2.rectangle(canvas, (x2 - int(w * 0.16), body_top + 2), (x2 - int(w * 0.04), body_bot - 4), shirt_color, -1)
    pants_color = (random.randint(25, 85), random.randint(25, 85), random.randint(35, 95))
    leg_w = max(2, int(w * 0.22))
    cv2.rectangle(canvas, (x1 + int(w * 0.20), body_bot), (x1 + int(w * 0.20) + leg_w, y2), pants_color, -1)
    cv2.rectangle(canvas, (x2 - int(w * 0.20) - leg_w, body_bot), (x2 - int(w * 0.20), y2), pants_color, -1)

def draw_tree(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    draw_shadow(canvas, x1, y2, w)
    trunk_w = max(10, int(w * random.uniform(0.18, 0.28)))
    trunk_x1 = x1 + (w - trunk_w) // 2
    trunk_x2 = trunk_x1 + trunk_w
    trunk_y1 = y1 + int(h * 0.32)
    bark_base = (random.randint(25, 50), random.randint(45, 80), random.randint(75, 120))
    cv2.rectangle(canvas, (trunk_x1, trunk_y1), (trunk_x2, y2), bark_base, -1)
    canopy_cx = x1 + w // 2
    canopy_cy = y1 + int(h * 0.32)
    canopy_r = max(15, int(w * 0.46))
    foliage_base = (random.randint(30, 60), random.randint(110, 160), random.randint(35, 75))
    cv2.circle(canvas, (canopy_cx, canopy_cy), canopy_r, foliage_base, -1)

def draw_chair(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    draw_shadow(canvas, x1, y2, w)
    color = (random.randint(40, 180), random.randint(40, 180), random.randint(40, 180))
    cv2.rectangle(canvas, (x1 + int(w * 0.1), y1), (x2 - int(w * 0.1), y1 + int(h * 0.45)), color, -1)
    cv2.rectangle(canvas, (x1, y1 + int(h * 0.45)), (x2, y1 + int(h * 0.58)), color, -1)
    leg_w = max(2, int(w * 0.08))
    cv2.rectangle(canvas, (x1 + int(w * 0.05), y1 + int(h * 0.58)), (x1 + int(w * 0.05) + leg_w, y2), (30, 30, 30), -1)
    cv2.rectangle(canvas, (x2 - int(w * 0.05) - leg_w, y1 + int(h * 0.58)), (x2 - int(w * 0.05), y2), (30, 30, 30), -1)

def draw_table(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    draw_shadow(canvas, x1, y2, w)
    top_color = (random.randint(40, 120), random.randint(60, 140), random.randint(100, 180))
    cv2.rectangle(canvas, (x1, y1), (x2, y1 + int(h * 0.25)), top_color, -1)
    leg_w = max(3, int(w * 0.07))
    cv2.rectangle(canvas, (x1 + int(w * 0.06), y1 + int(h * 0.25)), (x1 + int(w * 0.06) + leg_w, y2), (30, 30, 30), -1)
    cv2.rectangle(canvas, (x2 - int(w * 0.06) - leg_w, y1 + int(h * 0.25)), (x2 - int(w * 0.06), y2), (30, 30, 30), -1)

def draw_door(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    door_color = (random.randint(50, 100), random.randint(70, 120), random.randint(110, 170))
    cv2.rectangle(canvas, (x1, y1), (x2, y2), (40, 40, 40), 3)
    cv2.rectangle(canvas, (x1 + 3, y1 + 3), (x2 - 3, y2 - 3), door_color, -1)
    knob_x = x2 - max(6, int(w * 0.15))
    knob_y = y1 + h // 2
    cv2.circle(canvas, (knob_x, knob_y), max(3, int(w * 0.04)), (30, 180, 220), -1)

def draw_stairs(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    num_steps = random.randint(4, 7)
    step_h = h // num_steps
    for i in range(num_steps):
        sy1 = y2 - (i + 1) * step_h
        sy2 = y2 - i * step_h
        sx1 = x1 + int(w * (0.05 * (num_steps - i)))
        sx2 = x2 - int(w * (0.05 * (num_steps - i)))
        color = (130 + i * 15, 130 + i * 15, 130 + i * 15)
        cv2.rectangle(canvas, (sx1, sy1), (sx2, sy2), color, -1)

def draw_signboard(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    post_w = max(3, int(w * 0.08))
    post_x = x1 + (w - post_w) // 2
    cv2.rectangle(canvas, (post_x, y1 + int(h * 0.5)), (post_x + post_w, y2), (70, 70, 70), -1)
    sign_color = (230, 230, 230) if random.random() > 0.5 else (40, 160, 240)
    cv2.rectangle(canvas, (x1, y1), (x2, y1 + int(h * 0.55)), sign_color, -1)

def draw_vehicle(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    draw_shadow(canvas, x1, y2, w)
    color = (random.randint(40, 220), random.randint(40, 220), random.randint(40, 220))
    cv2.rectangle(canvas, (x1, y1 + int(h * 0.35)), (x2, y2 - int(h * 0.15)), color, -1)
    cv2.rectangle(canvas, (x1 + int(w * 0.2), y1), (x2 - int(w * 0.2), y1 + int(h * 0.35)), color, -1)
    cv2.rectangle(canvas, (x1 + int(w * 0.25), y1 + int(h * 0.05)), (x2 - int(w * 0.25), y1 + int(h * 0.32)), (220, 240, 255), -1)
    wheel_r = max(4, int(w * 0.08))
    cv2.circle(canvas, (x1 + int(w * 0.25), y2 - int(h * 0.15)), wheel_r, (30, 30, 30), -1)
    cv2.circle(canvas, (x2 - int(w * 0.25), y2 - int(h * 0.15)), wheel_r, (30, 30, 30), -1)

def draw_pole(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    x1, y1, x2, y2 = bbox
    w = x2 - x1
    draw_shadow(canvas, x1, y2, w)
    cv2.rectangle(canvas, (x1, y1), (x2, y2), (95, 100, 105), -1)

def draw_laptop(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    cv2.rectangle(canvas, (x1 + int(w * 0.1), y1), (x2 - int(w * 0.1), y1 + int(h * 0.65)), (50, 50, 50), -1)
    cv2.rectangle(canvas, (x1 + int(w * 0.15), y1 + int(h * 0.05)), (x2 - int(w * 0.15), y1 + int(h * 0.60)), (180, 220, 255), -1)
    cv2.rectangle(canvas, (x1, y1 + int(h * 0.65)), (x2, y2), (70, 70, 70), -1)

def draw_bottle(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    color = (random.randint(60, 200), random.randint(120, 230), random.randint(180, 255))
    cv2.rectangle(canvas, (x1 + int(w * 0.35), y1), (x2 - int(w * 0.35), y1 + int(h * 0.15)), (40, 40, 40), -1)
    cv2.rectangle(canvas, (x1, y1 + int(h * 0.15)), (x2, y2), color, -1)

def draw_potted_plant(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    draw_shadow(canvas, x1, y2, w)
    pot_top = y1 + int(h * 0.50)
    pts = np.array([[x1 + int(w * 0.15), pot_top], [x2 - int(w * 0.15), pot_top], [x2 - int(w * 0.25), y2], [x1 + int(w * 0.25), y2]], np.int32)
    cv2.fillPoly(canvas, [pts], (40, 70, 160))
    for _ in range(6):
        lx = random.randint(x1 + int(w * 0.1), x2 - int(w * 0.1))
        ly = random.randint(y1 + int(h * 0.1), pot_top + 5)
        cv2.circle(canvas, (lx, ly), max(4, int(w * 0.15)), (35, random.randint(130, 180), 45), -1)

def draw_bench(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    draw_shadow(canvas, x1, y2, w)
    wood_col = (45, 90, 155)
    cv2.rectangle(canvas, (x1, y1), (x2, y1 + int(h * 0.35)), wood_col, -1)
    cv2.rectangle(canvas, (x1, y1 + int(h * 0.40)), (x2, y1 + int(h * 0.60)), wood_col, -1)
    cv2.rectangle(canvas, (x1 + int(w * 0.08), y1 + int(h * 0.60)), (x1 + int(w * 0.18), y2), (40, 40, 40), -1)
    cv2.rectangle(canvas, (x2 - int(w * 0.18), y1 + int(h * 0.60)), (x2 - int(w * 0.08), y2), (40, 40, 40), -1)

def draw_trash_bin(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    draw_shadow(canvas, x1, y2, w)
    cv2.rectangle(canvas, (x1 + int(w * 0.1), y1 + int(h * 0.15)), (x2 - int(w * 0.1), y2), (100, 110, 110), -1)
    cv2.rectangle(canvas, (x1, y1), (x2, y1 + int(h * 0.15)), (50, 50, 50), -1)

def draw_bicycle(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    draw_shadow(canvas, x1, y2, w)
    wheel_r = max(5, int(w * 0.18))
    cv2.circle(canvas, (x1 + wheel_r + 2, y2 - wheel_r - 2), wheel_r, (40, 40, 40), 2)
    cv2.circle(canvas, (x2 - wheel_r - 2, y2 - wheel_r - 2), wheel_r, (40, 40, 40), 2)
    cv2.line(canvas, (x1 + wheel_r + 2, y2 - wheel_r - 2), (x1 + w // 2, y2 - int(h * 0.35)), (20, 40, 200), 2)
    cv2.line(canvas, (x1 + w // 2, y2 - int(h * 0.35)), (x2 - wheel_r - 2, y2 - wheel_r - 2), (20, 40, 200), 2)

def draw_fire_hydrant(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    draw_shadow(canvas, x1, y2, w)
    cv2.rectangle(canvas, (x1 + int(w * 0.25), y1 + int(h * 0.15)), (x2 - int(w * 0.25), y2), (25, 30, 210), -1)
    cv2.circle(canvas, (x1 + w // 2, y1 + int(h * 0.20)), max(4, int(w * 0.25)), (25, 30, 210), -1)

# ==============================================================================
# Everyday Assistive Belongings & Sonar Target Classes (16 to 31)
# ==============================================================================

def draw_ironbox(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    """Renders a clothes steam ironbox with soleplate, body, handle, and temperature dial."""
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    draw_shadow(canvas, x1, y2, w)
    # Metallic soleplate (pointed triangle/polygon at front)
    sole_pts = np.array([
        [x1, y2],
        [x2, y2],
        [x2, y2 - int(h * 0.18)],
        [x1 + int(w * 0.15), y2 - int(h * 0.18)]
    ], np.int32)
    cv2.fillPoly(canvas, [sole_pts], (210, 210, 210))
    # Plastic body (vivid blue/teal)
    body_color = (random.randint(160, 220), random.randint(100, 160), random.randint(30, 70))
    cv2.rectangle(canvas, (x1 + int(w * 0.15), y1 + int(h * 0.35)), (x2 - int(w * 0.05), y2 - int(h * 0.18)), body_color, -1)
    # Ergonomic curved handle
    cv2.rectangle(canvas, (x1 + int(w * 0.25), y1), (x2 - int(w * 0.15), y1 + int(h * 0.25)), (50, 50, 50), -1)
    # Dial
    cv2.circle(canvas, (x1 + int(w * 0.55), y1 + int(h * 0.45)), max(3, int(w * 0.10)), (240, 240, 240), -1)

def draw_keys(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    """Renders a metallic keyring with 2-3 jagged keys."""
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    ring_r = max(4, int(w * 0.25))
    cv2.circle(canvas, (x1 + w // 2, y1 + ring_r + 2), ring_r, (190, 190, 190), 2)
    for offset in [-int(w * 0.2), 0, int(w * 0.2)]:
        kx = x1 + w // 2 + offset
        cv2.line(canvas, (kx, y1 + ring_r * 2), (kx, y2), (210, 210, 210), 2)
        cv2.line(canvas, (kx, y2 - 4), (kx + 4, y2 - 4), (210, 210, 210), 2)

def draw_wallet(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    """Renders a bi-fold leather wallet."""
    x1, y1, x2, y2 = bbox
    draw_shadow(canvas, x1, y2, x2 - x1)
    leather_col = (random.randint(30, 55), random.randint(50, 80), random.randint(90, 140))
    cv2.rectangle(canvas, (x1, y1), (x2, y2), leather_col, -1)
    cv2.rectangle(canvas, (x1, y1), (x2, y2), (20, 20, 20), 1)
    cv2.line(canvas, (x1, y1 + (y2 - y1) // 2), (x2, y1 + (y2 - y1) // 2), (200, 200, 200), 1)

def draw_white_cane(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    """Renders a blind mobility white cane with red base band and rolling ball tip."""
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    cx = x1 + w // 2
    # Rubber handle
    cv2.line(canvas, (cx, y1), (cx, y1 + int(h * 0.20)), (30, 30, 30), 4)
    # White shaft
    cv2.line(canvas, (cx, y1 + int(h * 0.20)), (cx, y2 - int(h * 0.20)), (245, 245, 245), 3)
    # Red high-vis bottom band
    cv2.line(canvas, (cx, y2 - int(h * 0.20)), (cx, y2 - 4), (20, 25, 220), 3)
    # Rolling tip
    cv2.circle(canvas, (cx, y2 - 2), 3, (245, 245, 245), -1)

def draw_glasses(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    """Renders eyeglasses / sunglasses frames."""
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    frame_col = (30, 30, 30)
    lens_w = max(5, int(w * 0.38))
    cv2.rectangle(canvas, (x1 + 2, y1 + 2), (x1 + 2 + lens_w, y2 - 2), frame_col, 2)
    cv2.rectangle(canvas, (x2 - 2 - lens_w, y1 + 2), (x2 - 2, y2 - 2), frame_col, 2)
    # Bridge
    cv2.line(canvas, (x1 + 2 + lens_w, y1 + h // 2), (x2 - 2 - lens_w, y1 + h // 2), frame_col, 2)

def draw_cell_phone(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    """Renders a smartphone with screen and bezel."""
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    cv2.rectangle(canvas, (x1, y1), (x2, y2), (30, 30, 30), -1)
    cv2.rectangle(canvas, (x1 + 3, y1 + 6), (x2 - 3, y2 - 6), (20, 20, 20), -1)
    # Screen reflection
    cv2.line(canvas, (x1 + 5, y1 + 10), (x2 - 5, y2 - 15), (70, 70, 70), 1)

def draw_charger(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    """Renders a power adapter cube with cable."""
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    cv2.rectangle(canvas, (x1 + int(w * 0.2), y1), (x2 - int(w * 0.2), y1 + int(h * 0.5)), (240, 240, 240), -1)
    cv2.line(canvas, (x1 + w // 2, y1 + int(h * 0.5)), (x1 + int(w * 0.2), y2), (40, 40, 40), 2)

def draw_shoes(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    """Renders a pair of footwear/shoes."""
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    draw_shadow(canvas, x1, y2, w)
    shoe_col = (random.randint(40, 180), random.randint(40, 180), random.randint(40, 180))
    cv2.ellipse(canvas, (x1 + int(w * 0.3), y1 + int(h * 0.5)), (max(4, int(w * 0.22)), max(4, int(h * 0.4))), 0, 0, 360, shoe_col, -1)
    cv2.ellipse(canvas, (x1 + int(w * 0.7), y1 + int(h * 0.5)), (max(4, int(w * 0.22)), max(4, int(h * 0.4))), 0, 0, 360, shoe_col, -1)

def draw_cup(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    """Renders a coffee mug with side handle."""
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    mug_col = (random.randint(180, 240), random.randint(180, 240), random.randint(180, 240))
    cv2.rectangle(canvas, (x1, y1), (x2 - int(w * 0.25), y2), mug_col, -1)
    cv2.ellipse(canvas, (x2 - int(w * 0.25), y1 + h // 2), (max(3, int(w * 0.2)), max(3, int(h * 0.3))), 0, -90, 90, (180, 180, 180), 2)

def draw_plate(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    """Renders a dining ceramic plate."""
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    draw_shadow(canvas, x1, y2, w)
    cv2.ellipse(canvas, (x1 + w // 2, y1 + h // 2), (w // 2, h // 2), 0, 0, 360, (230, 230, 230), -1)
    cv2.ellipse(canvas, (x1 + w // 2, y1 + h // 2), (int(w * 0.35), int(h * 0.35)), 0, 0, 360, (200, 200, 200), 1)

def draw_spoon(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    """Renders a metallic utensil spoon."""
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    cx = x1 + w // 2
    cv2.ellipse(canvas, (cx, y1 + int(h * 0.25)), (max(3, int(w * 0.35)), max(4, int(h * 0.22))), 0, 0, 360, (215, 215, 215), -1)
    cv2.line(canvas, (cx, y1 + int(h * 0.45)), (cx, y2), (215, 215, 215), 2)

def draw_medicine_bottle(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    """Renders an amber prescription pill bottle with white child-proof cap."""
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    draw_shadow(canvas, x1, y2, w)
    cv2.rectangle(canvas, (x1 + int(w * 0.15), y1), (x2 - int(w * 0.15), y1 + int(h * 0.18)), (245, 245, 245), -1)
    cv2.rectangle(canvas, (x1, y1 + int(h * 0.18)), (x2, y2), (30, 90, 180), -1)
    cv2.rectangle(canvas, (x1 + 2, y1 + int(h * 0.35)), (x2 - 2, y2 - int(h * 0.25)), (240, 240, 240), -1)

def draw_headphones(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    """Renders over-ear headphones with arched headband and earcups."""
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    cv2.ellipse(canvas, (x1 + w // 2, y1 + int(h * 0.4)), (int(w * 0.45), int(h * 0.38)), 0, 180, 360, (40, 40, 40), 3)
    cv2.ellipse(canvas, (x1 + int(w * 0.12), y2 - int(h * 0.3)), (max(4, int(w * 0.12)), max(6, int(h * 0.25))), 0, 0, 360, (30, 30, 30), -1)
    cv2.ellipse(canvas, (x2 - int(w * 0.12), y2 - int(h * 0.3)), (max(4, int(w * 0.12)), max(6, int(h * 0.25))), 0, 0, 360, (30, 30, 30), -1)

def draw_watch(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    """Renders a wristwatch with strap and round face."""
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    cx, cy = x1 + w // 2, y1 + h // 2
    cv2.rectangle(canvas, (cx - 3, y1), (cx + 3, y2), (50, 50, 50), -1)
    cv2.circle(canvas, (cx, cy), max(5, int(min(w, h) * 0.4)), (220, 220, 220), -1)
    cv2.line(canvas, (cx, cy), (cx, cy - 3), (20, 20, 20), 1)

def draw_remote(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    """Renders a TV / device remote control with keypad buttons."""
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    cv2.rectangle(canvas, (x1, y1), (x2, y2), (35, 35, 35), -1)
    cv2.circle(canvas, (x1 + w // 2, y1 + 5), 2, (20, 20, 220), -1)
    for r in range(3):
        for c in range(2):
            bx = x1 + int(w * (0.25 + c * 0.4))
            by = y1 + int(h * (0.3 + r * 0.18))
            cv2.rectangle(canvas, (bx - 2, by - 2), (bx + 2, by + 2), (180, 180, 180), -1)

def draw_pen(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    """Renders a writing pen with clip."""
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    cx = x1 + w // 2
    cv2.line(canvas, (cx, y1 + 4), (cx, y2), (random.randint(40, 200), random.randint(40, 200), 200), 2)
    cv2.circle(canvas, (cx, y1 + 2), 2, (180, 180, 180), -1)

RENDER_FUNCS = [
    draw_person,          # 0
    draw_tree,            # 1
    draw_chair,           # 2
    draw_table,           # 3
    draw_door,            # 4
    draw_stairs,          # 5
    draw_signboard,       # 6
    draw_vehicle,         # 7
    draw_pole,            # 8
    draw_laptop,          # 9
    draw_bottle,          # 10
    draw_potted_plant,    # 11
    draw_bench,           # 12
    draw_trash_bin,       # 13
    draw_bicycle,         # 14
    draw_fire_hydrant,    # 15
    draw_ironbox,         # 16
    draw_keys,            # 17
    draw_wallet,          # 18
    draw_white_cane,      # 19
    draw_glasses,         # 20
    draw_cell_phone,      # 21
    draw_charger,         # 22
    draw_shoes,           # 23
    draw_cup,             # 24
    draw_plate,           # 25
    draw_spoon,           # 26
    draw_medicine_bottle, # 27
    draw_headphones,      # 28
    draw_watch,           # 29
    draw_remote,          # 30
    draw_pen,             # 31
]

def generate_scene(width: int = 640, height: int = 640) -> Tuple[np.ndarray, List[Tuple[int, float, float, float, float]]]:
    """Generates a realistic background with 1 to 4 distinct object obstacles."""
    scene_type = random.choice(["outdoor_day", "outdoor_park", "indoor_hall", "indoor_room"])
    
    if scene_type == "outdoor_park":
        bg_top = (random.randint(180, 240), random.randint(200, 245), random.randint(150, 220))
        bg_bot = (random.randint(40, 90), random.randint(110, 160), random.randint(40, 90))
    elif scene_type == "outdoor_day":
        bg_top = (random.randint(210, 250), random.randint(190, 230), random.randint(160, 210))
        bg_bot = (random.randint(90, 130), random.randint(90, 130), random.randint(90, 130))
    elif scene_type == "indoor_hall":
        bg_top = (random.randint(190, 230), random.randint(190, 230), random.randint(190, 230))
        bg_bot = (random.randint(120, 160), random.randint(120, 160), random.randint(130, 170))
    else:
        bg_top = (random.randint(170, 220), random.randint(170, 220), random.randint(170, 220))
        bg_bot = (random.randint(70, 120), random.randint(60, 110), random.randint(50, 100))

    img = np.zeros((height, width, 3), dtype=np.uint8)
    for y in range(height):
        alpha = y / height
        color = [int(bg_top[c] * (1 - alpha) + bg_bot[c] * alpha) for c in range(3)]
        img[y, :] = color

    noise = np.random.normal(0, 7, img.shape).astype(np.int16)
    img = np.clip(img.astype(np.int16) + noise, 0, 255).astype(np.uint8)

    horizon_y = int(height * random.uniform(0.38, 0.52))
    cv2.line(img, (0, horizon_y), (width, horizon_y), (60, 60, 60), 2)

    num_objects = random.randint(1, 4)
    annotations = []

    for _ in range(num_objects):
        class_id = random.randint(0, len(CLASSES) - 1)
        
        if class_id == 0: # Person
            obj_w = random.randint(70, 160)
            obj_h = int(obj_w * random.uniform(2.0, 2.8))
        elif class_id == 1: # Tree
            obj_w = random.randint(140, 280)
            obj_h = int(obj_w * random.uniform(1.3, 2.0))
        elif class_id in (2, 3): # Chair / Table
            obj_w = random.randint(90, 200)
            obj_h = int(obj_w * random.uniform(0.8, 1.4))
        elif class_id == 4: # Door
            obj_w = random.randint(110, 190)
            obj_h = int(obj_w * random.uniform(1.8, 2.3))
        elif class_id == 5: # Stairs
            obj_w = random.randint(150, 260)
            obj_h = int(obj_w * random.uniform(0.7, 1.2))
        elif class_id == 6: # Signboard
            obj_w = random.randint(130, 220)
            obj_h = int(obj_w * random.uniform(0.35, 0.65))
        elif class_id == 7: # Vehicle
            obj_w = random.randint(170, 300)
            obj_h = int(obj_w * random.uniform(0.5, 0.75))
        elif class_id in (8, 19): # Pole / White Cane
            obj_w = random.randint(20, 45)
            obj_h = int(obj_w * random.uniform(4.0, 7.0))
        elif class_id in (9, 21, 30): # Laptop / Cell Phone / Remote
            obj_w = random.randint(50, 140)
            obj_h = int(obj_w * random.uniform(1.2, 2.0))
        elif class_id in (10, 27): # Bottle / Medicine
            obj_w = random.randint(30, 65)
            obj_h = int(obj_w * random.uniform(1.6, 2.4))
        elif class_id == 16: # Ironbox
            obj_w = random.randint(90, 160)
            obj_h = int(obj_w * random.uniform(0.55, 0.85))
        elif class_id in (17, 18, 20, 22, 29): # Keys / Wallet / Glasses / Charger / Watch
            obj_w = random.randint(40, 80)
            obj_h = int(obj_w * random.uniform(0.7, 1.3))
        elif class_id in (24, 25, 26): # Cup / Plate / Spoon
            obj_w = random.randint(45, 100)
            obj_h = int(obj_w * random.uniform(0.7, 1.2))
        elif class_id in (23, 28): # Shoes / Headphones
            obj_w = random.randint(80, 150)
            obj_h = int(obj_w * random.uniform(0.6, 1.1))
        elif class_id == 31: # Pen
            obj_w = random.randint(15, 30)
            obj_h = int(obj_w * random.uniform(4.0, 6.5))
        else:
            obj_w = random.randint(50, 120)
            obj_h = int(obj_w * random.uniform(0.8, 1.4))

        obj_h = min(obj_h, height - 50)
        obj_w = min(obj_w, width - 50)

        if class_id in (6,):
            x1 = random.randint(15, max(16, width - obj_w - 15))
            y1 = random.randint(15, max(16, horizon_y - obj_h))
        elif class_id in (1,):
            x1 = random.randint(15, max(16, width - obj_w - 15))
            y1 = max(15, horizon_y - int(obj_h * 0.4))
        else:
            x1 = random.randint(15, max(16, width - obj_w - 15))
            y1 = random.randint(max(15, horizon_y - obj_h // 2), max(16, height - obj_h - 15))

        x2 = min(width - 5, x1 + obj_w)
        y2 = min(height - 5, y1 + obj_h)

        RENDER_FUNCS[class_id](img, (x1, y1, x2, y2))

        x_center = ((x1 + x2) / 2.0) / width
        y_center = ((y1 + y2) / 2.0) / height
        norm_w = (x2 - x1) / width
        norm_h = (y2 - y1) / height

        annotations.append((class_id, x_center, y_center, norm_w, norm_h))

    return img, annotations

def build_dataset(num_train: int = 1200, num_val: int = 240):
    """Generates large train and validation sets and writes data.yaml."""
    create_directory_structure()
    print(f"Generating {num_train} training samples and {num_val} validation samples for {len(CLASSES)} classes...")

    for split, count in [("train", num_train), ("val", num_val)]:
        for i in range(count):
            img, annots = generate_scene(640, 640)
            base_name = f"orbisnav_{split}_{i:04d}"
            
            img_path = os.path.join(DATASET_DIR, "images", split, f"{base_name}.jpg")
            cv2.imwrite(img_path, img)

            label_path = os.path.join(DATASET_DIR, "labels", split, f"{base_name}.txt")
            with open(label_path, "w") as f:
                for cls_id, xc, yc, nw, nh in annots:
                    f.write(f"{cls_id} {xc:.6f} {yc:.6f} {nw:.6f} {nh:.6f}\n")

    yaml_content = f"""# OrbisNav Assistive Spatial Perception & Lost Item Dataset (32 Classes)
path: {DATASET_DIR}
train: images/train
val: images/val

# Classes
nc: {len(CLASSES)}
names: {CLASSES}
"""
    yaml_path = os.path.join(DATASET_DIR, "data.yaml")
    with open(yaml_path, "w") as f:
        f.write(yaml_content)

    print(f"Dataset generation complete! data.yaml written to: {yaml_path}")
    return yaml_path

if __name__ == "__main__":
    build_dataset(num_train=1200, num_val=240)
