from pathlib import Path
import json
import numpy as np

root = Path(r"D:\FPGA_EdgeAI\cnn_baseline")
rom = root / "rom"
params = root / "outputs" / "rtl_params"
manifest = json.loads((params / "manifest.json").read_text())

def load_hex(path, bits, signed=False):
    vals=[]
    for line in path.read_text().splitlines():
        s=line.strip()
        if not s: continue
        v=int(s,16)
        if signed and v & (1<<(bits-1)): v-=1<<bits
        vals.append(v)
    return np.asarray(vals, dtype=np.int64)

def load_decimal(path):
    return np.asarray([int(x.strip()) for x in path.read_text().splitlines() if x.strip()], dtype=np.int64)

image = load_hex(rom/"conv1_image_u8_hex.mem",8).reshape(1,28,28)
w1 = load_decimal(params/"conv1_weights_int8.txt").reshape(16,1,3,3)
b1 = load_decimal(params/"conv1_bias_int32.txt")
w2 = load_decimal(params/"conv2_weights_int8.txt").reshape(32,16,3,3)
b2 = load_decimal(params/"conv2_bias_int32.txt")
if image.shape != (1,28,28) or w1.shape != (16,1,3,3) or len(b1)!=16 or w2.shape!=(32,16,3,3) or len(b2)!=32:
    raise SystemExit("Unexpected image/parameter shape.")

# Exact Conv1 integer reference using same-padding, then Q31 requantization and ReLU.
m1 = int(manifest["layers"]["features.0"]["requant_multiplier"])
shift1 = int(manifest["layers"]["features.0"]["requant_shift"])
x1 = np.zeros((16,28,28),dtype=np.uint8)
acc1 = np.zeros((16,28,28),dtype=np.int64)
pad1=np.pad(image[0],((1,1),(1,1)))
for f in range(16):
    for y in range(28):
        for x in range(28):
            acc=int(b1[f])
            for ky in range(3):
                for kx in range(3):
                    acc += int(pad1[y+ky,x+kx])*int(w1[f,0,ky,kx])
            acc1[f,y,x]=acc
            q=max(0,min(255,(max(0,acc)*m1+(1<<(shift1-1)))>>shift1))
            x1[f,y,x]=q

# 2x2 max pool, stride 2.
pool1=x1.reshape(16,14,2,14,2).max(axis=(2,4))
(root/"rom"/"conv2_pool1_input_hex.mem").write_text("".join(f"{int(v):02X}\n" for v in pool1.reshape(-1)))
# Conv2: input is pool1 (16x14x14), same padding, 32 filters.
m2=int(manifest["layers"]["features.3"]["requant_multiplier"])
shift2=int(manifest["layers"]["features.3"]["requant_shift"])
acc2=np.zeros((32,14,14),dtype=np.int64)
x2=np.zeros((32,14,14),dtype=np.uint8)
for f in range(32):
    for y in range(14):
        for x in range(14):
            acc=int(b2[f])
            for c in range(16):
                for ky in range(3):
                    iy=y+ky-1
                    for kx in range(3):
                        ix=x+kx-1
                        if 0<=iy<14 and 0<=ix<14:
                            acc += int(pool1[c,iy,ix])*int(w2[f,c,ky,kx])
            acc2[f,y,x]=acc
            q=max(0,min(255,(max(0,acc)*m2+(1<<(shift2-1)))>>shift2))
            x2[f,y,x]=q

pool2=x2.reshape(32,7,2,7,2).max(axis=(2,4))

# Save reference arrays in filter/channel-major row-major order for RTL compare.
(root/"conv2_reference_acc.txt").write_text("".join(f"{int(v)}\n" for v in acc2.reshape(-1)))
(root/"conv2_reference_activations.txt").write_text("".join(f"{int(v)}\n" for v in x2.reshape(-1)))
(root/"conv2_reference_pool2.txt").write_text("".join(f"{int(v)}\n" for v in pool2.reshape(-1)))
(root/"conv2_reference_summary.txt").write_text(
    f"image_label={((root/'rom'/'conv1_image_info.txt').read_text().split('label=')[1].splitlines()[0] if (root/'rom'/'conv1_image_info.txt').exists() else 'unknown')}\n"
    f"pool1_shape={pool1.shape}\nconv2_acc_shape={acc2.shape}\nconv2_activation_shape={x2.shape}\npool2_shape={pool2.shape}\n"
    f"conv2_acc_min={int(acc2.min())}\nconv2_acc_max={int(acc2.max())}\n"
    f"conv2_activation_min={int(x2.min())}\nconv2_activation_max={int(x2.max())}\n"
    f"pool2_min={int(pool2.min())}\npool2_max={int(pool2.max())}\n"
)
print("PYTHON REFERENCE GENERATED")
print("Conv1 same-pad output: 16 x 28 x 28")
print("Pool1 output:          16 x 14 x 14")
print("Conv2 accumulators:    32 x 14 x 14 =", acc2.size)
print("Conv2 activations:     32 x 14 x 14 =", x2.size)
print("Pool2 output:          32 x 7 x 7 =", pool2.size)
print("Conv2 accumulator range:", int(acc2.min()), "to", int(acc2.max()))
print("Conv2 activation range:", int(x2.min()), "to", int(x2.max()))
print("Reference files: conv2_reference_acc.txt, conv2_reference_activations.txt, conv2_reference_pool2.txt")

