"""
Direct Python Conversion for YOLOv8 ONNX to TFLite with Mocked Test Data.
"""

import os
import sys
import shutil
import numpy as np

import onnx2tf
import onnx2tf.onnx2tf as otf
import onnx2tf.utils.common_functions as cfuncs

# Mock download_test_image_data in all modules
def mocked_test_data(*args, **kwargs):
    return np.zeros((1, 320, 320, 3), dtype=np.float32)

cfuncs.download_test_image_data = mocked_test_data
otf.download_test_image_data = mocked_test_data

def main():
    root_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    onnx_path = os.path.join(root_dir, "yolov8n.onnx")
    output_dir = os.path.join(root_dir, "training", "saved_model")
    assets_dir = os.path.join(root_dir, "assets", "models")
    os.makedirs(assets_dir, exist_ok=True)
    os.makedirs(output_dir, exist_ok=True)

    print(f"Converting {onnx_path} to TFLite via onnx2tf...")
    otf.convert(
        input_onnx_file_path=onnx_path,
        output_folder_path=output_dir,
        check_onnx_tf_outputs_elementwise_close_full=False,
        output_integer_quantized_tflite=False,
        non_verbose=True
    )

    target_tflite = os.path.join(assets_dir, "yolov8n.tflite")
    for root, dirs, files in os.walk(output_dir):
        for f in files:
            if f.endswith(".tflite"):
                src = os.path.join(root, f)
                shutil.copyfile(src, target_tflite)
                print(f"SUCCESS: Exported and copied TFLite model -> {target_tflite} ({os.path.getsize(target_tflite)} bytes)")
                return

    print("Checking root directory for tflite files...")
    for root, dirs, files in os.walk(root_dir):
        if "assets" in root: continue
        for f in files:
            if f.endswith(".tflite"):
                src = os.path.join(root, f)
                shutil.copyfile(src, target_tflite)
                print(f"Copied {src} -> {target_tflite}")
                return

if __name__ == "__main__":
    main()
