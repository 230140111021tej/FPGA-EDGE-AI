import json
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn

ROOT = Path(".")
OUT = ROOT / "outputs" / "rtl_params"
OUT.mkdir(parents=True, exist_ok=True)

CHECKPOINT = ROOT / "outputs" / "best_mnist_cnn.pth"

# Match the scales and symmetric INT8 weight quantization used
# in integer_cnn_reference.py.
WEIGHT_SCALES = {
    "features.0": 0.0059380850454015055,
    "features.3": 0.004132752812753512,
    "classifier.1": 0.0028914492430649405,
    "classifier.3": 0.00258087126288827,
}

# Activation scales from the preserved 10,000-image reference.
ACTIVATION_SCALES = {
    "input": 1.0 / 255.0,
    "pool1": 2.1746950149536133 / 255.0,
    "pool2": 6.421261310577393 / 255.0,
    "fc1_relu": 27.940956115722656 / 255.0,
}

SHIFT = 31

LAYERS = [
    ("features.0", "conv1"),
    ("features.3", "conv2"),
    ("classifier.1", "fc1"),
    ("classifier.3", "fc2"),
]

checkpoint = torch.load(
    CHECKPOINT, map_location="cpu", weights_only=True
)
if not isinstance(checkpoint, dict):
    raise TypeError("Expected a state-dict checkpoint.")

manifest = {
    "format": "signed INT8 weights, signed INT32 biases",
    "weight_quantization": "symmetric per-layer, round-to-nearest-even, clamp [-127,127]",
    "bias_quantization": "round-to-nearest-even in input_scale * weight_scale units",
    "requantization": {
        "shift": SHIFT,
        "rounding": "nearest, halfway upward for nonnegative values",
        "saturation": "unsigned 8-bit [0,255]",
    },
    "activation_scales": ACTIVATION_SCALES,
    "layers": {},
}

for name, short in LAYERS:
    w = checkpoint[f"{name}.weight"].detach().cpu().numpy().astype(np.float64)
    b = checkpoint[f"{name}.bias"].detach().cpu().numpy().astype(np.float64)

    actual_scale = float(np.max(np.abs(w))) / 127.0
    if actual_scale == 0:
        actual_scale = 1.0

    expected_scale = WEIGHT_SCALES[name]
    if not np.isclose(actual_scale, expected_scale, rtol=1e-6, atol=1e-12):
        raise ValueError(
            f"{name}: checkpoint-derived weight scale {actual_scale} "
            f"does not match configured scale {expected_scale}"
        )

    wq = np.clip(np.rint(w / actual_scale), -127, 127).astype(np.int8)

    if name == "features.0":
        input_scale = ACTIVATION_SCALES["input"]
        output_scale = ACTIVATION_SCALES["pool1"]
    elif name == "features.3":
        input_scale = ACTIVATION_SCALES["pool1"]
        output_scale = ACTIVATION_SCALES["pool2"]
    elif name == "classifier.1":
        input_scale = ACTIVATION_SCALES["pool2"]
        output_scale = ACTIVATION_SCALES["fc1_relu"]
    else:
        input_scale = ACTIVATION_SCALES["fc1_relu"]
        output_scale = None

    bias_scale = input_scale * actual_scale
    bq64 = np.rint(b / bias_scale).astype(np.int64)

    if np.any(bq64 < np.iinfo(np.int32).min) or np.any(
        bq64 > np.iinfo(np.int32).max
    ):
        raise OverflowError(f"{name}: bias does not fit signed INT32")
    bq = bq64.astype(np.int32)

    # Store flattened, row-major values for simple RTL/testbench loading.
    np.savetxt(OUT / f"{short}_weights_int8.txt",
               wq.reshape(-1), fmt="%d")
    np.savetxt(OUT / f"{short}_bias_int32.txt",
               bq.reshape(-1), fmt="%d")

    ratio = None if output_scale is None else (
        input_scale * actual_scale / output_scale
    )
    multiplier = None if ratio is None else int(np.rint(ratio * (1 << SHIFT)))

    manifest["layers"][name] = {
        "rtl_name": short,
        "weight_shape": list(w.shape),
        "weight_count": int(wq.size),
        "bias_count": int(bq.size),
        "weight_scale": actual_scale,
        "bias_scale": bias_scale,
        "input_scale": input_scale,
        "output_scale": output_scale,
        "requant_ratio": ratio,
        "requant_multiplier": multiplier,
        "requant_shift": None if ratio is None else SHIFT,
        "weight_file": f"{short}_weights_int8.txt",
        "bias_file": f"{short}_bias_int32.txt",
        "weight_min": int(wq.min()),
        "weight_max": int(wq.max()),
        "bias_min": int(bq.min()),
        "bias_max": int(bq.max()),
    }

(OUT / "manifest.json").write_text(json.dumps(manifest, indent=2))
print(f"Exported parameters to: {OUT}")
for name, info in manifest["layers"].items():
    print(
        f"{name}: weights={info['weight_count']}, "
        f"biases={info['bias_count']}, "
        f"bias range=[{info['bias_min']}, {info['bias_max']}]"
    )
print("Manifest:", OUT / "manifest.json")
