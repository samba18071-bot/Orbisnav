"""
OrbisNav Comprehensive Assistive Navigation Dataset Generator (Max Accuracy Edition).
Procedurally generates structured YOLOv8 training and validation datasets with 
realistic bounding box annotations for all primary assistive spatial obstacles,
including trees, pedestrians, vehicles, structural hazards, and daily objects,
without downloading external datasets.

Classes:
0: person (Moving pedestrian hazard)
1: tree (Outdoor navigation & pathway obstacle)
2: chair (Stationary indoor seating obstacle)
3: table (Room / corridor furniture obstacle)
4: door (Waypoint & entrance)
5: stairs (Level change critical hazard)
6: signboard (Landmark & wayfinding plaque)
7: vehicle (Car / Bus / Truck outdoor hazard)
8: pole (Vertical street / corridor obstacle)
9: laptop (Desktop context)
10: bottle (Tabletop item)
11: potted_plant (Floor / walkway greenery)
12: bench (Park / sidewalk seating obstacle)
13: trash_bin (Curbside / indoor waste receptacle)
14: bicycle (Pavement / bike lane hazard)
15: fire_hydrant (Sidewalk tripping obstacle)
"""

import os
import random
import math
from typing import List, Tuple
import cv2
import numpy as np

CLASSES = [
    "person",
    "tree",
    "chair",
    "table",
    "door",
    "stairs",
    "signboard",
    "vehicle",
    "pole",
    "laptop",
    "bottle",
    "potted_plant",
    "bench",
    "trash_bin",
    "bicycle",
    "fire_hydrant",
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
    """Renders a realistic stylized pedestrian with clothing, arms, legs, and shadow."""
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    draw_shadow(canvas, x1, y2, w)
    
    head_r = max(4, int(w * 0.22))
    head_cx = x1 + w // 2
    head_cy = y1 + int(h * 0.16)
    
    # Head & Hair
    skin_color = (random.randint(140, 210), random.randint(170, 225), random.randint(200, 245))
    hair_color = (random.randint(20, 50), random.randint(20, 50), random.randint(20, 50))
    cv2.circle(canvas, (head_cx, head_cy), head_r, skin_color, -1)
    cv2.circle(canvas, (head_cx, head_cy - int(head_r * 0.4)), int(head_r * 0.8), hair_color, -1)
    
    # Shirt / Upper Torso
    shirt_color = (random.randint(30, 230), random.randint(30, 230), random.randint(30, 230))
    body_top = head_cy + head_r
    body_bot = y1 + int(h * 0.58)
    cv2.rectangle(canvas, (x1 + int(w * 0.16), body_top), (x2 - int(w * 0.16), body_bot), shirt_color, -1)
    
    # Arms
    arm_w = max(2, int(w * 0.12))
    cv2.rectangle(canvas, (x1 + int(w * 0.04), body_top + 2), (x1 + int(w * 0.16), body_bot - 4), shirt_color, -1)
    cv2.rectangle(canvas, (x2 - int(w * 0.16), body_top + 2), (x2 - int(w * 0.04), body_bot - 4), shirt_color, -1)
    
    # Pants / Legs
    pants_color = (random.randint(25, 85), random.randint(25, 85), random.randint(35, 95))
    leg_w = max(2, int(w * 0.22))
    cv2.rectangle(canvas, (x1 + int(w * 0.20), body_bot), (x1 + int(w * 0.20) + leg_w, y2), pants_color, -1)
    cv2.rectangle(canvas, (x2 - int(w * 0.20) - leg_w, body_bot), (x2 - int(w * 0.20), y2), pants_color, -1)

def draw_tree(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    """Renders a realistic tree with textured bark, branching limbs, root flares, and lush canopy."""
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    draw_shadow(canvas, x1, y2, w)
    
    # Trunk dimensions
    trunk_w = max(10, int(w * random.uniform(0.18, 0.28)))
    trunk_x1 = x1 + (w - trunk_w) // 2
    trunk_x2 = trunk_x1 + trunk_w
    trunk_y1 = y1 + int(h * 0.32)
    trunk_y2 = y2
    
    # Bark color & gradient
    bark_base = (random.randint(25, 50), random.randint(45, 80), random.randint(75, 120))
    cv2.rectangle(canvas, (trunk_x1, trunk_y1), (trunk_x2, trunk_y2), bark_base, -1)
    
    # Root flare at bottom
    root_pts = np.array([
        [trunk_x1 - int(trunk_w * 0.4), trunk_y2],
        [trunk_x1, trunk_y2 - int(h * 0.10)],
        [trunk_x2, trunk_y2 - int(h * 0.10)],
        [trunk_x2 + int(trunk_w * 0.4), trunk_y2]
    ], np.int32)
    cv2.fillPoly(canvas, [root_pts], bark_base)
    
    # Bark vertical ridges
    for tx in range(trunk_x1 + 2, trunk_x2 - 1, 3):
        ridge_color = (max(10, bark_base[0] - 15), max(15, bark_base[1] - 20), max(25, bark_base[2] - 25))
        cv2.line(canvas, (tx, trunk_y1), (tx, trunk_y2), ridge_color, 1)
        
    # Main branches
    branch_color = bark_base
    cv2.line(canvas, (trunk_x1 + trunk_w // 2, trunk_y1 + int(h * 0.15)), 
             (x1 + int(w * 0.22), y1 + int(h * 0.22)), branch_color, max(2, trunk_w // 3))
    cv2.line(canvas, (trunk_x1 + trunk_w // 2, trunk_y1 + int(h * 0.15)), 
             (x2 - int(w * 0.22), y1 + int(h * 0.22)), branch_color, max(2, trunk_w // 3))
    
    # Foliage Canopy
    canopy_cx = x1 + w // 2
    canopy_cy = y1 + int(h * 0.28)
    
    leaf_palettes = [
        [(30, 110, 30), (40, 145, 40), (50, 175, 55), (65, 200, 70), (25, 90, 25)],
        [(20, 80, 25), (25, 105, 35), (35, 130, 45), (45, 155, 55), (15, 65, 20)],
        [(35, 100, 60), (45, 125, 75), (60, 150, 95), (75, 175, 115), (25, 80, 45)],
        [(20, 80, 180), (30, 110, 210), (40, 140, 230), (50, 170, 245), (15, 60, 150)],
    ]
    palette = random.choice(leaf_palettes)
    
    # Background mass
    cv2.ellipse(canvas, (canopy_cx, canopy_cy), (w // 2, int(h * 0.30)), 0, 0, 360, palette[0], -1)
    
    # Multi-cluster leafy foliage
    num_clusters = random.randint(10, 16)
    for _ in range(num_clusters):
        cx = random.randint(x1 + int(w * 0.12), x2 - int(w * 0.12))
        cy = random.randint(y1 + int(h * 0.06), y1 + int(h * 0.50))
        radius = random.randint(max(8, int(w * 0.16)), max(12, int(w * 0.30)))
        leaf_col = random.choice(palette)
        cv2.circle(canvas, (cx, cy), radius, leaf_col, -1)

def draw_chair(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    """Renders a chair shape."""
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    draw_shadow(canvas, x1, y2, w)
    color = (random.randint(60, 140), random.randint(50, 110), random.randint(40, 95))
    
    # Backrest
    cv2.rectangle(canvas, (x1 + int(w * 0.1), y1), (x2 - int(w * 0.1), y1 + int(h * 0.45)), color, -1)
    # Seat
    cv2.rectangle(canvas, (x1, y1 + int(h * 0.45)), (x2, y1 + int(h * 0.55)), color, -1)
    # Legs
    cv2.rectangle(canvas, (x1 + int(w * 0.1), y1 + int(h * 0.55)), (x1 + int(w * 0.2), y2), color, -1)
    cv2.rectangle(canvas, (x2 - int(w * 0.2), y1 + int(h * 0.55)), (x2 - int(w * 0.1), y2), color, -1)

def draw_table(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    """Renders a table."""
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    draw_shadow(canvas, x1, y2, w)
    color = (random.randint(80, 160), random.randint(70, 130), random.randint(50, 100))
    
    cv2.rectangle(canvas, (x1, y1), (x2, y1 + int(h * 0.25)), color, -1)
    cv2.rectangle(canvas, (x1 + int(w * 0.05), y1 + int(h * 0.25)), (x1 + int(w * 0.15), y2), color, -1)
    cv2.rectangle(canvas, (x2 - int(w * 0.15), y1 + int(h * 0.25)), (x2 - int(w * 0.05), y2), color, -1)

def draw_door(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    """Renders a doorway / entrance."""
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    color = (random.randint(140, 210), random.randint(130, 190), random.randint(110, 170))
    
    cv2.rectangle(canvas, (x1, y1), (x2, y2), (50, 50, 50), 4)
    cv2.rectangle(canvas, (x1 + 4, y1 + 4), (x2 - 4, y2 - 4), color, -1)
    handle_x = x2 - int(w * 0.18)
    handle_y = y1 + int(h * 0.5)
    cv2.circle(canvas, (handle_x, handle_y), max(3, int(w * 0.04)), (20, 20, 20), -1)

def draw_stairs(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    """Renders a staircase with steps."""
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    num_steps = random.randint(4, 7)
    step_h = h // num_steps
    
    for i in range(num_steps):
        sy1 = y1 + i * step_h
        sy2 = sy1 + step_h
        sx1 = x1 + int((i / num_steps) * w * 0.3)
        sx2 = x2 - int(((num_steps - i) / num_steps) * w * 0.1)
        gray = 160 + (i * 12) % 60
        cv2.rectangle(canvas, (sx1, sy1), (sx2, sy2), (gray, gray, gray), -1)
        cv2.rectangle(canvas, (sx1, sy1), (sx2, sy2), (50, 50, 50), 1)

def draw_signboard(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    """Renders a commercial signboard or plaque."""
    x1, y1, x2, y2 = bbox
    bg_color = random.choice([
        (0, 100, 200), (30, 150, 30), (20, 20, 180), (200, 180, 40)
    ])
    cv2.rectangle(canvas, (x1, y1), (x2, y2), bg_color, -1)
    cv2.rectangle(canvas, (x1, y1), (x2, y2), (255, 255, 255), 2)
    cy = y1 + (y2 - y1) // 2
    cv2.line(canvas, (x1 + 8, cy), (x2 - 8, cy), (255, 255, 255), 2)

def draw_vehicle(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    """Renders a vehicle / car."""
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    draw_shadow(canvas, x1, y2, w)
    color = (random.randint(30, 220), random.randint(30, 220), random.randint(30, 220))
    
    # Body
    cv2.rectangle(canvas, (x1, y1 + int(h * 0.35)), (x2, y2 - int(h * 0.2)), color, -1)
    # Cabin
    cv2.rectangle(canvas, (x1 + int(w * 0.2), y1), (x2 - int(w * 0.2), y1 + int(h * 0.35)), color, -1)
    # Windows
    cv2.rectangle(canvas, (x1 + int(w * 0.25), y1 + int(h * 0.05)), (x2 - int(w * 0.25), y1 + int(h * 0.32)), (220, 240, 255), -1)
    # Wheels
    wheel_r = max(4, int(w * 0.08))
    cv2.circle(canvas, (x1 + int(w * 0.25), y2 - int(h * 0.15)), wheel_r, (30, 30, 30), -1)
    cv2.circle(canvas, (x2 - int(w * 0.25), y2 - int(h * 0.15)), wheel_r, (30, 30, 30), -1)

def draw_pole(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    """Renders a vertical bollard / lamp pole."""
    x1, y1, x2, y2 = bbox
    w = x2 - x1
    draw_shadow(canvas, x1, y2, w)
    color = (95, 100, 105)
    cv2.rectangle(canvas, (x1, y1), (x2, y2), color, -1)
    cv2.rectangle(canvas, (x1, y1), (x2, y2), (40, 40, 40), 1)

def draw_laptop(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    """Renders an open laptop."""
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    cv2.rectangle(canvas, (x1 + int(w * 0.1), y1), (x2 - int(w * 0.1), y1 + int(h * 0.65)), (50, 50, 50), -1)
    cv2.rectangle(canvas, (x1 + int(w * 0.15), y1 + int(h * 0.05)), (x2 - int(w * 0.15), y1 + int(h * 0.60)), (180, 220, 255), -1)
    cv2.rectangle(canvas, (x1, y1 + int(h * 0.65)), (x2, y2), (70, 70, 70), -1)

def draw_bottle(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    """Renders a bottle / can."""
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    color = (random.randint(60, 200), random.randint(120, 230), random.randint(180, 255))
    cv2.rectangle(canvas, (x1 + int(w * 0.35), y1), (x2 - int(w * 0.35), y1 + int(h * 0.15)), (40, 40, 40), -1)
    cv2.rectangle(canvas, (x1, y1 + int(h * 0.15)), (x2, y2), color, -1)

def draw_potted_plant(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    """Renders an indoor potted plant with terracotta pot and leafy shoots."""
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    draw_shadow(canvas, x1, y2, w)
    
    pot_top = y1 + int(h * 0.50)
    pot_col = (40, 70, 160)
    pts = np.array([
        [x1 + int(w * 0.15), pot_top],
        [x2 - int(w * 0.15), pot_top],
        [x2 - int(w * 0.25), y2],
        [x1 + int(w * 0.25), y2]
    ], np.int32)
    cv2.fillPoly(canvas, [pts], pot_col)
    
    for _ in range(random.randint(5, 8)):
        lx = random.randint(x1 + int(w * 0.1), x2 - int(w * 0.1))
        ly = random.randint(y1 + int(h * 0.1), pot_top + 5)
        cv2.circle(canvas, (lx, ly), max(4, int(w * 0.15)), (35, random.randint(130, 180), 45), -1)

def draw_bench(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    """Renders a park / corridor bench."""
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    draw_shadow(canvas, x1, y2, w)
    wood_col = (45, 90, 155)
    
    cv2.rectangle(canvas, (x1, y1), (x2, y1 + int(h * 0.35)), wood_col, -1)
    cv2.rectangle(canvas, (x1, y1 + int(h * 0.40)), (x2, y1 + int(h * 0.60)), wood_col, -1)
    cv2.rectangle(canvas, (x1 + int(w * 0.08), y1 + int(h * 0.60)), (x1 + int(w * 0.18), y2), (40, 40, 40), -1)
    cv2.rectangle(canvas, (x2 - int(w * 0.18), y1 + int(h * 0.60)), (x2 - int(w * 0.08), y2), (40, 40, 40), -1)

def draw_trash_bin(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    """Renders a public / room waste bin."""
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    draw_shadow(canvas, x1, y2, w)
    bin_col = (random.randint(70, 120), random.randint(80, 130), random.randint(80, 130))
    cv2.rectangle(canvas, (x1 + int(w * 0.1), y1 + int(h * 0.15)), (x2 - int(w * 0.1), y2), bin_col, -1)
    cv2.rectangle(canvas, (x1, y1), (x2, y1 + int(h * 0.15)), (50, 50, 50), -1)

def draw_bicycle(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    """Renders a bicycle."""
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    draw_shadow(canvas, x1, y2, w)
    
    wheel_r = max(5, int(w * 0.18))
    w1_c = (x1 + wheel_r + 2, y2 - wheel_r - 2)
    w2_c = (x2 - wheel_r - 2, y2 - wheel_r - 2)
    
    cv2.circle(canvas, w1_c, wheel_r, (40, 40, 40), 2)
    cv2.circle(canvas, w2_c, wheel_r, (40, 40, 40), 2)
    
    frame_col = (20, 40, 200)
    mid_bb = (x1 + w // 2, y2 - int(h * 0.35))
    seat_pt = (x1 + int(w * 0.4), y1 + int(h * 0.25))
    handle_pt = (x1 + int(w * 0.7), y1 + int(h * 0.15))
    
    cv2.line(canvas, w1_c, mid_bb, frame_col, 2)
    cv2.line(canvas, mid_bb, w2_c, frame_col, 2)
    cv2.line(canvas, mid_bb, seat_pt, frame_col, 2)
    cv2.line(canvas, seat_pt, w1_c, frame_col, 2)
    cv2.line(canvas, mid_bb, handle_pt, frame_col, 2)
    cv2.line(canvas, handle_pt, w2_c, frame_col, 2)

def draw_fire_hydrant(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    """Renders a street fire hydrant."""
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    draw_shadow(canvas, x1, y2, w)
    red_col = (25, 30, 210)
    
    cv2.rectangle(canvas, (x1 + int(w * 0.25), y1 + int(h * 0.15)), (x2 - int(w * 0.25), y2), red_col, -1)
    cv2.circle(canvas, (x1 + w // 2, y1 + int(h * 0.20)), max(4, int(w * 0.25)), red_col, -1)
    cv2.rectangle(canvas, (x1 + int(w * 0.05), y1 + int(h * 0.40)), (x1 + int(w * 0.25), y1 + int(h * 0.60)), (180, 180, 180), -1)
    cv2.rectangle(canvas, (x2 - int(w * 0.25), y1 + int(h * 0.40)), (x2 - int(w * 0.05), y1 + int(h * 0.60)), (180, 180, 180), -1)

RENDER_FUNCS = [
    draw_person,
    draw_tree,
    draw_chair,
    draw_table,
    draw_door,
    draw_stairs,
    draw_signboard,
    draw_vehicle,
    draw_pole,
    draw_laptop,
    draw_bottle,
    draw_potted_plant,
    draw_bench,
    draw_trash_bin,
    draw_bicycle,
    draw_fire_hydrant,
]

def generate_scene(width: int = 640, height: int = 640) -> Tuple[np.ndarray, List[Tuple[int, float, float, float, float]]]:
    """Generates a realistic indoor/outdoor background with 1 to 4 distinct object obstacles."""
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
        elif class_id == 8: # Pole
            obj_w = random.randint(25, 55)
            obj_h = int(obj_w * random.uniform(4.0, 6.0))
        elif class_id == 9: # Laptop
            obj_w = random.randint(90, 160)
            obj_h = int(obj_w * random.uniform(0.65, 0.9))
        elif class_id == 10: # Bottle
            obj_w = random.randint(30, 65)
            obj_h = int(obj_w * random.uniform(1.8, 2.5))
        elif class_id == 11: # Potted plant
            obj_w = random.randint(70, 140)
            obj_h = int(obj_w * random.uniform(1.1, 1.6))
        elif class_id == 12: # Bench
            obj_w = random.randint(150, 270)
            obj_h = int(obj_w * random.uniform(0.45, 0.75))
        elif class_id == 13: # Trash bin
            obj_w = random.randint(50, 100)
            obj_h = int(obj_w * random.uniform(1.2, 1.7))
        elif class_id == 14: # Bicycle
            obj_w = random.randint(130, 240)
            obj_h = int(obj_w * random.uniform(0.65, 0.95))
        else: # Fire hydrant
            obj_w = random.randint(45, 85)
            obj_h = int(obj_w * random.uniform(1.3, 1.8))

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

def build_dataset(num_train: int = 600, num_val: int = 120):
    """Generates large train and validation sets and writes data.yaml."""
    create_directory_structure()
    print(f"Generating {num_train} training samples and {num_val} validation samples...")

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

    yaml_content = f"""# OrbisNav Custom Assistive Navigation Dataset Configuration
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
    build_dataset(num_train=600, num_val=120)
