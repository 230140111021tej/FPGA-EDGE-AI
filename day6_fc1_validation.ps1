$ErrorActionPreference = "Stop"
$root = "D:\FPGA_EdgeAI\cnn_baseline"
$vivado = "D:\vivado\2025.1\Vivado\bin"
Set-Location $root

Write-Host "`n=== Day 6: FC1 shared-MAC RTL validation ===" -ForegroundColor Cyan

# Build FC1 input from the already validated Conv2/Pool2 Python reference.
# This keeps the FC1 arithmetic test independent of the Conv2 implementation.
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
'@
Set-Content "scripts\prepare_fc1_reference.py" $prepare -Encoding ascii
python scripts\prepare_fc1_reference.py
if ($LASTEXITCODE -ne 0) { throw "FC1 Python reference generation failed." }

$mac = @'
`timescale 1ns/1ps
module fc1_shared_mac(
 input wire clk,
 input wire rst,
 input wire start,
 input wire [12543:0] inputs_flat,
 input wire [12543:0] weights_flat,
 input wire signed [31:0] bias,
 output reg signed [31:0] acc,
 output reg busy,
 output reg done
);
 reg [10:0] index;
 reg signed [8:0] p;
 reg signed [7:0] w;
 reg signed [16:0] product;
 reg signed [31:0] sum;
 always @(posedge clk) begin
  if (rst) begin
   index<=0; p<=0; w<=0; product<=0; sum<=0; acc<=0; busy<=0; done<=0;
  end else begin
   done<=0;
   if (start && !busy) begin
    index<=0; sum<=bias; busy<=1;
   end else if (busy) begin
    p={1'b0,inputs_flat[index*8 +: 8]};
    w=$signed(weights_flat[index*8 +: 8]);
    product=p*w;
    sum<=sum+product;
    if (index==1567) begin
     acc<=sum+product;
     busy<=0;
     done<=1;
    end else index<=index+1'b1;
   end
  end
 end
endmodule
'@
Set-Content "rtl\fc1_shared_mac.v" $mac -Encoding ascii

$layer = @'
`timescale 1ns/1ps
module fc1_full_layer #(
 parameter INPUT_FILE="rom/fc1_pool2_input_hex.mem",
 parameter WEIGHT_FILE="rom/fc1_weights_int8_hex.mem",
 parameter BIAS_FILE="rom/fc1_bias_int32_hex.mem"
)(
 input wire clk,input wire rst,input wire start,
 output reg busy,output reg done,
 output reg [5:0] out_addr,output reg signed [31:0] out_acc,output reg out_valid
);
 reg [7:0] input_map [0:1567];
 reg [7:0] weights [0:100351];
 reg [31:0] biases [0:63];
 reg [12543:0] input_flat,weight_flat;
 reg signed [31:0] bias_reg;
 reg mac_start;
 wire mac_busy,mac_done;
 wire signed [31:0] mac_acc;
 integer neuron_index,k;
 integer j;
 initial begin
  $readmemh(INPUT_FILE,input_map);
  $readmemh(WEIGHT_FILE,weights);
  $readmemh(BIAS_FILE,biases);
 end
 fc1_shared_mac mac(.clk(clk),.rst(rst),.start(mac_start),
  .inputs_flat(input_flat),.weights_flat(weight_flat),.bias(bias_reg),
  .acc(mac_acc),.busy(mac_busy),.done(mac_done));
 always @(posedge clk) begin
  if (rst) begin
   busy<=0; done<=0; out_addr<=0; out_acc<=0; out_valid<=0;
   neuron_index<=0; input_flat<=0; weight_flat<=0; bias_reg<=0; mac_start<=0;
  end else begin
   done<=0; out_valid<=0; mac_start<=0;
   if (start && !busy) begin
    busy<=1; neuron_index<=0;
    for (j=0;j<1568;j=j+1) input_flat[j*8 +: 8] <= input_map[j];
    for (j=0;j<1568;j=j+1) weight_flat[j*8 +: 8] <= weights[j];
    bias_reg<=biases[0];
    mac_start<=1;
   end else if (busy && mac_done) begin
    out_addr<=neuron_index;
    out_acc<=mac_acc;
    out_valid<=1;
    if (neuron_index==63) begin
     busy<=0; done<=1;
    end else begin
     neuron_index<=neuron_index+1;
     for (j=0;j<1568;j=j+1) weight_flat[j*8 +: 8] <= weights[(neuron_index+1)*1568+j];
     bias_reg<=biases[neuron_index+1];
     mac_start<=1;
    end
   end
  end
 end
endmodule
'@
Set-Content "rtl\fc1_full_layer.v" $layer -Encoding ascii

