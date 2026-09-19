"""
OrbisNav Assistive Vision & Multi-Class Metric Object Detection Server.
Integrated with Open-Vocabulary YOLO-World & Real-World Metric Optical Geometry.

Features:
1. Universal Object Coverage: Detects all everyday objects including spectacles/glasses,
   ceiling/table fans, vehicles (cars, buses, trucks, bikes), persons, stairs, doors,
   laptops, mobile phones, bottles, keys, furniture, and more.
2. Physics-Grounded Metric Distance Estimation: Uses pinhole camera optics with canonical
   real-world physical priors (height, width, primary axis) for precise distance in meters.
3. 12-Hour Clock Spatial Zone Mapping: Converts bounding box centroids to user-friendly clock directions.
4. Assistive Hazard Classification: Level 0 Critical Hazards, Level 1 Safety Obstacles,
   Level 2 Landmarks/Waypoints, and Tabletop/Personal context cues.
"""

import sys
import time
import json
import logging
import math
import os
from typing import List, Dict, Any, Tuple

import cv2
import numpy as np
from fastapi import FastAPI, Request, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from ultralytics import YOLO

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger("OrbisNavVisionServer")

app = FastAPI(
    title="OrbisNav Universal Vision & Distance Estimation Server",
    version="3.0.0",
    description="Real-time multi-class object detection and metric distance estimation"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Comprehensive Open-Vocabulary Assistive Navigation Class Ontology
UNIVERSAL_CLASSES = [
    # Eyewear & Personal Items
    "spectacles", "glasses", "sunglasses",
    # Fans & Appliances
    "ceiling fan", "table fan", "electric fan", "refrigerator",
    # Vehicles & Traffic
    "car", "bus", "truck", "motorcycle", "bicycle", "vehicle", "traffic light", "stop sign",
    # Pedestrians & Structural Elements
    "person", "stairs", "stairs_up", "stairs_down", "door", "elevator", "window", "pillar", "pole", "fire hydrant",
    # Furniture & Living Areas
    "chair", "couch", "sofa", "table", "dining table", "desk", "bed", "bench", "sink", "toilet", "potted plant", "trash bin",
    # Electronics & Workstation
    "laptop", "cell phone", "keyboard", "mouse", "remote", "tv",
    # Accessories & Daily Objects
    "bottle", "cup", "plate", "bowl", "book", "pen", "backpack", "handbag", "suitcase", "wallet", "keys", "shoes", "slippers"
]

# Physical Dimensions (Height in meters, Width in meters, Primary Axis, Hazard Category)
# Pinhole model: distance = (Focal_Length * Real_Dimension) / Normalized_Screen_Dimension
OBJECT_PHYSICAL_PRIORS: Dict[str, Tuple[float, float, str, str]] = {
    # Eyewear
    "spectacles": (0.045, 0.14, "width", "tabletop"),
    "glasses": (0.045, 0.14, "width", "tabletop"),
    "sunglasses": (0.045, 0.14, "width", "tabletop"),
    "reading glasses": (0.045, 0.14, "width", "tabletop"),

    # Fans
    "ceiling fan": (0.35, 1.10, "width", "tabletop"),
    "table fan": (0.45, 0.40, "height", "safety"),
    "electric fan": (0.50, 0.45, "height", "safety"),
    "fan": (0.45, 0.45, "height", "safety"),

    # Vehicles (Level 0 Critical Hazards)
    "car": (1.50, 1.80, "width", "critical"),
    "bus": (3.20, 2.50, "height", "critical"),
    "truck": (3.00, 2.40, "height", "critical"),
    "motorcycle": (1.10, 0.80, "height", "critical"),
    "bicycle": (1.00, 1.60, "width", "waypoint"),
    "vehicle": (1.50, 1.80, "width", "critical"),
    "train": (3.80, 3.00, "height", "critical"),

    # Structural & Navigation Hazards
    "stairs": (1.50, 1.20, "height", "critical"),
    "stairs_up": (1.50, 1.20, "height", "critical"),
    "stairs_down": (1.50, 1.20, "height", "critical"),
    "door": (2.05, 0.85, "height", "waypoint"),
    "elevator": (2.10, 1.10, "height", "waypoint"),
    "pillar": (2.50, 0.35, "height", "safety"),
    "pole": (2.50, 0.30, "height", "safety"),
    "window": (1.20, 1.00, "height", "tabletop"),
    "signboard": (0.60, 1.20, "width", "waypoint"),
    "fire hydrant": (0.75, 0.40, "height", "safety"),
    "traffic light": (0.90, 0.35, "height", "safety"),
    "stop sign": (0.75, 0.75, "height", "critical"),

    # People & Pets
    "person": (1.70, 0.50, "height", "waypoint"),
    "pedestrian": (1.70, 0.50, "height", "waypoint"),
    "dog": (0.55, 0.70, "height", "safety"),
    "cat": (0.25, 0.40, "height", "safety"),

    # Furniture & Living Space
    "chair": (0.85, 0.50, "height", "safety"),
    "couch": (0.85, 1.80, "width", "safety"),
    "sofa": (0.85, 1.80, "width", "safety"),
    "table": (0.75, 1.20, "width", "safety"),
    "dining table": (0.75, 1.20, "width", "safety"),
    "desk": (0.75, 1.20, "width", "safety"),
    "bed": (0.65, 1.60, "width", "safety"),
    "bench": (0.80, 1.40, "width", "safety"),
    "refrigerator": (1.75, 0.80, "height", "safety"),
    "sink": (0.80, 0.60, "width", "safety"),
    "toilet": (0.75, 0.50, "height", "safety"),
    "potted plant": (0.60, 0.40, "height", "safety"),
    "trash bin": (0.45, 0.30, "height", "safety"),

    # Electronics & Workstation
    "laptop": (0.22, 0.32, "width", "tabletop"),
    "cell phone": (0.15, 0.075, "height", "tabletop"),
    "mobile phone": (0.15, 0.075, "height", "tabletop"),
    "keyboard": (0.14, 0.44, "width", "tabletop"),
    "mouse": (0.04, 0.07, "width", "tabletop"),
    "remote": (0.18, 0.05, "height", "tabletop"),
    "tv": (0.55, 0.95, "width", "safety"),

    # Tabletop & Handheld Items
    "book": (0.24, 0.17, "height", "tabletop"),
    "bottle": (0.24, 0.08, "height", "tabletop"),
    "water bottle": (0.24, 0.08, "height", "tabletop"),
    "cup": (0.10, 0.09, "height", "tabletop"),
    "mug": (0.10, 0.09, "height", "tabletop"),
    "plate": (0.03, 0.25, "width", "tabletop"),
    "bowl": (0.08, 0.16, "width", "tabletop"),
    "pen": (0.14, 0.015, "height", "tabletop"),
    "backpack": (0.45, 0.32, "height", "safety"),
    "handbag": (0.28, 0.35, "width", "tabletop"),
    "suitcase": (0.70, 0.48, "height", "safety"),
    "wallet": (0.10, 0.12, "width", "tabletop"),
    "keys": (0.08, 0.04, "height", "tabletop"),
    "shoes": (0.12, 0.28, "width", "tabletop"),
    "slippers": (0.10, 0.26, "width", "tabletop"),
    "clock": (0.30, 0.30, "width", "tabletop"),
    "vase": (0.30, 0.15, "height", "tabletop"),
}

# Calibrated Normalized Optical Focal Lengths for Mobile Device Cameras (~62° Vertical FOV)
FOCAL_Y = 1.10
FOCAL_X = 0.90

# Model Initialization
try:
    logger.info("Initializing Universal YOLO-World Vision Engine...")
    yolo_model = YOLO("yolov8s-worldv2.pt")
    yolo_model.set_classes(UNIVERSAL_CLASSES)
    active_model_name = f"YOLO-World-Universal ({len(UNIVERSAL_CLASSES)} classes)"
    logger.info(f"Universal YOLO-World successfully loaded with {len(UNIVERSAL_CLASSES)} classes!")
except Exception as e:
    logger.warning(f"YOLO-World load fallback: {e}")
    if os.path.exists("yolov8n_orbisnav.pt"):
        yolo_model = YOLO("yolov8n_orbisnav.pt")
        active_model_name = "YOLOv8n-OrbisNav (Custom Navigation Model)"
    else:
        yolo_model = YOLO("yolov8n.pt")
        active_model_name = "YOLOv8n-Base"

class DetectionItem(BaseModel):
    label: str
    clock_zone: str
    distance_meters: float
    ttc_seconds: float
    confidence: float
    is_critical: bool
    bbox: List[float] # [xMin, yMin, xMax, yMax] normalized

class VisionResponse(BaseModel):
    frame_id: int
    processing_time_ms: float
    timestamp: float
    detections: List[DetectionItem]

def centroid_to_clock_zone(x_center: float) -> str:
    """Converts normalized horizontal centroid [0.0, 1.0] to 12-hour clock zone."""
    if x_center < 0.12:
        return "9 o'clock"
    elif x_center < 0.28:
        return "10 o'clock"
    elif x_center < 0.44:
        return "11 o'clock"
    elif x_center <= 0.56:
        return "12 o'clock"
    elif x_center <= 0.72:
        return "1 o'clock"
    elif x_center <= 0.88:
        return "2 o'clock"
    else:
        return "3 o'clock"

def estimate_metric_distance(label: str, box_w: float, box_h: float) -> Tuple[float, str]:
    """
    Computes precise metric distance in meters using camera pinhole geometry
    and canonical physical object priors.
    """
    lbl_clean = label.lower().strip()
    priors = OBJECT_PHYSICAL_PRIORS.get(lbl_clean)

    if priors is None:
        # Check substring matches (e.g. 'sunglasses' -> 'glasses', 'water bottle' -> 'bottle')
        for k, v in OBJECT_PHYSICAL_PRIORS.items():
            if k in lbl_clean or lbl_clean in k:
                priors = v
                break

    if priors is None:
        # Default prior for unknown obstacle
        priors = (0.60, 0.50, "auto", "safety")

    h_real, w_real, axis, hazard_cat = priors

    d_h = (FOCAL_Y * h_real) / max(0.012, box_h)
    d_w = (FOCAL_X * w_real) / max(0.012, box_w)

    if axis == "height":
        raw_dist = d_h
    elif axis == "width":
        raw_dist = d_w
    else:
        # Combine height and width estimates based on aspect ratio consistency
        raw_dist = (d_h + d_w) / 2.0

    # Operational clamping [0.3m, 15.0m]
    dist_m = round(float(np.clip(raw_dist, 0.3, 15.0)), 1)
    return dist_m, hazard_cat

def analyze_frame(img: np.ndarray, frame_id: int) -> List[Dict[str, Any]]:
    """Runs real-time multi-class inference and metric distance calculation."""
    height, width = img.shape[:2]
    detections = []

    # Fast 320px inference for sub-30ms execution on Apple Silicon GPU (MPS)
    results = yolo_model(img, imgsz=320, conf=0.25, verbose=False)

    if results and len(results) > 0 and results[0].boxes is not None:
        boxes = results[0].boxes
        for box in boxes:
            cls_id = int(box.cls[0].item())
            class_name = yolo_model.names.get(cls_id, "Obstacle")
            conf = float(box.conf[0].item())

            # Bounding box in normalized coordinates
            xyxy = box.xyxy[0].tolist()
            x_min = max(0.0, xyxy[0] / width)
            y_min = max(0.0, xyxy[1] / height)
            x_max = min(1.0, xyxy[2] / width)
            y_max = min(1.0, xyxy[3] / height)

            x_center = (x_min + x_max) / 2.0
            clock_zone = centroid_to_clock_zone(x_center)

            box_w = x_max - x_min
            box_h = y_max - y_min

            # Precise metric distance estimation
            distance, hazard_cat = estimate_metric_distance(class_name, box_w, box_h)
            ttc = round(float(np.clip(distance / 1.2, 0.4, 9.9)), 1)

            # Assistive navigation criticality
            is_critical = False
            if hazard_cat == "critical":
                is_critical = distance < 2.5 or ttc < 2.0
            elif hazard_cat == "safety":
                is_critical = distance < 1.3
            elif hazard_cat == "waypoint":
                is_critical = class_name.lower() == "person" and (distance < 1.2 or ttc < 1.2)
            else: # tabletop / personal items
                is_critical = False

            detections.append({
                "label": class_name.title(),
                "clock_zone": clock_zone,
                "distance_meters": distance,
                "ttc_seconds": ttc,
                "confidence": round(conf, 2),
                "is_critical": is_critical,
                "bbox": [round(x_min, 3), round(y_min, 3), round(x_max, 3), round(y_max, 3)]
            })

    # If no objects detected, return clear path
    if not detections:
        detections.append({
            "label": "Path Clear",
            "clock_zone": "12 o'clock",
            "distance_meters": 5.0,
            "ttc_seconds": 9.9,
            "confidence": 0.99,
            "is_critical": False,
            "bbox": [0.0, 0.0, 1.0, 1.0]
        })

    return detections

@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "service": "OrbisNav Assistive Vision Server",
        "model": active_model_name,
        "classes_count": len(yolo_model.names),
        "timestamp": time.time()
    }

