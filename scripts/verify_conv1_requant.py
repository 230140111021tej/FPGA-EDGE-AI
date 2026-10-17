from pathlib import Path
root=Path(r"D:\FPGA_EdgeAI\cnn_baseline")
rom=root/"rom"

def load_hex(path,bits,signed=False):
    vals=[]
    for line in path.read_text().splitlines():
        s=line.strip()
        if not s: continue
        v=int(s,16)
        if signed and v & (1<<(bits-1)): v-=1<<bits
        vals.append(v)
    return vals

image=load_hex(rom/"conv1_image_u8_hex.mem",8)
weights=load_hex(rom/"conv1_weights_int8_hex.mem",8,True)
biases=load_hex(rom/"conv1_bias_int32_hex.mem",32,True)
rtl_acc=[tuple(map(int,x.split())) for x in (root/"conv1_rtl_outputs.txt").read_text().splitlines() if len(x.split())==3]
rtl_act=[tuple(map(int,x.split())) for x in (root/"conv1_rtl_activations.txt").read_text().splitlines() if len(x.split())==2]
if (len(image),len(weights),len(biases))!=(784,144,16): raise SystemExit("ROM length mismatch")
if len(rtl_acc)!=12544 or len(rtl_act)!=12544:
    raise SystemExit(f"Expected 12544 outputs; got accum={len(rtl_acc)}, act={len(rtl_act)}")

MULT=5863783; ROUND=1<<30
ae=qe=0; firsta=[]; firstq=[]
for f in range(16):
  for pos in range(784):
    y,x=divmod(pos,28)
    acc=biases[f]
    for ky in range(3):
      for kx in range(3):
        iy=y+ky-1; ix=x+kx-1
        pix=image[iy*28+ix] if 0<=iy<28 and 0<=ix<28 else 0
        acc += pix*weights[f*9+ky*3+kx]
    acc &= (1<<20)-1
    if acc & (1<<19): acc-=1<<20
    addr=f*784+pos
    if rtl_acc[addr]!=(addr,f,acc):
      ae+=1
      if len(firsta)<5:firsta.append((addr,f,acc,rtl_acc[addr]))
    q=max(0,min(255,(max(0,acc)*MULT+ROUND)>>31))
    if rtl_act[addr]!=(addr,q):
      qe+=1
      if len(firstq)<10:firstq.append((addr,q,rtl_act[addr]))
print("Same-padding Conv1 outputs:",len(rtl_acc))
print("Accumulator mismatches:",ae)
print("Activation mismatches:",qe)
if firsta: print("First accumulator mismatches:",firsta)
if firstq: print("First activation mismatches:",firstq)
if ae or qe: raise SystemExit(1)
print("PASS: all 12,544 same-padding accumulators and activations match Python.")
