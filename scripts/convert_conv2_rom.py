from pathlib import Path
root=Path(r"D:\FPGA_EdgeAI\cnn_baseline")
params=root/"outputs"/"rtl_params"
rom=root/"rom"
def dec(path): return [int(x.strip()) for x in path.read_text().splitlines() if x.strip()]
def write(vals,path,bits):
    mask=(1<<bits)-1
    path.write_text("".join(f"{v & mask:0{bits//4}X}\n" for v in vals))
write(dec(params/"conv2_weights_int8.txt"),rom/"conv2_weights_int8_hex.mem",8)
write(dec(params/"conv2_bias_int32.txt"),rom/"conv2_bias_int32_hex.mem",32)
print("Exported Conv2 weights/biases to hex ROMs.")
