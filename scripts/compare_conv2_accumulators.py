from pathlib import Path
root=Path(r"D:\FPGA_EdgeAI\cnn_baseline")
ref=[int(x) for x in (root/"conv2_reference_acc.txt").read_text().splitlines() if x.strip()]
rtl=[]
for line in (root/"conv2_rtl_accumulators.txt").read_text().splitlines():
    p=line.split()
    if len(p)==3: rtl.append(tuple(map(int,p)))
if len(ref)!=6272 or len(rtl)!=6272:
    raise SystemExit(f"Expected 6272 rows; reference={len(ref)} RTL={len(rtl)}")
errors=0; first=[]
for i,(addr,filt,val) in enumerate(rtl):
    exp=ref[i]
    expected_filter=i//196
    if addr!=i or filt!=expected_filter or val!=exp:
        errors+=1
        if len(first)<10:first.append((i,expected_filter,exp,addr,filt,val))
print("Conv2 RTL outputs:",len(rtl))
print("Accumulator mismatches:",errors)
if first:
    print("First mismatches (index, expected_filter, expected_acc, rtl_addr, rtl_filter, rtl_acc):")
    for row in first:print(row)
if errors: raise SystemExit(1)
print("PASS: all 6,272 Conv2 RTL accumulators match Python reference.")
