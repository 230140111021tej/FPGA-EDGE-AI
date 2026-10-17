$ErrorActionPreference = "Stop"
$root = "D:\FPGA_EdgeAI\cnn_baseline"
$vivado = "D:\vivado\2025.1\Vivado\bin"
Set-Location $root

# Preserve the currently passing valid-convolution implementation as a baseline.
if ((Test-Path "rtl\conv1_full_layer.v") -and -not (Test-Path "rtl\conv1_full_layer_valid_backup.v")) {
    Copy-Item "rtl\conv1_full_layer.v" "rtl\conv1_full_layer_valid_backup.v"
}
if ((Test-Path "tb\tb_conv1_requant_validation.v") -and -not (Test-Path "tb\tb_conv1_requant_validation_valid_backup.v")) {
    Copy-Item "tb\tb_conv1_requant_validation.v" "tb\tb_conv1_requant_validation_valid_backup.v"
}

$layer = @'
`timescale 1ns/1ps
module conv1_full_layer #(
 parameter IMAGE_FILE = "rom/conv1_image_u8_hex.mem",
 parameter WEIGHT_FILE = "rom/conv1_weights_int8_hex.mem",
 parameter BIAS_FILE = "rom/conv1_bias_int32_hex.mem"
)(
 input wire clk, input wire rst, input wire start,
 output reg busy, output reg done,
 output reg [13:0] out_addr, output reg [3:0] out_filter,
 output reg signed [19:0] out_acc, output reg out_valid
);
 reg [7:0] image [0:783];
 reg [7:0] weights [0:143];
 reg [31:0] biases [0:15];
 reg [71:0] pixels_reg, weights_reg;
 reg signed [31:0] bias_reg;
 reg mac_start;
 wire mac_busy, mac_done;
 wire signed [19:0] mac_acc;
 integer pixel_index, filter_index;
 integer row, col, kk, ky, kx, iy, ix;
 reg [71:0] px_tmp, wt_tmp;

 conv1_shared_mac mac(
  .clk(clk), .rst(rst), .start(mac_start),
  .pixels(pixels_reg), .weights(weights_reg), .bias(bias_reg),
  .acc(mac_acc), .busy(mac_busy), .done(mac_done)
 );

 initial begin
  $readmemh(IMAGE_FILE, image);
  $readmemh(WEIGHT_FILE, weights);
  $readmemh(BIAS_FILE, biases);
 end

 // PyTorch Conv2d(kernel=3, padding=1): zero-pad by one pixel.
 task load_window;
  input integer pos;
  input integer filt;
  begin
   row = pos / 28;
   col = pos % 28;
   px_tmp = 72'd0;
   wt_tmp = 72'd0;
   for (kk=0; kk<9; kk=kk+1) begin
    ky = kk / 3;
    kx = kk % 3;
    iy = row + ky - 1;
    ix = col + kx - 1;
    if ((iy >= 0) && (iy < 28) && (ix >= 0) && (ix < 28))
     px_tmp[kk*8 +: 8] = image[iy*28+ix];
    else
     px_tmp[kk*8 +: 8] = 8'd0;
    wt_tmp[kk*8 +: 8] = weights[filt*9+kk];
   end
   pixels_reg <= px_tmp;
   weights_reg <= wt_tmp;
   bias_reg <= biases[filt];
  end
 endtask

 always @(posedge clk) begin
  if (rst) begin
   busy<=0; done<=0; out_valid<=0; out_addr<=0; out_filter<=0; out_acc<=0;
   pixel_index<=0; filter_index<=0; mac_start<=0;
   pixels_reg<=0; weights_reg<=0; bias_reg<=0;
  end else begin
   done<=0;
   out_valid<=0;
   mac_start<=0;
   if (start && !busy) begin
    busy<=1;
    pixel_index<=0;
    filter_index<=0;
    load_window(0,0);
    mac_start<=1;
   end else if (busy && mac_done) begin
    out_addr <= filter_index*784 + pixel_index;
    out_filter <= filter_index[3:0];
    out_acc <= mac_acc;
    out_valid <= 1;
    if (pixel_index == 783) begin
     if (filter_index == 15) begin
      busy<=0;
      done<=1;
     end else begin
      pixel_index<=0;
      filter_index<=filter_index+1;
      load_window(0,filter_index+1);
      mac_start<=1;
     end
    end else begin
     pixel_index<=pixel_index+1;
     load_window(pixel_index+1,filter_index);
     mac_start<=1;
    end
   end
  end
 end
endmodule
'@
Set-Content "rtl\conv1_full_layer.v" $layer -Encoding ascii

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
  while((!done_seen || act_count<12544) && cycles<180000) begin
   @(posedge clk); cycles=cycles+1;
  end
  #1;
  $fclose(fd_acc); $fclose(fd_act);
  if(!done_seen || count!=12544 || act_count!=12544 || errors!=0) begin
   $display("FAIL done=%0d accumulators=%0d activations=%0d errors=%0d",
    done_seen,count,act_count,errors);
   $fatal(1);
  end
  $display("PASS: SAME-PADDING Conv1 produced %0d accumulators and %0d activations",count,act_count);
  $finish;
 end
endmodule
'@
Set-Content "tb\tb_conv1_requant_validation.v" $tb -Encoding ascii

$py = @'
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
'@
Set-Content "scripts\verify_conv1_requant.py" $py -Encoding ascii

$xvlog=Join-Path $vivado "xvlog.bat"
$xelab=Join-Path $vivado "xelab.bat"
$xsim=Join-Path $vivado "xsim.bat"
& $xvlog -work xil_defaultlib rtl\conv1_shared_mac.v rtl\conv1_full_layer.v rtl\conv1_requantize.v tb\tb_conv1_requant_validation.v
if ($LASTEXITCODE -ne 0) { throw "XSim compilation failed" }
& $xelab xil_defaultlib.tb_conv1_requant_validation -s conv1_samepad_validation_sim
if ($LASTEXITCODE -ne 0) { throw "XSim elaboration failed" }
& $xsim conv1_samepad_validation_sim -runall
if ($LASTEXITCODE -ne 0) { throw "XSim simulation failed" }
python scripts\verify_conv1_requant.py
if ($LASTEXITCODE -ne 0) { throw "Same-padding Conv1 numerical comparison failed." }

Write-Host ""
Write-Host "Updated Conv1 geometry to PyTorch padding=1."
Write-Host "Valid-convolution backup: rtl\conv1_full_layer_valid_backup.v"
Write-Host "Valid-convolution testbench backup: tb\tb_conv1_requant_validation_valid_backup.v"
