import json
from pathlib import Path
import numpy as np

root = Path(".")
out = root / "sim/requantize"
manifest = json.loads(
    (root / "outputs/rtl_params/manifest.json").read_text()
)

layers = [
    ("features.0", "conv1"),
    ("features.3", "conv2"),
    ("classifier.1", "fc1"),
]

SHIFT = 31
DEN = 1 << SHIFT
rng = np.random.default_rng(20261015)

def multiplier(layer):
    return manifest["layers"][layer]["requant_multiplier"]

multipliers = [multiplier(layer) for layer, _ in layers]
print("Using multipliers:", multipliers)

# Include boundary values, practical accumulator ranges, and random cases.
values = {0, 1, 2, 3, 100, 255, 256, 1000, 100000, 370804,
          2**31 - 1, 2**32 - 1}
values.update(int(x) for x in rng.integers(0, 500001, size=2000))

# Include inputs close to output rounding transitions for each multiplier.
for m in multipliers:
    for k in range(256):
        threshold = ((2 * k + 1) * DEN) // (2 * m)
        for x in (threshold - 1, threshold, threshold + 1):
            if 0 <= x <= 2**32 - 1:
                values.add(x)

values = sorted(values)

def ref(x, m):
    y = (x * m + (1 << (SHIFT - 1))) >> SHIFT
    return min(255, max(0, y))

vectors = out / "requant_vectors.txt"
with vectors.open("w") as f:
    for x in values:
        expected = [ref(x, m) for m in multipliers]
        f.write(f"{x} {expected[0]} {expected[1]} {expected[2]}\n")

print(f"Wrote {len(values)} test vectors to {vectors}")
