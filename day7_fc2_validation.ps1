$ErrorActionPreference = "Stop"
$root = "D:\FPGA_EdgeAI\cnn_baseline"
$vivado = "D:\vivado\2025.1\Vivado\bin"
Set-Location $root

Write-Host "`n=== Day 7: FC2 RTL validation ===" -ForegroundColor Cyan

$prepare = @'
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
'@
Set-Content "scripts\prepare_fc2_reference.py" $prepare -Encoding ascii
python scripts\prepare_fc2_reference.py
if ($LASTEXITCODE -ne 0) { throw "FC2 Python reference generation failed." }

$mac = @'
`timescale 1ns/1ps
module fc2_shared_mac(
 input wire clk,input wire rst,input wire start,
 input wire [511:0] inputs_flat,input wire [511:0] weights_flat,
 input wire signed [31:0] bias,
 output reg signed [31:0] acc,output reg busy,output reg done
);
 reg [5:0] index;
 reg signed [8:0] p;
 reg signed [7:0] w;
 reg signed [16:0] product;
 reg signed [31:0] sum;
 always @(posedge clk) begin
  if(rst) begin index<=0;p<=0;w<=0;product<=0;sum<=0;acc<=0;busy<=0;done<=0;end
  else begin
   done<=0;
   if(start && !busy) begin index<=0;sum<=bias;busy<=1;end
   else if(busy) begin
    p={1'b0,inputs_flat[index*8 +: 8]};
    w=$signed(weights_flat[index*8 +: 8]);
    product=p*w;
    sum<=sum+product;
    if(index==63) begin acc<=sum+product;busy<=0;done<=1;end
    else index<=index+1'b1;
   end
  end
 end
endmodule
'@
Set-Content "rtl\fc2_shared_mac.v" $mac -Encoding ascii

$layer = @'
`timescale 1ns/1ps
module fc2_full_layer #(
 parameter INPUT_FILE="rom/fc2_fc1_input_hex.mem",
 parameter WEIGHT_FILE="rom/fc2_weights_int8_hex.mem",
 parameter BIAS_FILE="rom/fc2_bias_int32_hex.mem"
)(
 input wire clk,input wire rst,input wire start,
 output reg busy,output reg done,
 output reg [3:0] out_addr,output reg signed [31:0] out_score,output reg out_valid
);
 reg [7:0] input_map [0:63];
 reg [7:0] weights [0:639];
 reg [31:0] biases [0:9];
 reg [511:0] input_flat,weight_flat;
 reg signed [31:0] bias_reg;
 reg mac_start;
 wire mac_busy,mac_done;
 wire signed [31:0] mac_acc;
 integer class_index,j;
 initial begin
  $readmemh(INPUT_FILE,input_map);
  $readmemh(WEIGHT_FILE,weights);
  $readmemh(BIAS_FILE,biases);
 end
 fc2_shared_mac mac(.clk(clk),.rst(rst),.start(mac_start),
  .inputs_flat(input_flat),.weights_flat(weight_flat),.bias(bias_reg),
  .acc(mac_acc),.busy(mac_busy),.done(mac_done));
 always @(posedge clk) begin
  if(rst) begin
   busy<=0;done<=0;out_addr<=0;out_score<=0;out_valid<=0;
   class_index<=0;input_flat<=0;weight_flat<=0;bias_reg<=0;mac_start<=0;
  end else begin
   done<=0;out_valid<=0;mac_start<=0;
   if(start && !busy) begin
    busy<=1;class_index<=0;
    for(j=0;j<64;j=j+1) input_flat[j*8 +: 8]<=input_map[j];
    for(j=0;j<64;j=j+1) weight_flat[j*8 +: 8]<=weights[j];
    bias_reg<=biases[0];
    mac_start<=1;
   end else if(busy && mac_done) begin
    out_addr<=class_index;
    out_score<=mac_acc;
    out_valid<=1;
    if(class_index==9) begin busy<=0;done<=1;end
    else begin
     class_index<=class_index+1;
     for(j=0;j<64;j=j+1) weight_flat[j*8 +: 8]<=weights[(class_index+1)*64+j];
     bias_reg<=biases[class_index+1];
     mac_start<=1;
    end
   end
  end
 end
endmodule
'@
Set-Content "rtl\fc2_full_layer.v" $layer -Encoding ascii

$tb = @'
`timescale 1ns/1ps
module tb_fc2_validation;
 reg clk=0,rst=1,start=0;
 wire busy,done,out_valid;
 wire [3:0] out_addr;
 wire signed [31:0] out_score;
 integer count=0,cycles=0,fd;
 integer addr_errors=0;
 reg done_seen=0;
 always #5 clk=~clk;
 fc2_full_layer dut(.clk(clk),.rst(rst),.start(start),.busy(busy),.done(done),
  .out_addr(out_addr),.out_score(out_score),.out_valid(out_valid));
 initial begin
  fd=$fopen("fc2_rtl_scores.txt","w");
  if(fd==0) begin $display("ERROR opening FC2 score file");$fatal(1);end
 end
 always @(posedge clk) begin
  if(rst) begin count<=0;done_seen<=0;addr_errors<=0;end
  else begin
   if(out_valid) begin
    $fwrite(fd,"%0d %0d\n",out_addr,$signed(out_score));
    if(out_addr!==count) begin
     $display("ERROR score address expected=%0d got=%0d",count,out_addr);
     addr_errors<=addr_errors+1;
    end
    count<=count+1;
   end
   if(done) done_seen<=1;
  end
 end
 initial begin
  repeat(4) @(posedge clk);rst<=0;
  @(posedge clk);start<=1;
  @(posedge clk);start<=0;
  while((!done_seen || count<10) && cycles<10000) begin @(posedge clk);cycles=cycles+1;end
  #2;$fclose(fd);
  if(!done_seen || count!=10 || addr_errors!=0) begin
   $display("FAIL done=%0d count=%0d address_errors=%0d cycles=%0d",done_seen,count,addr_errors,cycles);
   $fatal(1);
  end
  $display("PASS: generated 10 FC2 class scores in %0d cycles.",cycles);
  $finish;
 end
endmodule
'@
Set-Content "tb\tb_fc2_validation.v" $tb -Encoding ascii

$compare = @'
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
'@
Set-Content "scripts\compare_fc2.py" $compare -Encoding ascii

$xvlog=Join-Path $vivado "xvlog.bat"
$xelab=Join-Path $vivado "xelab.bat"
$xsim=Join-Path $vivado "xsim.bat"
& $xvlog -work xil_defaultlib rtl\fc2_shared_mac.v rtl\fc2_full_layer.v tb\tb_fc2_validation.v
if ($LASTEXITCODE -ne 0) { throw "FC2 XSim compilation failed." }
& $xelab xil_defaultlib.tb_fc2_validation -s fc2_validation_sim
if ($LASTEXITCODE -ne 0) { throw "FC2 XSim elaboration failed." }
& $xsim fc2_validation_sim -runall
if ($LASTEXITCODE -ne 0) { throw "FC2 XSim simulation failed." }
python scripts\compare_fc2.py
if ($LASTEXITCODE -ne 0) { throw "FC2 Python comparison failed." }

Write-Host "`nDAY 7 COMPLETE: FC2 score validation passed." -ForegroundColor Green
Write-Host "Note: This validates FC2 using the Python-generated FC1 activation reference, not yet the integrated RTL stream." -ForegroundColor Yellow
