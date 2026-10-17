from pathlib import Path
import json
import numpy as np

root=Path(r"D:\FPGA_EdgeAI\cnn_baseline")
params=root/"outputs"/"rtl_params"
rom=root/"rom"
manifest=json.loads((params/"manifest.json").read_text())

def read_ints(path):
    return [int(v.strip()) for v in path.read_text().splitlines() if v.strip()]

def write_hex(values,path,bits):
    mask=(1<<bits)-1
    path.write_text("".join(f"{int(v)&mask:0{bits//4}X}\n" for v in values))

pool=read_ints(root/"conv2_reference_pool2.txt")
weights=read_ints(params/"fc1_weights_int8.txt")
biases=read_ints(params/"fc1_bias_int32.txt")
if len(pool)!=1568 or len(weights)!=100352 or len(biases)!=64:
    raise SystemExit(f"Bad FC1 dimensions: pool={len(pool)}, weights={len(weights)}, biases={len(biases)}")

write_hex(pool,rom/"fc1_pool2_input_hex.mem",8)
write_hex(weights,rom/"fc1_weights_int8_hex.mem",8)
write_hex(biases,rom/"fc1_bias_int32_hex.mem",32)

layer=manifest["layers"]["classifier.1"]
mult=int(layer["requant_multiplier"])
shift=int(layer["requant_shift"])
# Python model follows the declared exported fixed-point contract:
# signed accumulator * Q31 multiplier, add 2^30, arithmetic shift 31,
# ReLU, then clamp to uint8.
x=np.asarray(pool,dtype=np.int64)
w=np.asarray(weights,dtype=np.int64).reshape(64,1568)
b=np.asarray(biases,dtype=np.int64)
acc=w@x+b
scaled=(acc*mult+(1<<(shift-1))) >> shift
act=np.clip(np.maximum(scaled,0),0,255).astype(np.int64)
(root/"fc1_reference_acc.txt").write_text("".join(f"{int(v)}\n" for v in acc))
(root/"fc1_reference_activations.txt").write_text("".join(f"{int(v)}\n" for v in act))
(root/"fc1_reference_summary.txt").write_text(
    f"inputs=1568\noutputs=64\nmultiplier={mult}\nshift={shift}\n"
    f"acc_min={int(acc.min())}\nacc_max={int(acc.max())}\n"
    f"activation_min={int(act.min())}\nactivation_max={int(act.max())}\n")
print("FC1 reference generated.")
print("Input values:",len(pool),"Weights:",len(weights),"Outputs:",len(acc))
print("Accumulator range:",int(acc.min()),"to",int(acc.max()))
print("Activation range:",int(act.min()),"to",int(act.max()))
print("Q31 multiplier:",mult,"shift:",shift)