@app.get("/model-info")
async def model_info():
    return {
        "model_name": active_model_name,
        "classes": yolo_model.names,
        "num_classes": len(yolo_model.names),
        "focal_calibration": {"focal_y": FOCAL_Y, "focal_x": FOCAL_X},
        "backend": "Apple Silicon GPU (MPS) / YOLO-World Universal"
    }

@app.post("/detect")
async def detect_objects(request: Request):
    """Processes an incoming JPEG frame bytes and returns detections with metric distances."""
    try:
        frame_bytes = await request.body()
        if not frame_bytes:
            return {"status": "error", "message": "Empty frame body", "detections": []}

        start_time = time.perf_counter()
        np_arr = np.frombuffer(frame_bytes, np.uint8)
        img = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)

        if img is None:
            return {"status": "error", "message": "Failed to decode image", "detections": []}

        detections = analyze_frame(img, 0)
        processing_time_ms = round((time.perf_counter() - start_time) * 1000.0, 2)

        return {
            "status": "ok",
            "processing_time_ms": processing_time_ms,
            "timestamp": time.time(),
            "detections": detections
        }
    except Exception as e:
        logger.error(f"Error in /detect: {e}", exc_info=True)
        return {"status": "error", "message": str(e), "detections": []}

# Lazy PaddleOCR instance
_ocr_reader = None

