from pathlib import Path

root = Path(r"D:\FPGA_EdgeAI\cnn_baseline")
rom = root / "rom"

def load_hex(path, bits, signed=False):
    vals = []
    for line in path.read_text().splitlines():
        s = line.strip()
        if not s:
            continue
        v = int(s, 16)
        if signed and v & (1 << (bits - 1)):
            v -= 1 << bits
        vals.append(v)
    return vals

image = load_hex(rom / "conv1_image_u8_hex.mem", 8, False)
weights = load_hex(rom / "conv1_weights_int8_hex.mem", 8, True)
biases = load_hex(rom / "conv1_bias_int32_hex.mem", 32, True)
if len(image) != 784 or len(weights) != 144 or len(biases) != 16:
    raise SystemExit(f"Bad ROM lengths: image={len(image)} weights={len(weights)} biases={len(biases)}")

rtl_path = root / "conv1_rtl_outputs.txt"
if not rtl_path.exists():
    raise SystemExit(f"Missing RTL output file: {rtl_path}")
rtl = []
for line in rtl_path.read_text().splitlines():
    parts = line.split()
    if len(parts) == 3:
        rtl.append(tuple(map(int, parts)))
if len(rtl) != 10816:
    raise SystemExit(f"Expected 10816 RTL rows, found {len(rtl)}")

errors = 0
max_abs_diff = 0
first_errors = []
for filt in range(16):
    for pos in range(676):
        row, col = divmod(pos, 26)
        acc = biases[filt]
        for ky in range(3):
            for kx in range(3):
                pix = image[(row + ky) * 28 + col + kx]
                wt = weights[filt * 9 + ky * 3 + kx]
                acc += pix * wt
        # RTL accumulator is signed 20-bit and bias is truncated to 20 bits on load.
        acc20 = acc & ((1 << 20) - 1)
        if acc20 & (1 << 19):
            acc20 -= 1 << 20

        addr = filt * 676 + pos
        got_addr, got_filter, got_acc = rtl[addr]
        diff = abs(got_acc - acc20)
        max_abs_diff = max(max_abs_diff, diff)
        if got_addr != addr or got_filter != filt or got_acc != acc20:
            errors += 1
            if len(first_errors) < 10:
                first_errors.append((addr, filt, acc20, got_addr, got_filter, got_acc))

print(f"RTL rows: {len(rtl)}")
print(f"Compared outputs: 10816")
print(f"Mismatches: {errors}")
print(f"Maximum absolute difference: {max_abs_diff}")
if first_errors:
    print("First mismatches (expected_addr, expected_filter, expected_acc, rtl_addr, rtl_filter, rtl_acc):")
    for item in first_errors:
        print(item)
if errors:
    raise SystemExit(1)
print("PASS: all 10,816 accumulator values match the independent Python reference.")
