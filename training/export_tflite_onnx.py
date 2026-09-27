"""
OrbisNav YOLOv8 ONNX to TFLite Robust Converter.
Converts YOLOv8 ONNX model into TFLite format using onnx2tf for on-device mobile execution.
"""

import os
import sys
import shutil
import subprocess
import numpy as np
from ultralytics import YOLO

def export_onnx_and_tflite():
    root_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    assets_dir = os.path.join(root_dir, "assets", "models")
    os.makedirs(assets_dir, exist_ok=True)

    # 1. Load YOLOv8n (80 COCO real-world dataset classes)
    model_path = os.path.join(root_dir, "yolov8n.pt")
    if not os.path.exists(model_path):
        model_path = "yolov8n.pt"

    print(f"[OrbisNav Export] Loading YOLOv8 model from {model_path}...")
    model = YOLO(model_path)

    # 2. Export to ONNX (Static input shape [1, 3, 320, 320])
    print("[OrbisNav Export] Exporting to ONNX (320x320)...")
    onnx_path = model.export(format="onnx", imgsz=320, dynamic=False, simplify=True)
    print(f"[OrbisNav Export] ONNX output: {onnx_path}")

    # 3. Convert ONNX to TFLite via onnx2tf
    output_dir = os.path.join(root_dir, "training", "saved_model")
    os.makedirs(output_dir, exist_ok=True)

    print("[OrbisNav Export] Converting ONNX -> TFLite via onnx2tf...")
    # Generate dummy input to bypass test data download
    dummy_npy = os.path.join(root_dir, "training", "dummy_input.npy")
    np.save(dummy_npy, np.zeros((1, 3, 320, 320), dtype=np.float32))

    try:
        cmd = [
            sys.executable, "-m", "onnx2tf",
            "-i", onnx_path,
            "-o", output_dir,
            "-cotof",
            "-cind", "images", dummy_npy
        ]
        subprocess.run(cmd, check=True)
    except Exception as e:
        print(f"[OrbisNav Export] onnx2tf subprocess error: {e}")

    # 4. Copy generated tflite model to assets/models/yolov8n.tflite
    target_tflite = os.path.join(assets_dir, "yolov8n.tflite")
    
    # Check candidates
    candidates = [
        os.path.join(output_dir, "yolov8n_float32.tflite"),
        os.path.join(output_dir, "model_float32.tflite"),
    ]
    for root, dirs, files in os.walk(output_dir):
        for f in files:
            if f.endswith(".tflite"):
                candidates.append(os.path.join(root, f))

    found = False
    for cand in candidates:
        if os.path.exists(cand):
            shutil.copyfile(cand, target_tflite)
            print(f"[OrbisNav Export] SUCCESS: Saved on-device TFLite model to {target_tflite} ({os.path.getsize(target_tflite)} bytes)")
            found = True
            break

    if not found:
        print("[OrbisNav Export] Note: searching for any generated .tflite files in root...")
        for root, dirs, files in os.walk(root_dir):
            if "assets" in root: continue
            for f in files:
                if f.endswith(".tflite"):
                    src = os.path.join(root, f)
                    shutil.copyfile(src, target_tflite)
                    print(f"[OrbisNav Export] Copied {src} -> {target_tflite}")
                    found = True
                    break
            if found: break

    # 5. Export labels.txt
    labels_path = os.path.join(assets_dir, "labels.txt")
    with open(labels_path, "w") as f:
        for idx in range(len(model.names)):
            f.write(f"{model.names[idx]}\n")
    print(f"[OrbisNav Export] Saved {len(model.names)} labels to {labels_path}")

if __name__ == "__main__":
    export_onnx_and_tflite()
