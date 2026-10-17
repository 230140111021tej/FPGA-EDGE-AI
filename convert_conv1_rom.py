
from pathlib import Path

ROOT = Path(r"D:\FPGA_EdgeAI\cnn_baseline\rom")

def convert_signed_decimal_to_hex(src_name, dst_name, bits, expected_count):
    src = ROOT / src_name
    dst = ROOT / dst_name

    values = [int(line.strip()) for line in src.read_text().splitlines()
              if line.strip()]

    if len(values) != expected_count:
        raise ValueError(
            f"{src_name}: expected {expected_count} values, got {len(values)}"
        )

    lo = -(1 << (bits - 1))
    hi = (1 << (bits - 1)) - 1

    if any(v < lo or v > hi for v in values):
        raise ValueError(f"{src_name}: value outside signed {bits}-bit range")

    digits = bits // 4
    dst.write_text(
        "".join(f"{v & ((1 << bits) - 1):0{digits}X}\n"
                for v in values)
    )
    print(f"Created {dst.name}: {len(values)} values, {bits}-bit")

convert_signed_decimal_to_hex(
    "conv1_weights_int8.mem",
    "conv1_weights_int8_hex.mem",
    8,
    144,
)

convert_signed_decimal_to_hex(
    "conv1_bias_int32.mem",
    "conv1_bias_int32_hex.mem",
    32,
    16,
)
