$ErrorActionPreference = "Stop"
$root = "D:\FPGA_EdgeAI\cnn_baseline"
$vivado = "D:\vivado\2025.1\Vivado\bin"
Set-Location $root

# Standalone registered requantizer: ReLU, Q31 multiply/round, unsigned 8-bit saturation.
$rtl = @'
`timescale 1ns/1ps
module conv1_requantize (
 input wire clk,
 input wire rst,
 input wire in_valid,
 input wire signed [19:0] in_acc,
 output reg out_valid,
 output reg [7:0] out_activation
);
 localparam signed [31:0] MULTIPLIER = 32'sd5863783;
 localparam signed [63:0] ROUNDING = 64'sd1073741824; // 2^30
 reg signed [19:0] relu_acc;
 reg signed [63:0] product_rounded;
 reg signed [63:0] scaled;
 always @(posedge clk) begin
  if (rst) begin
   out_valid <= 1'b0;
   out_activation <= 8'd0;
   relu_acc <= 0;
   product_rounded <= 0;
   scaled <= 0;
  end else begin
   out_valid <= in_valid;
   if (in_valid) begin
    if (in_acc < 0) begin
     out_activation <= 8'd0;
    end else begin
     relu_acc = in_acc;
     product_rounded = $signed({44'b0,relu_acc}) * $signed({32'b0,MULTIPLIER}) + ROUNDING;
     scaled = product_rounded >>> 31;
     if (scaled > 255)
      out_activation <= 8'd255;
     else if (scaled < 0)
      out_activation <= 8'd0;
     else
      out_activation <= scaled[7:0];
    end
   end
  end
 end
endmodule
'@
Set-Content "rtl\conv1_requantize.v" $rtl -Encoding ascii

$tb = @'
`timescale 1ns/1ps
module tb_conv1_requant_validation;
 reg clk=0, rst=1, start=0;
 wire busy, done, acc_valid;
 wire [13:0] out_addr;
 wire [3:0] out_filter;
 wire signed [19:0] out_acc;
 wire act_valid;
 wire [7:0] activation;
 integer count=0, act_count=0, cycles=0, fd_acc, fd_act;
 reg done_seen=0;
 integer errors=0;
 always #5 clk=~clk;

 conv1_full_layer dut(.clk(clk),.rst(rst),.start(start),.busy(busy),.done(done),
  .out_addr(out_addr),.out_filter(out_filter),.out_acc(out_acc),.out_valid(acc_valid));
 conv1_requantize rq(.clk(clk),.rst(rst),.in_valid(acc_valid),.in_acc(out_acc),
  .out_valid(act_valid),.out_activation(activation));

 initial begin
  fd_acc=$fopen("conv1_rtl_outputs.txt","w");
  fd_act=$fopen("conv1_rtl_activations.txt","w");
  if(fd_acc==0 || fd_act==0) begin $display("ERROR: cannot open output files"); $fatal(1); end
 end

 always @(posedge clk) begin
  if(rst) begin count<=0; act_count<=0; done_seen<=0; errors<=0; end
  else begin
   if(acc_valid) begin
    $fwrite(fd_acc,"%0d %0d %0d\n",out_addr,out_filter,$signed(out_acc));
    if(out_addr !== count) begin
     $display("ERROR: expected address %0d got %0d",count,out_addr);
     errors<=errors+1;
    end
    count<=count+1;
   end
   if(act_valid) begin
    $fwrite(fd_act,"%0d %0d\n",act_count,activation);
    act_count<=act_count+1;
   end
   if(done) done_seen<=1;
  end
 end

 initial begin
  repeat(4) @(posedge clk); rst<=0;
  @(posedge clk); start<=1;
  @(posedge clk); start<=0;
  while((!done_seen || act_count<10816) && cycles<150500) begin
   @(posedge clk); cycles=cycles+1;
  end
  #1;
  $fclose(fd_acc); $fclose(fd_act);
  if(!done_seen || count!=10816 || act_count!=10816 || errors!=0) begin
   $display("FAIL done=%0d accumulators=%0d activations=%0d errors=%0d",
    done_seen,count,act_count,errors);
   $fatal(1);
  end
  $display("PASS: produced %0d accumulators and %0d requantized activations",count,act_count);
  $finish;
 end
