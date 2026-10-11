"""
OrbisNav YOLOv8 Custom Object Detection Training Script (Max Accuracy Edition).
Fine-tunes YOLOv8-Nano on the comprehensive assistive spatial perception dataset.
Includes trees, obstacles, vehicles, structural hazards, and pedestrians.
Uses Apple Silicon Metal Performance Shaders (MPS) for high-speed GPU acceleration.
"""

import os
import sys
import shutil
import torch
from ultralytics import YOLO

def main():
    base_dir = os.path.dirname(os.path.abspath(__file__))
    root_dir = os.path.dirname(base_dir)
    yaml_path = os.path.join(base_dir, "dataset", "data.yaml")

    # Generate or refresh dataset configuration (1,200 train, 240 val)
    print("Building expanded procedural dataset for maximum accuracy (1,200 train / 240 val)...")
    from dataset_builder import build_dataset
    yaml_path = build_dataset(num_train=1200, num_val=240)

    # Determine optimal compute device (MPS for Mac M-series, or CPU)
    if torch.backends.mps.is_available():
        device = "mps"
        print("Using Apple Silicon GPU Acceleration (MPS)")
    else:
        device = "cpu"
        print("MPS not available; using CPU")

    pretrained_model = os.path.join(root_dir, "yolov8n.pt")
    if not os.path.exists(pretrained_model):
        pretrained_model = "yolov8n.pt"

    print(f"Loading base weights from: {pretrained_model}")
    model = YOLO(pretrained_model)

    print("Starting high-accuracy training on OrbisNav Assistive Dataset...")
    # Train for 30 epochs with cosine LR schedule, label smoothing, and strong regularizers
    results = model.train(
        data=yaml_path,
        epochs=50,
        imgsz=640,
        batch=16,
        device=device,
        workers=2,
        project=os.path.join(base_dir, "runs"),
        name="orbisnav_detector_max",
        exist_ok=True,
        verbose=True,
        cos_lr=True,
        lr0=0.01,
        lrf=0.01,
        warmup_epochs=3.0,
        mosaic=1.0,
        mixup=0.15,
        label_smoothing=0.05,
        hsv_h=0.015,
        hsv_s=0.7,
        hsv_v=0.4,
        degrees=10.0,
        translate=0.10,
        scale=0.30,
        fliplr=0.5,
        save=True,
        save_period=-1,
        val=True
    )

    best_weights = os.path.join(base_dir, "runs", "orbisnav_detector_max", "weights", "best.pt")
    target_weights = os.path.join(root_dir, "yolov8n_orbisnav.pt")

    if os.path.exists(best_weights):
        shutil.copyfile(best_weights, target_weights)
        print(f"\n==========================================")
        print(f"SUCCESS: Trained weights saved to: {target_weights}")
        print(f"==========================================\n")
    else:
        last_weights = os.path.join(base_dir, "runs", "orbisnav_detector_max", "weights", "last.pt")
        if os.path.exists(last_weights):
            shutil.copyfile(last_weights, target_weights)
            print(f"Saved last weights to: {target_weights}")

    # Validate model
    print("Running final validation benchmark...")
    val_model = YOLO(target_weights)
    val_results = val_model.val(data=yaml_path, device=device)
    
    print("\nTraining & Validation Benchmark Summary:")
    print(f"Classes ({len(val_model.names)}): {val_model.names}")
    print(f"mAP50: {val_results.box.map50:.4f}")
    print(f"mAP50-95: {val_results.box.map:.4f}")

    # Export to ONNX for zero-heap runtime compatibility
    try:
        onnx_path = val_model.export(format="onnx", imgsz=640, dynamic=True)
        if os.path.exists(onnx_path):
            root_onnx = os.path.join(root_dir, "yolov8n_orbisnav.onnx")
            shutil.copyfile(onnx_path, root_onnx)
            print(f"Exported and copied ONNX model to: {root_onnx}")
    except Exception as e:
        print(f"ONNX export note: {e}")

if __name__ == "__main__":
    main()
