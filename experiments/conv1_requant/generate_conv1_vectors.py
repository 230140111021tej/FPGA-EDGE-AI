from pathlib import Path
import json
import numpy as np

ROOT = Path(".")
PARAMS = ROOT / "outputs/rtl_params"
OUT = ROOT / "experiments/conv1_requant"

FILTERS = 16
KERNEL = 3
SIZE = 28
MULTIPLIER = 5863783
SHIFT = 31

weights = np.loadtxt(
    PARAMS / "conv1_weights_int8.txt", dtype=np.int32
).reshape(FILTERS, KERNEL, KERNEL)

biases = np.loadtxt(
    PARAMS / "conv1_bias_int32.txt", dtype=np.int64
)

# Deterministic test image covering the full unsigned 8-bit range.
rng = np.random.default_rng(20261015)
image = rng.integers(0, 256, size=(SIZE, SIZE), dtype=np.uint16)

accumulators = np.zeros((FILTERS, SIZE, SIZE), dtype=np.int64)
outputs = np.zeros((FILTERS, SIZE, SIZE), dtype=np.uint8)

for f in range(FILTERS):
    for y in range(SIZE):
        for x in range(SIZE):
            acc = int(biases[f])

            for ky in range(KERNEL):
                for kx in range(KERNEL):
                    iy = y + ky - 1
                    ix = x + kx - 1

                    # Same zero-padding as Conv2d(..., padding=1).
                    if 0 <= iy < SIZE and 0 <= ix < SIZE:
                        acc += (
                            int(image[iy, ix])
                            * int(weights[f, ky, kx])
                        )

            accumulators[f, y, x] = acc

            # ReLU followed by fixed-point requantization.
            positive = max(acc, 0)
            rounded = (
                positive * MULTIPLIER + (1 << (SHIFT - 1))
            ) >> SHIFT
            outputs[f, y, x] = min(rounded, 255)

np.savetxt(OUT / "image_pixels.txt", image.reshape(-1), fmt="%d")
np.savetxt(OUT / "expected_acc.txt", accumulators.reshape(-1), fmt="%d")
np.savetxt(OUT / "expected_q.txt", outputs.reshape(-1), fmt="%d")

summary = {
    "image_shape": [SIZE, SIZE],
    "filter_count": FILTERS,
    "positions_per_filter": SIZE * SIZE,
    "total_outputs": int(outputs.size),
    "accumulator_min": int(accumulators.min()),
    "accumulator_max": int(accumulators.max()),
    "negative_accumulators": int(np.sum(accumulators < 0)),
    "zero_outputs": int(np.sum(outputs == 0)),
    "saturated_outputs": int(np.sum(outputs == 255)),
    "test_seed": 20261015,
}

(OUT / "reference_summary.json").write_text(
    json.dumps(summary, indent=2) + "\n"
)
print(json.dumps(summary, indent=2))
print("PASS: Python reference vectors generated.")
