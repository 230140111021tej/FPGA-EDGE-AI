from pathlib import Path
root=Path(r"D:\FPGA_EdgeAI\cnn_baseline")
def ints(name): return [int(x.strip()) for x in (root/name).read_text().splitlines() if x.strip()]
ref_acc=ints("fc1_reference_acc.txt")
ref_act=ints("fc1_reference_activations.txt")
rtl_acc=[]
for line in (root/"fc1_rtl_accumulators.txt").read_text().splitlines():
 p=line.split()
 if len(p)==2: rtl_acc.append(tuple(map(int,p)))
rtl_act=[]
for line in (root/"fc1_rtl_activations.txt").read_text().splitlines():
 p=line.split()
 if len(p)==2: rtl_act.append(tuple(map(int,p)))
if len(ref_acc)!=64 or len(ref_act)!=64 or len(rtl_acc)!=64 or len(rtl_act)!=64:
 raise SystemExit(f"Row count error: ref_acc={len(ref_acc)} ref_act={len(ref_act)} rtl_acc={len(rtl_acc)} rtl_act={len(rtl_act)}")
acc_errors=[(i,ref_acc[i],rtl_acc[i]) for i in range(64) if rtl_acc[i]!=(i,ref_acc[i])]
act_errors=[(i,ref_act[i],rtl_act[i]) for i in range(64) if rtl_act[i]!=(i,ref_act[i])]
print(f"FC1 accumulators: {len(rtl_acc)}, mismatches: {len(acc_errors)}")
print(f"FC1 activations: {len(rtl_act)}, mismatches: {len(act_errors)}")
if acc_errors: print("First accumulator mismatches:",acc_errors[:10])
if act_errors: print("First activation mismatches:",act_errors[:10])
if acc_errors or act_errors: raise SystemExit("FC1 validation failed.")
print("PASS: all 64 FC1 accumulators and activations match Python.")
