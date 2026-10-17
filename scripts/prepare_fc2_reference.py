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

fc1=read_ints(root/"fc1_reference_activations.txt")
weights=read_ints(params/"fc2_weights_int8.txt")
biases=read_ints(params/"fc2_bias_int32.txt")
if len(fc1)!=64 or len(weights)!=640 or len(biases)!=10:
    raise SystemExit(f"Bad FC2 dimensions: inputs={len(fc1)}, weights={len(weights)}, biases={len(biases)}")
write_hex(fc1,rom/"fc2_fc1_input_hex.mem",8)
write_hex(weights,rom/"fc2_weights_int8_hex.mem",8)
write_hex(biases,rom/"fc2_bias_int32_hex.mem",32)

layer=manifest["layers"]["classifier.3"]
# FC2 emits signed raw class scores; no requantization or ReLU.
x=np.asarray(fc1,dtype=np.int64)
w=np.asarray(weights,dtype=np.int64).reshape(10,64)
b=np.asarray(biases,dtype=np.int64)
scores=w@x+b
pred=int(np.argmax(scores))
(root/"fc2_reference_scores.txt").write_text("".join(f"{int(v)}\n" for v in scores))
(root/"fc2_reference_summary.txt").write_text(
 f"inputs=64\noutputs=10\nscore_min={int(scores.min())}\nscore_max={int(scores.max())}\npredicted_class={pred}\n")
print("FC2 reference generated.")
print("Inputs:",len(fc1),"Weights:",len(weights),"Outputs:",len(scores))
print("Score range:",int(scores.min()),"to",int(scores.max()))
print("Python predicted class:",pred)