endmodule
'@
Set-Content "tb\tb_conv1_requant_validation.v" $tb -Encoding ascii

$py = @'
from pathlib import Path
root = Path(r"D:\FPGA_EdgeAI\cnn_baseline")
rom = root / "rom"

def load_hex(path, bits, signed=False):
    out=[]
    for line in path.read_text().splitlines():
        s=line.strip()
        if not s: continue
        v=int(s,16)
        if signed and v & (1 << (bits-1)): v -= 1 << bits
        out.append(v)
    return out

image=load_hex(rom/"conv1_image_u8_hex.mem",8)
weights=load_hex(rom/"conv1_weights_int8_hex.mem",8,True)
biases=load_hex(rom/"conv1_bias_int32_hex.mem",32,True)
if (len(image),len(weights),len(biases)) != (784,144,16):
    raise SystemExit(f"ROM length error: {len(image)}, {len(weights)}, {len(biases)}")

def read_rows(path, ncols):
    rows=[]
    for line in path.read_text().splitlines():
        parts=line.split()
        if len(parts)==ncols:
            rows.append(tuple(map(int,parts)))
    return rows

rtl_acc=read_rows(root/"conv1_rtl_outputs.txt",3)
rtl_act=read_rows(root/"conv1_rtl_activations.txt",2)
if len(rtl_acc)!=10816 or len(rtl_act)!=10816:
    raise SystemExit(f"Wrong output count: accumulators={len(rtl_acc)}, activations={len(rtl_act)}")

MULT=5863783
ROUND=1<<30
acc_errors=0
act_errors=0
first_acc=[]
first_act=[]
for f in range(16):
    for pos in range(676):
        row,col=divmod(pos,26)
        acc=biases[f]
        for ky in range(3):
            for kx in range(3):
                acc += image[(row+ky)*28+col+kx] * weights[f*9+ky*3+kx]
        # Mirror the 20-bit signed accumulator behavior.
        acc &= (1<<20)-1
        if acc & (1<<19): acc -= 1<<20
        addr=f*676+pos
        ra,rf,rv=rtl_acc[addr]
        if (ra,rf,rv)!=(addr,f,acc):
            acc_errors+=1
            if len(first_acc)<5: first_acc.append((addr,f,acc,ra,rf,rv))
        # ReLU then round-to-nearest with halfway cases upward, shift Q31, saturate U8.
        relu=max(acc,0)
        q=(relu*MULT+ROUND)>>31
        q=max(0,min(255,q))
        ia,iv=rtl_act[addr]
        if (ia,iv)!=(addr,q):
            act_errors+=1
            if len(first_act)<10: first_act.append((addr,q,ia,iv))

print("Accumulator reference mismatches:",acc_errors)
print("Requantized activation mismatches:",act_errors)
if first_acc:
    print("First accumulator mismatches:",first_acc)
if first_act:
    print("First activation mismatches (index, expected, RTL_index, RTL_value):")
    for x in first_act: print(x)
if acc_errors or act_errors:
    raise SystemExit(1)
print("PASS: all 10,816 accumulators and all 10,816 requantized activations match Python.")
'@
Set-Content "scripts\verify_conv1_requant.py" $py -Encoding ascii

$xvlog = Join-Path $vivado "xvlog.bat"
$xelab = Join-Path $vivado "xelab.bat"
$xsim = Join-Path $vivado "xsim.bat"
& $xvlog -work xil_defaultlib rtl\conv1_shared_mac.v rtl\conv1_full_layer.v rtl\conv1_requantize.v tb\tb_conv1_requant_validation.v
if ($LASTEXITCODE -ne 0) { throw "XSim compilation failed" }
& $xelab xil_defaultlib.tb_conv1_requant_validation -s conv1_requant_validation_sim
if ($LASTEXITCODE -ne 0) { throw "XSim elaboration failed" }
& $xsim conv1_requant_validation_sim -runall
if ($LASTEXITCODE -ne 0) { throw "XSim simulation failed" }
python scripts\verify_conv1_requant.py
if ($LASTEXITCODE -ne 0) { throw "Requantization reference comparison failed." }