$requant = @'
`timescale 1ns/1ps
module fc1_requantize(
 input wire clk,input wire rst,input wire in_valid,input wire signed [31:0] in_acc,
 output reg out_valid,output reg [7:0] out_data
);
 localparam signed [31:0] MULTIPLIER = 32'sd1427002;
 localparam signed [63:0] ROUNDING = 64'sd1073741824;
 reg signed [63:0] product_rounded;
 reg signed [63:0] scaled;
 always @(posedge clk) begin
  if (rst) begin
   out_valid<=0; out_data<=0; product_rounded<=0; scaled<=0;
  end else begin
   out_valid<=in_valid;
   if (in_valid) begin
    if (in_acc<=0) out_data<=0;
    else begin
     product_rounded=$signed(in_acc)*MULTIPLIER+ROUNDING;
     scaled=product_rounded >>> 31;
     if (scaled>255) out_data<=255;
     else out_data<=scaled[7:0];
    end
   end
  end
 end
endmodule
'@
Set-Content "rtl\fc1_requantize.v" $requant -Encoding ascii

$tb = @'
`timescale 1ns/1ps
module tb_fc1_validation;
 reg clk=0,rst=1,start=0;
 wire busy,done,acc_valid;
 wire [5:0] acc_addr;
 wire signed [31:0] acc_data;
 wire act_valid;
 wire [7:0] act_data;
 integer acc_count=0,act_count=0,cycles=0,acc_fd,act_fd;
 integer addr_errors=0;
 reg done_seen=0;
 reg [7:0] acts [0:63];
 always #5 clk=~clk;
 fc1_full_layer dut(.clk(clk),.rst(rst),.start(start),.busy(busy),.done(done),
  .out_addr(acc_addr),.out_acc(acc_data),.out_valid(acc_valid));
 fc1_requantize rq(.clk(clk),.rst(rst),.in_valid(acc_valid),.in_acc(acc_data),
  .out_valid(act_valid),.out_data(act_data));
 initial begin
  acc_fd=$fopen("fc1_rtl_accumulators.txt","w");
  act_fd=$fopen("fc1_rtl_activations.txt","w");
  if(acc_fd==0 || act_fd==0) begin $display("ERROR opening FC1 outputs"); $fatal(1); end
 end
 always @(posedge clk) begin
  if(rst) begin acc_count<=0; act_count<=0; done_seen<=0; addr_errors<=0; end
  else begin
   if(acc_valid) begin
    $fwrite(acc_fd,"%0d %0d\n",acc_addr,$signed(acc_data));
    if(acc_addr!==acc_count) begin
     $display("ERROR address expected=%0d got=%0d",acc_count,acc_addr);
     addr_errors<=addr_errors+1;
    end
    acc_count<=acc_count+1;
   end
   if(act_valid) begin
    acts[act_count]<=act_data;
    $fwrite(act_fd,"%0d %0d\n",act_count,act_data);
    act_count<=act_count+1;
   end
   if(done) done_seen<=1;
  end
 end
 initial begin
  repeat(4) @(posedge clk); rst<=0;
  @(posedge clk); start<=1;
  @(posedge clk); start<=0;
  while((!done_seen || acc_count<64 || act_count<64) && cycles<200000) begin
   @(posedge clk); cycles=cycles+1;
  end
  #2; $fclose(acc_fd); $fclose(act_fd);
  if(!done_seen || acc_count!=64 || act_count!=64 || addr_errors!=0) begin
   $display("FAIL done=%0d accumulators=%0d activations=%0d address_errors=%0d cycles=%0d",
    done_seen,acc_count,act_count,addr_errors,cycles);
   $fatal(1);
  end
  $display("PASS: generated 64 FC1 accumulators and activations in %0d cycles.",cycles);
  $finish;
 end
endmodule
'@
Set-Content "tb\tb_fc1_validation.v" $tb -Encoding ascii

$compare = @'
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
'@
Set-Content "scripts\compare_fc1.py" $compare -Encoding ascii

$xvlog=Join-Path $vivado "xvlog.bat"
$xelab=Join-Path $vivado "xelab.bat"
$xsim=Join-Path $vivado "xsim.bat"
& $xvlog -work xil_defaultlib rtl\fc1_shared_mac.v rtl\fc1_full_layer.v rtl\fc1_requantize.v tb\tb_fc1_validation.v
if ($LASTEXITCODE -ne 0) { throw "FC1 XSim compilation failed." }
& $xelab xil_defaultlib.tb_fc1_validation -s fc1_validation_sim
if ($LASTEXITCODE -ne 0) { throw "FC1 XSim elaboration failed." }
& $xsim fc1_validation_sim -runall
if ($LASTEXITCODE -ne 0) { throw "FC1 XSim simulation failed." }
python scripts\compare_fc1.py
if ($LASTEXITCODE -ne 0) { throw "FC1 Python comparison failed." }
Write-Host "`nDAY 6 COMPLETE: FC1 accumulator and activation checks passed." -ForegroundColor Green
