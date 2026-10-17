$ErrorActionPreference = "Stop"
$root = "D:\FPGA_EdgeAI\cnn_baseline"
$vivado = "D:\vivado\2025.1\Vivado\bin"
Set-Location $root

Write-Host "`n=== Day 5: Conv2 requantization and pooling validation ===" -ForegroundColor Cyan

# Rebuild the independent Python reference and the Pool1 input ROM.
python scripts\generate_conv2_reference.py
if ($LASTEXITCODE -ne 0) { throw "Python reference generation failed." }

# Ensure the Conv2 signed parameter ROMs are up to date.
python scripts\convert_conv2_rom.py
if ($LASTEXITCODE -ne 0) { throw "Conv2 ROM conversion failed." }

$requant = @'
`timescale 1ns/1ps
module conv2_requantize(
 input wire clk,
 input wire rst,
 input wire in_valid,
 input wire signed [19:0] in_acc,
 output reg out_valid,
 output reg [7:0] out_data
);
 localparam signed [31:0] MULTIPLIER = 32'sd3005712;
 localparam signed [63:0] ROUNDING = 64'sd1073741824;
 reg signed [63:0] product_rounded;
 reg signed [63:0] scaled;
 always @(posedge clk) begin
  if (rst) begin
   out_valid <= 1'b0;
   out_data <= 8'd0;
   product_rounded <= 64'sd0;
   scaled <= 64'sd0;
  end else begin
   out_valid <= in_valid;
   if (in_valid) begin
    if (in_acc <= 0) begin
     out_data <= 8'd0;
    end else begin
     product_rounded = $signed(in_acc) * MULTIPLIER + ROUNDING;
     scaled = product_rounded >>> 31;
     if (scaled > 255) out_data <= 8'd255;
     else out_data <= scaled[7:0];
    end
   end
  end
 end
endmodule
'@
Set-Content "rtl\conv2_requantize.v" $requant -Encoding ascii

$tb = @'
`timescale 1ns/1ps
module tb_conv2_requant_pool_validation;
 reg clk=0, rst=1, start=0;
 wire busy, done, acc_valid;
 wire [12:0] acc_addr;
 wire [4:0] acc_filter;
 wire signed [19:0] acc_data;
 wire act_valid;
 wire [7:0] act_data;

 integer acc_count=0, act_count=0, cycles=0;
 integer acc_fd, act_fd, pool_fd;
 integer f,y,x,base,idx;
 integer a,b,c,d,mx;
 reg done_seen=0;
 integer addr_errors=0;
 reg [7:0] activations [0:6271];

 always #5 clk=~clk;

 conv2_full_layer dut(
  .clk(clk), .rst(rst), .start(start),
  .busy(busy), .done(done),
  .out_addr(acc_addr), .out_filter(acc_filter),
  .out_acc(acc_data), .out_valid(acc_valid)
 );

 conv2_requantize rq(
  .clk(clk), .rst(rst), .in_valid(acc_valid), .in_acc(acc_data),
  .out_valid(act_valid), .out_data(act_data)
 );

 initial begin
  acc_fd=$fopen("conv2_rtl_accumulators.txt","w");
  act_fd=$fopen("conv2_rtl_activations.txt","w");
  if (acc_fd==0 || act_fd==0) begin
   $display("ERROR: unable to open output files");
   $fatal(1);
  end
 end

 always @(posedge clk) begin
  if (rst) begin
   acc_count <= 0;
   act_count <= 0;
   done_seen <= 0;
   addr_errors <= 0;
  end else begin
   if (acc_valid) begin
    $fwrite(acc_fd,"%0d %0d %0d\n",acc_addr,acc_filter,$signed(acc_data));
    if (acc_addr !== acc_count) begin
     $display("ERROR: accumulator address expected %0d, got %0d",acc_count,acc_addr);
     addr_errors <= addr_errors + 1;
    end
    acc_count <= acc_count + 1;
   end
   if (act_valid) begin
    activations[act_count] <= act_data;
    $fwrite(act_fd,"%0d %0d\n",act_count,act_data);
    act_count <= act_count + 1;
   end
   if (done) done_seen <= 1;
  end
 end

 initial begin
  repeat(4) @(posedge clk);
  rst <= 0;
  @(posedge clk); start <= 1;
  @(posedge clk); start <= 0;

  while ((!done_seen || acc_count < 6272 || act_count < 6272) && cycles < 1000000) begin
   @(posedge clk);
   cycles = cycles + 1;
  end
  #2;
  $fclose(acc_fd);
  $fclose(act_fd);

  if (!done_seen || acc_count != 6272 || act_count != 6272 || addr_errors != 0) begin
   $display("FAIL: done=%0d acc_count=%0d act_count=%0d addr_errors=%0d cycles=%0d",
            done_seen,acc_count,act_count,addr_errors,cycles);
   $fatal(1);
  end

  // Pool the RTL-generated activation stream in filter-major order.
  // This checks the pooling result from hardware requantization outputs.
  pool_fd=$fopen("conv2_rtl_pool2.txt","w");
  if (pool_fd==0) begin $display("ERROR: cannot open pool output file"); $fatal(1); end
  for (f=0; f<32; f=f+1) begin
   for (y=0; y<7; y=y+1) begin
    for (x=0; x<7; x=x+1) begin
     base=f*196+(2*y)*14+(2*x);
     a=activations[base];
     b=activations[base+1];
     c=activations[base+14];
     d=activations[base+15];
     mx=a;
     if (b>mx) mx=b;
     if (c>mx) mx=c;
     if (d>mx) mx=d;
     $fwrite(pool_fd,"%0d\n",mx);
    end
   end
  end
  $fclose(pool_fd);
  $display("PASS: generated %0d Conv2 accumulators and %0d activations.",acc_count,act_count);
  $display("Generated 1,568 Pool2 values from the RTL activation outputs.");
  $display("Simulation cycles: %0d",cycles);
  $finish;
 end
endmodule
'@
Set-Content "tb\tb_conv2_requant_pool_validation.v" $tb -Encoding ascii

$compare = @'
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
'@
Set-Content "scripts\compare_conv2_requant_pool.py" $compare -Encoding ascii

$xvlog = Join-Path $vivado "xvlog.bat"
$xelab = Join-Path $vivado "xelab.bat"
$xsim = Join-Path $vivado "xsim.bat"

& $xvlog -work xil_defaultlib rtl\conv2_shared_mac.v rtl\conv2_full_layer.v rtl\conv2_requantize.v tb\tb_conv2_requant_pool_validation.v
if ($LASTEXITCODE -ne 0) { throw "XSim compilation failed." }

& $xelab xil_defaultlib.tb_conv2_requant_pool_validation -s conv2_requant_pool_validation_sim
if ($LASTEXITCODE -ne 0) { throw "XSim elaboration failed." }

& $xsim conv2_requant_pool_validation_sim -runall
if ($LASTEXITCODE -ne 0) { throw "XSim simulation failed." }

python scripts\compare_conv2_requant_pool.py
if ($LASTEXITCODE -ne 0) { throw "Conv2 activation/pooling comparison failed." }

Write-Host "`nDAY 5 COMPLETE: Conv2 accumulator, activation, and pooling checks passed." -ForegroundColor Green