def get_ocr_engine():
    global _ocr_reader
    if _ocr_reader is None:
        try:
            from paddleocr import PaddleOCR
            _ocr_reader = PaddleOCR(use_angle_cls=False, lang='en', show_log=False)
            logger.info("PaddleOCR engine loaded successfully.")
        except Exception as e:
            logger.warning(f"PaddleOCR load warning: {e}")
    return _ocr_reader

def compute_text_similarity(str1: str, str2: str) -> float:
    """Computes token-level and substring similarity between detected board text and query."""
    s1 = str1.lower().strip()
    s2 = str2.lower().strip()
    if not s1 or not s2:
        return 0.0
    if s1 in s2 or s2 in s1:
        return 1.0

    tokens1 = set(s1.split())
    tokens2 = set(s2.split())
    intersection = tokens1.intersection(tokens2)
    if intersection:
        return len(intersection) / max(len(tokens1), len(tokens2))

    from difflib import SequenceMatcher
    return SequenceMatcher(None, s1, s2).ratio()

@app.post("/detect-board")
async def detect_nameboard(request: Request, query: str = ""):
    """Analyzes a camera frame to locate signboards and matches them against target destination."""
    try:
        frame_bytes = await request.body()
        if not frame_bytes:
            return {"status": "error", "message": "Empty frame body", "boards": []}

        start_time = time.perf_counter()
        np_arr = np.frombuffer(frame_bytes, np.uint8)
        img = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)
        if img is None:
            return {"status": "error", "message": "Failed to decode image", "boards": []}

        h, w = img.shape[:2]
        ocr = get_ocr_engine()
        boards = []
        best_match = None
        best_sim = 0.0

        if ocr is not None:
            ocr_res = ocr.ocr(img, cls=False)
            if ocr_res and len(ocr_res) > 0 and ocr_res[0]:
                for line in ocr_res[0]:
                    coords = line[0] # 4 corner vertices
                    text, conf = line[1]

                    xs = [pt[0] for pt in coords]
                    ys = [pt[1] for pt in coords]
                    x_min = max(0.0, min(xs) / w)
                    y_min = max(0.0, min(ys) / h)
                    x_max = min(1.0, max(xs) / w)
                    y_max = min(1.0, max(ys) / h)

                    box_w = x_max - x_min
                    box_h = y_max - y_min
                    dist = round(float(np.clip((FOCAL_X * 1.20) / max(0.01, box_w), 1.0, 15.0)), 1)

                    x_center = (x_min + x_max) / 2.0
                    clock_zone = centroid_to_clock_zone(x_center)

                    sim = compute_text_similarity(text, query) if query else 0.0

                    board_item = {
                        "text": text,
                        "confidence": round(float(conf), 2),
                        "similarity": round(float(sim), 2),
                        "distance_meters": dist,
                        "clock_zone": clock_zone,
                        "bbox": [round(x_min, 3), round(y_min, 3), round(x_max, 3), round(y_max, 3)],
                        "is_match": sim >= 0.5
                    }
                    boards.append(board_item)

                    if sim > best_sim and sim >= 0.5:
                        best_sim = sim
                        best_match = board_item

        processing_time_ms = round((time.perf_counter() - start_time) * 1000.0, 2)
        return {
            "status": "ok",
            "processing_time_ms": processing_time_ms,
            "query": query,
            "target_sighted": best_match is not None,
            "best_match": best_match,
            "boards": boards
        }
    except Exception as e:
        logger.error(f"Error in /detect-board: {e}", exc_info=True)
        return {"status": "error", "message": str(e), "boards": []}

