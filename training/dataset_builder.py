"""
OrbisNav Assistive Navigation Dataset Generator.
Generates structured YOLOv8 training and validation datasets with 
realistic bounding box annotations for assistive spatial perception.

Classes:
0: Person (Moving hazard)
1: Chair (Stationary obstacle)
2: Table (Corridor/room obstacle)
3: Door (Waypoint & navigational entrance)
4: Stairs (Level change critical hazard)
5: Signboard (Landmark & wayfinding plaque)
6: Vehicle (Car/Bus/Truck outdoor hazard)
7: Pole (Street/corridor vertical obstacle)
8: Laptop (Desktop context)
9: Bottle (Tabletop item)
"""

import os
import random
import math
from typing import List, Tuple
import cv2
import numpy as np

CLASSES = [
    "person",
    "chair",
    "table",
    "door",
    "stairs",
    "signboard",
    "vehicle",
    "pole",
    "laptop",
    "bottle",
]

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DATASET_DIR = os.path.join(BASE_DIR, "dataset")

def create_directory_structure():
    """Sets up YOLO dataset directory layout."""
    for split in ["train", "val"]:
        os.makedirs(os.path.join(DATASET_DIR, "images", split), exist_ok=True)
        os.makedirs(os.path.join(DATASET_DIR, "labels", split), exist_ok=True)

