from pathlib import Path
import numpy as np
root=Path(r"D:\FPGA_EdgeAI\cnn_baseline")
ref=[int(x.strip()) for x in (root/"fc2_reference_scores.txt").read_text().splitlines() if x.strip()]
rtl=[]
for line in (root/"fc2_rtl_scores.txt").read_text().splitlines():
 p=line.split()
 if len(p)==2: rtl.append(tuple(map(int,p)))
if len(ref)!=10 or len(rtl)!=10:
 raise SystemExit(f"Score count error: reference={len(ref)}, RTL={len(rtl)}")
errors=[(i,ref[i],rtl[i]) for i in range(10) if rtl[i]!=(i,ref[i])]
print(f"FC2 scores: {len(rtl)}, mismatches: {len(errors)}")
if errors: print("Mismatches (class, expected score, RTL row):",errors)
if errors: raise SystemExit("FC2 score validation failed.")
ref_pred=int(np.argmax(ref))
rtl_pred=max(range(10),key=lambda i:rtl[i][1])
print("Python predicted class:",ref_pred)
print("RTL predicted class:",rtl_pred)
if ref_pred!=rtl_pred: raise SystemExit("Predicted-class mismatch.")
print("PASS: all 10 FC2 scores and predicted class match Python.")