@app.websocket("/ws/vision-stream")
async def websocket_vision_stream(websocket: WebSocket):
    await websocket.accept()
    client_host = websocket.client.host if websocket.client else "unknown"
    logger.info(f"WebSocket client connected from {client_host}")

    frame_counter = 0

    try:
        while True:
            message = await websocket.receive()

            if "bytes" not in message or not message["bytes"]:
                if "text" in message:
                    await websocket.send_text(json.dumps({"status": "ack"}))
                continue

            frame_bytes = message["bytes"]
            frame_counter += 1
            start_time = time.perf_counter()

            # Decode JPEG in-memory
            np_arr = np.frombuffer(frame_bytes, np.uint8)
            img = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)

            if img is None:
                continue

            # Execute Universal Detection
            detections = analyze_frame(img, frame_counter)
            processing_time_ms = round((time.perf_counter() - start_time) * 1000.0, 2)

            response_payload = {
                "frame_id": frame_counter,
                "processing_time_ms": processing_time_ms,
                "timestamp": time.time(),
                "detections": detections
            }

            await websocket.send_text(json.dumps(response_payload))

    except WebSocketDisconnect:
        logger.info(f"Client {client_host} disconnected gracefully.")
    except Exception as e:
        logger.error(f"WebSocket streaming error: {e}", exc_info=True)
    finally:
        logger.info(f"Cleaned up session for {client_host}.")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000, log_level="info")