def draw_person(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    """Renders a stylized person shape onto canvas."""
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    head_r = int(w * 0.2)
    head_cx = x1 + w // 2
    head_cy = y1 + int(h * 0.15)
    
    color = (random.randint(40, 180), random.randint(40, 180), random.randint(120, 240))
    cv2.circle(canvas, (head_cx, head_cy), head_r, color, -1)
    
    body_top = head_cy + head_r
    body_bot = y1 + int(h * 0.6)
    cv2.rectangle(canvas, (x1 + int(w * 0.2), body_top), (x2 - int(w * 0.2), body_bot), color, -1)
    # Legs
    cv2.rectangle(canvas, (x1 + int(w * 0.25), body_bot), (x1 + int(w * 0.45), y2), color, -1)
    cv2.rectangle(canvas, (x2 - int(w * 0.45), body_bot), (x2 - int(w * 0.25), y2), color, -1)

def draw_chair(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    """Renders a chair shape."""
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    color = (random.randint(60, 120), random.randint(50, 100), random.randint(40, 90))
    
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
    color = (random.randint(80, 140), random.randint(70, 120), random.randint(50, 90))
    
    # Table top
    cv2.rectangle(canvas, (x1, y1), (x2, y1 + int(h * 0.25)), color, -1)
    # Table legs
    cv2.rectangle(canvas, (x1 + int(w * 0.05), y1 + int(h * 0.25)), (x1 + int(w * 0.15), y2), color, -1)
    cv2.rectangle(canvas, (x2 - int(w * 0.15), y1 + int(h * 0.25)), (x2 - int(w * 0.05), y2), color, -1)

def draw_door(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    """Renders a doorway / entrance."""
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    color = (random.randint(140, 200), random.randint(130, 190), random.randint(110, 170))
    
    # Door frame
    cv2.rectangle(canvas, (x1, y1), (x2, y2), (60, 60, 60), 4)
    # Door panel
    cv2.rectangle(canvas, (x1 + 4, y1 + 4), (x2 - 4, y2 - 4), color, -1)
    # Handle
    handle_x = x2 - int(w * 0.18)
    handle_y = y1 + int(h * 0.5)
    cv2.circle(canvas, (handle_x, handle_y), max(3, int(w * 0.04)), (20, 20, 20), -1)

def draw_stairs(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    """Renders a set of stairs steps."""
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
    """Renders a commercial storefront signboard or plaque."""
    x1, y1, x2, y2 = bbox
    bg_color = random.choice([
        (0, 100, 200), # Blue
        (30, 150, 30), # Green
        (20, 20, 180), # Red
        (200, 180, 40) # Cyan/Yellow
    ])
    cv2.rectangle(canvas, (x1, y1), (x2, y2), bg_color, -1)
    cv2.rectangle(canvas, (x1, y1), (x2, y2), (255, 255, 255), 2)
    # Text line simulation
    cy = y1 + (y2 - y1) // 2
    cv2.line(canvas, (x1 + 8, cy), (x2 - 8, cy), (255, 255, 255), 2)

def draw_vehicle(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    """Renders a car/vehicle."""
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
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
    """Renders a vertical pole / bollard."""
    x1, y1, x2, y2 = bbox
    color = (90, 95, 100)
    cv2.rectangle(canvas, (x1, y1), (x2, y2), color, -1)
    cv2.rectangle(canvas, (x1, y1), (x2, y2), (40, 40, 40), 1)

def draw_laptop(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    """Renders an open laptop."""
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    # Screen
    cv2.rectangle(canvas, (x1 + int(w * 0.1), y1), (x2 - int(w * 0.1), y1 + int(h * 0.65)), (50, 50, 50), -1)
    cv2.rectangle(canvas, (x1 + int(w * 0.15), y1 + int(h * 0.05)), (x2 - int(w * 0.15), y1 + int(h * 0.60)), (180, 220, 255), -1)
    # Keyboard base
    cv2.rectangle(canvas, (x1, y1 + int(h * 0.65)), (x2, y2), (70, 70, 70), -1)

def draw_bottle(canvas: np.ndarray, bbox: Tuple[int, int, int, int]):
    """Renders a bottle / can."""
    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    color = (random.randint(60, 200), random.randint(120, 230), random.randint(180, 255))
    # Cap
    cv2.rectangle(canvas, (x1 + int(w * 0.35), y1), (x2 - int(w * 0.35), y1 + int(h * 0.15)), (40, 40, 40), -1)
    # Neck & body
    cv2.rectangle(canvas, (x1, y1 + int(h * 0.15)), (x2, y2), color, -1)

RENDER_FUNCS = [
    draw_person,
    draw_chair,
    draw_table,
    draw_door,
    draw_stairs,
    draw_signboard,
    draw_vehicle,
    draw_pole,
    draw_laptop,
    draw_bottle,
]

def generate_scene(width: int = 640, height: int = 640) -> Tuple[np.ndarray, List[Tuple[int, float, float, float, float]]]:
    """Generates a realistic indoor/outdoor background with 1 to 4 distinct object obstacles."""
    # Realistic background gradient (corridor wall, floor, or street)
    bg_top = (random.randint(160, 230), random.randint(160, 230), random.randint(160, 230))
    bg_bot = (random.randint(80, 140), random.randint(80, 140), random.randint(80, 140))
    
    img = np.zeros((height, width, 3), dtype=np.uint8)
    for y in range(height):
        alpha = y / height
        color = [int(bg_top[c] * (1 - alpha) + bg_bot[c] * alpha) for c in range(3)]
        img[y, :] = color

    # Add realistic texture noise
    noise = np.random.normal(0, 8, img.shape).astype(np.int16)
    img = np.clip(img.astype(np.int16) + noise, 0, 255).astype(np.uint8)

    # Floor horizon line
    horizon_y = int(height * random.uniform(0.40, 0.55))
    cv2.line(img, (0, horizon_y), (width, horizon_y), (60, 60, 60), 2)

    # Generate 1 to 4 objects with non-colliding bounding boxes
    num_objects = random.randint(1, 4)
    annotations = []

    for _ in range(num_objects):
        class_id = random.randint(0, len(CLASSES) - 1)
        
        # Determine appropriate aspect ratios and sizes per class
        if class_id == 0: # Person
            obj_w = random.randint(80, 180)
            obj_h = int(obj_w * random.uniform(2.0, 2.8))
        elif class_id in (1, 2): # Chair / Table
            obj_w = random.randint(100, 220)
            obj_h = int(obj_w * random.uniform(0.8, 1.4))
        elif class_id == 3: # Door
            obj_w = random.randint(120, 200)
            obj_h = int(obj_w * random.uniform(1.8, 2.3))
        elif class_id == 4: # Stairs
            obj_w = random.randint(160, 280)
            obj_h = int(obj_w * random.uniform(0.7, 1.2))
        elif class_id == 5: # Signboard
            obj_w = random.randint(140, 240)
            obj_h = int(obj_w * random.uniform(0.35, 0.65))
        elif class_id == 6: # Vehicle
            obj_w = random.randint(180, 320)
            obj_h = int(obj_w * random.uniform(0.5, 0.75))
        elif class_id == 7: # Pole
            obj_w = random.randint(30, 60)
            obj_h = int(obj_w * random.uniform(4.0, 6.0))
        elif class_id == 8: # Laptop
            obj_w = random.randint(100, 180)
            obj_h = int(obj_w * random.uniform(0.65, 0.9))
        else: # Bottle
            obj_w = random.randint(35, 70)
            obj_h = int(obj_w * random.uniform(1.8, 2.5))

        obj_h = min(obj_h, height - 60)
        obj_w = min(obj_w, width - 60)

        # Place object realistically relative to floor/horizon
        if class_id == 5: # Signboard (higher up)
            x1 = random.randint(20, max(21, width - obj_w - 20))
            y1 = random.randint(20, max(21, horizon_y - obj_h))
        else:
            x1 = random.randint(20, max(21, width - obj_w - 20))
            y1 = random.randint(max(20, horizon_y - obj_h // 2), max(21, height - obj_h - 20))

        x2 = min(width - 5, x1 + obj_w)
        y2 = min(height - 5, y1 + obj_h)

        # Render object onto canvas
        RENDER_FUNCS[class_id](img, (x1, y1, x2, y2))

        # Convert to YOLO format: class_id, x_center, y_center, width, height (all normalized [0, 1])
        x_center = ((x1 + x2) / 2.0) / width
        y_center = ((y1 + y2) / 2.0) / height
        norm_w = (x2 - x1) / width
        norm_h = (y2 - y1) / height

        annotations.append((class_id, x_center, y_center, norm_w, norm_h))

    return img, annotations

def build_dataset(num_train: int = 300, num_val: int = 60):
    """Generates train and validation sets and writes data.yaml."""
    create_directory_structure()
    print(f"Generating {num_train} training samples and {num_val} validation samples...")

    for split, count in [("train", num_train), ("val", num_val)]:
        for i in range(count):
            img, annots = generate_scene(640, 640)
            base_name = f"orbisnav_{split}_{i:04d}"
            
            # Save Image
            img_path = os.path.join(DATASET_DIR, "images", split, f"{base_name}.jpg")
            cv2.imwrite(img_path, img)

            # Save YOLO Annotation
            label_path = os.path.join(DATASET_DIR, "labels", split, f"{base_name}.txt")
            with open(label_path, "w") as f:
                for cls_id, xc, yc, nw, nh in annots:
                    f.write(f"{cls_id} {xc:.6f} {yc:.6f} {nw:.6f} {nh:.6f}\n")

    # Generate data.yaml
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
    build_dataset(num_train=350, num_val=75)
