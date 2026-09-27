"""
OrbisNav YOLOv8 Real-World Dataset TFLite Exporter.
Exports YOLOv8-Nano trained on real-world datasets directly into TensorFlow Lite (.tflite) format
for 100% standalone, on-device mobile execution (zero Mac / server dependency).
"""

import os
import sys
import shutil
from ultralytics import YOLO

def export_model():
    root_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    assets_dir = os.path.join(root_dir, "assets", "models")
    os.makedirs(assets_dir, exist_ok=True)

    # Use YOLOv8n (real-world COCO dataset with 80 classes)
    model_path = os.path.join(root_dir, "yolov8n.pt")
    if not os.path.exists(model_path):
        model_path = "yolov8n.pt"

    print(f"[OrbisNav Export] Loading YOLOv8 model from {model_path}...")
    model = YOLO(model_path)

    # Export to TFLite format
    print("[OrbisNav Export] Exporting to TensorFlow Lite (TFLite) format (imgsz=320 for ultra-fast mobile inference)...")
    exported_path = model.export(format="tflite", imgsz=320, int8=False)
    print(f"[OrbisNav Export] Export output: {exported_path}")

    # Copy to assets/models/yolov8n_float32.tflite
    target_tflite = os.path.join(assets_dir, "yolov8n.tflite")
    if os.path.exists(exported_path):
        if os.path.isdir(exported_path):
            # Sometimes ultralytics exports a folder with *_float32.tflite
            for f in os.listdir(exported_path):
                if f.endswith(".tflite"):
                    src = os.path.join(exported_path, f)
                    shutil.copyfile(src, target_tflite)
                    print(f"[OrbisNav Export] Copied {src} -> {target_tflite}")
                    break
        else:
            shutil.copyfile(exported_path, target_tflite)
            print(f"[OrbisNav Export] Copied {exported_path} -> {target_tflite}")

    # Export class names to labels.txt
    labels_path = os.path.join(assets_dir, "labels.txt")
    with open(labels_path, "w") as f:
        for idx in range(len(model.names)):
            f.write(f"{model.names[idx]}\n")
    print(f"[OrbisNav Export] Saved {len(model.names)} labels to {labels_path}")

if __name__ == "__main__":
    export_model()
