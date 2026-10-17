from pathlib import Path
root = Path(r"D:\FPGA_EdgeAI\cnn_baseline")

def ints(name):
    return [int(x.strip()) for x in (root/name).read_text().splitlines() if x.strip()]

# Accumulator comparison
ref_acc = ints("conv2_reference_acc.txt")
rtl_acc = []
for line in (root/"conv2_rtl_accumulators.txt").read_text().splitlines():
    fields=line.split()
    if len(fields)==3:
        rtl_acc.append(tuple(map(int,fields)))
if len(ref_acc)!=6272 or len(rtl_acc)!=6272:
    raise SystemExit(f"Accumulator row count mismatch: reference={len(ref_acc)}, RTL={len(rtl_acc)}")
acc_errors=[]
for i,(addr,filt,val) in enumerate(rtl_acc):
    if addr!=i or filt!=i//196 or val!=ref_acc[i]:
        if len(acc_errors)<10: acc_errors.append((i,ref_acc[i],addr,filt,val))
print(f"Conv2 accumulators: {len(rtl_acc)}, mismatches: {sum(1 for i,(addr,filt,val) in enumerate(rtl_acc) if addr!=i or filt!=i//196 or val!=ref_acc[i])}")

# Activation comparison
ref_act = ints("conv2_reference_activations.txt")
rtl_act=[]
for line in (root/"conv2_rtl_activations.txt").read_text().splitlines():
    fields=line.split()
    if len(fields)==2:
        rtl_act.append(tuple(map(int,fields)))
if len(ref_act)!=6272 or len(rtl_act)!=6272:
    raise SystemExit(f"Activation row count mismatch: reference={len(ref_act)}, RTL={len(rtl_act)}")
act_errors=[]
for i,(idx,val) in enumerate(rtl_act):
    if idx!=i or val!=ref_act[i]:
        if len(act_errors)<10: act_errors.append((i,ref_act[i],idx,val))
print(f"Conv2 activations: {len(rtl_act)}, mismatches: {sum(1 for i,(idx,val) in enumerate(rtl_act) if idx!=i or val!=ref_act[i])}")

# Pool2 comparison
ref_pool=ints("conv2_reference_pool2.txt")
rtl_pool=ints("conv2_rtl_pool2.txt")
if len(ref_pool)!=1568 or len(rtl_pool)!=1568:
    raise SystemExit(f"Pool2 row count mismatch: reference={len(ref_pool)}, RTL-derived={len(rtl_pool)}")
pool_errors=[(i,ref_pool[i],rtl_pool[i]) for i in range(1568) if ref_pool[i]!=rtl_pool[i]]
print(f"Pool2 outputs: {len(rtl_pool)}, mismatches: {len(pool_errors)}")

if acc_errors:
    print("First accumulator mismatches (index, expected, address, filter, actual):",acc_errors)
if act_errors:
    print("First activation mismatches (index, expected, index_out, actual):",act_errors)
if pool_errors:
    print("First Pool2 mismatches (index, expected, actual):",pool_errors[:10])

if acc_errors or act_errors or pool_errors:
    raise SystemExit("FAIL: one or more Conv2 comparisons did not match.")
print("PASS: all 6,272 accumulators match.")
print("PASS: all 6,272 requantized activations match.")
print("PASS: all 1,568 Pool2 outputs match.")
