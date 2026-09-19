"""
OrbisNav YOLOv8 Custom Object Detection Training Script.
Fine-tunes YOLOv8-Nano on the custom assistive spatial perception dataset.
Uses Apple Silicon Metal Performance Shaders (MPS) for high-speed GPU acceleration.
"""

import os
import sys
import torch
from ultralytics import YOLO

def main():
    base_dir = os.path.dirname(os.path.abspath(__file__))
    root_dir = os.path.dirname(base_dir)
    yaml_path = os.path.join(base_dir, "dataset", "data.yaml")

    if not os.path.exists(yaml_path):
        print(f"Dataset configuration not found at {yaml_path}. Generating dataset first...")
        from dataset_builder import build_dataset
        yaml_path = build_dataset(num_train=350, num_val=75)

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

    print("Starting fine-tuning on OrbisNav Navigation Dataset...")
    # Train for 15 epochs (fast & accurate fine-tuning on custom dataset)
    results = model.train(
        data=yaml_path,
        epochs=15,
        imgsz=640,
        batch=16,
        device=device,
        workers=2,
        project=os.path.join(base_dir, "runs"),
        name="orbisnav_detector",
        exist_ok=True,
        verbose=True,
        mosaic=1.0,
        mixup=0.1,
        degrees=10.0,
        translate=0.1,
        scale=0.2,
        flipud=0.0,
        fliplr=0.5,
        save=True,
        save_period=-1,
        val=True
    )

    best_weights = os.path.join(base_dir, "runs", "orbisnav_detector", "weights", "best.pt")
    target_weights = os.path.join(root_dir, "yolov8n_orbisnav.pt")

    if os.path.exists(best_weights):
        import shutil
        shutil.copyfile(best_weights, target_weights)
        print(f"\n==========================================")
        print(f"SUCCESS: Trained weights saved to: {target_weights}")
        print(f"==========================================\n")
    else:
        # Fallback to last weights if best.pt wasn't populated
        last_weights = os.path.join(base_dir, "runs", "orbisnav_detector", "weights", "last.pt")
        if os.path.exists(last_weights):
            import shutil
            shutil.copyfile(last_weights, target_weights)
            print(f"Saved last weights to: {target_weights}")

    # Validate model
    print("Running final validation benchmark...")
    val_model = YOLO(target_weights)
    val_results = val_model.val(data=yaml_path, device=device)
    
    print("\nTraining & Validation Benchmark Summary:")
    print(f"Classes: {val_model.names}")
    print(f"mAP50: {val_results.box.map50:.4f}")
    print(f"mAP50-95: {val_results.box.map:.4f}")

    # Export to ONNX for embedded / zero-heap runtime compatibility
    try:
        onnx_path = val_model.export(format="onnx", imgsz=640, dynamic=True)
        print(f"Exported ONNX model to: {onnx_path}")
    except Exception as e:
        print(f"ONNX export note: {e}")

if __name__ == "__main__":
    main()
