$ErrorActionPreference = "Stop"
$root = "D:\FPGA_EdgeAI\cnn_baseline"
$vivado = "D:\vivado\2025.1\Vivado\bin"
Set-Location $root

# Extend the Python reference generator to export Pool1 as byte hex for the RTL input ROM.
$refPath = "scripts\generate_conv2_reference.py"
$refText = Get-Content $refPath -Raw
if ($refText -notmatch "conv2_pool1_input_hex\.mem") {
    $needle = '(?m)^pool1=x1\.reshape\(16,14,2,14,2\)\.max\(axis=\(2,4\)\)\s*$'
    $replacement = 'pool1=x1.reshape(16,14,2,14,2).max(axis=(2,4))' + "`r`n" +
        '(root/"rom"/"conv2_pool1_input_hex.mem").write_text("".join(f"{int(v):02X}\n" for v in pool1.reshape(-1)))'
    $refText = [regex]::Replace($refText, $needle, $replacement)
    Set-Content $refPath $refText -Encoding ascii
}
python $refPath
if ($LASTEXITCODE -ne 0) { throw "Python reference regeneration failed." }

# Convert signed decimal parameters to two's-complement hex ROMs for Verilog.
$convert = @'
from pathlib import Path
root=Path(r"D:\FPGA_EdgeAI\cnn_baseline")
params=root/"outputs"/"rtl_params"
rom=root/"rom"
def dec(path): return [int(x.strip()) for x in path.read_text().splitlines() if x.strip()]
def write(vals,path,bits):
    mask=(1<<bits)-1
    path.write_text("".join(f"{v & mask:0{bits//4}X}\n" for v in vals))
write(dec(params/"conv2_weights_int8.txt"),rom/"conv2_weights_int8_hex.mem",8)
write(dec(params/"conv2_bias_int32.txt"),rom/"conv2_bias_int32_hex.mem",32)
print("Exported Conv2 weights/biases to hex ROMs.")
'@
Set-Content "scripts\convert_conv2_rom.py" $convert -Encoding ascii
python scripts\convert_conv2_rom.py
if ($LASTEXITCODE -ne 0) { throw "Conv2 ROM conversion failed." }

$mac = @'
`timescale 1ns/1ps
module conv2_shared_mac(
 input wire clk, input wire rst, input wire start,
 input wire [1151:0] pixels, input wire [1151:0] weights,
 input wire signed [31:0] bias,
 output reg signed [19:0] acc, output reg busy, output reg done
);
 reg [7:0] index;
 reg signed [31:0] sum;
 reg signed [8:0] p;
 reg signed [7:0] w;
 reg signed [16:0] product;
 always @(posedge clk) begin
  if(rst) begin index<=0; sum<=0; acc<=0; busy<=0; done<=0; p<=0; w<=0; product<=0; end
  else begin
   done<=0;
   if(start && !busy) begin index<=0; sum<=bias; busy<=1; end
   else if(busy) begin
    p={1'b0,pixels[index*8 +: 8]};
    w=$signed(weights[index*8 +: 8]);
    product=p*w;
    sum<=sum+product;
    if(index==143) begin acc<=sum+product; busy<=0; done<=1; end
    else index<=index+1'b1;
   end
  end
 end
endmodule
'@
Set-Content "rtl\conv2_shared_mac.v" $mac -Encoding ascii

$layer = @'
`timescale 1ns/1ps
module conv2_full_layer #(
 parameter INPUT_FILE="rom/conv2_pool1_input_hex.mem",
 parameter WEIGHT_FILE="rom/conv2_weights_int8_hex.mem",
 parameter BIAS_FILE="rom/conv2_bias_int32_hex.mem"
)(
 input wire clk,input wire rst,input wire start,
 output reg busy,output reg done,
 output reg [12:0] out_addr,output reg [4:0] out_filter,
 output reg signed [19:0] out_acc,output reg out_valid
);
 reg [7:0] input_map [0:3135];
 reg [7:0] weights [0:4607];
 reg [31:0] biases [0:31];
 reg [1151:0] pixels_reg,weights_reg;
 reg signed [31:0] bias_reg;
 reg mac_start;
 wire mac_busy,mac_done;
 wire signed [19:0] mac_acc;
 integer pos_index,filter_index,channel_index,ky,kx,iy,ix,kk;
 integer row,col;
 reg [1151:0] px_tmp,wt_tmp;

 conv2_shared_mac mac(.clk(clk),.rst(rst),.start(mac_start),
  .pixels(pixels_reg),.weights(weights_reg),.bias(bias_reg),
  .acc(mac_acc),.busy(mac_busy),.done(mac_done));

 initial begin
  $readmemh(INPUT_FILE,input_map);
  $readmemh(WEIGHT_FILE,weights);
  $readmemh(BIAS_FILE,biases);
 end

 task load_window;
  input integer pos;
  input integer filt;
  begin
   row=pos/14; col=pos%14;
   px_tmp=1152'd0; wt_tmp=1152'd0;
   for(kk=0;kk<144;kk=kk+1) begin
    channel_index=kk/9;
    ky=(kk%9)/3; kx=kk%3;
    iy=row+ky-1; ix=col+kx-1;
    if(iy>=0 && iy<14 && ix>=0 && ix<14)
     px_tmp[kk*8 +: 8]=input_map[channel_index*196+iy*14+ix];
    else px_tmp[kk*8 +: 8]=8'd0;
    wt_tmp[kk*8 +: 8]=weights[filt*144+kk];
   end
   pixels_reg<=px_tmp; weights_reg<=wt_tmp; bias_reg<=biases[filt];
  end
 endtask

 always @(posedge clk) begin
  if(rst) begin
   busy<=0; done<=0; out_valid<=0; out_addr<=0; out_filter<=0; out_acc<=0;
   pos_index<=0; filter_index<=0; mac_start<=0; pixels_reg<=0; weights_reg<=0; bias_reg<=0;
  end else begin
   done<=0; out_valid<=0; mac_start<=0;
   if(start && !busy) begin
    busy<=1; pos_index<=0; filter_index<=0;
    load_window(0,0); mac_start<=1;
   end else if(busy && mac_done) begin
    out_addr<=filter_index*196+pos_index;
    out_filter<=filter_index[4:0];
    out_acc<=mac_acc; out_valid<=1;
    if(pos_index==195) begin
     if(filter_index==31) begin busy<=0; done<=1; end
     else begin
      pos_index<=0; filter_index<=filter_index+1;
      load_window(0,filter_index+1); mac_start<=1;
     end
    end else begin
     pos_index<=pos_index+1;
     load_window(pos_index+1,filter_index); mac_start<=1;
    end
   end
  end
 end
endmodule
'@
Set-Content "rtl\conv2_full_layer.v" $layer -Encoding ascii

$tb = @'
`timescale 1ns/1ps
module tb_conv2_validation;
 reg clk=0,rst=1,start=0;
 wire busy,done,out_valid;
 wire [12:0] out_addr;
 wire [4:0] out_filter;
 wire signed [19:0] out_acc;
 integer count=0,cycles=0,fd;
 reg done_seen=0;
 integer errors=0;
 always #5 clk=~clk;
 conv2_full_layer dut(.clk(clk),.rst(rst),.start(start),.busy(busy),.done(done),
  .out_addr(out_addr),.out_filter(out_filter),.out_acc(out_acc),.out_valid(out_valid));
 initial begin
  fd=$fopen("conv2_rtl_accumulators.txt","w");
  if(fd==0) begin $display("ERROR: cannot open accumulator output file"); $fatal(1); end
 end
 always @(posedge clk) begin
  if(rst) begin count<=0;done_seen<=0;errors<=0;end
  else begin
   if(out_valid) begin
    $fwrite(fd,"%0d %0d %0d\n",out_addr,out_filter,$signed(out_acc));
    if(out_addr!==count) begin
     $display("ERROR address expected=%0d got=%0d",count,out_addr);
     errors<=errors+1;
    end
    count<=count+1;
   end
   if(done) done_seen<=1;
  end
 end
 initial begin
  repeat(4) @(posedge clk); rst<=0;
  @(posedge clk); start<=1;
  @(posedge clk); start<=0;
  while((!done_seen || count<6272) && cycles<1000000) begin @(posedge clk); cycles=cycles+1; end
  #1; $fclose(fd);
  if(!done_seen || count!=6272 || errors!=0) begin
   $display("FAIL done=%0d count=%0d errors=%0d cycles=%0d",done_seen,count,errors,cycles);
   $fatal(1);
  end
  $display("PASS: Conv2 RTL generated %0d accumulators in %0d cycles",count,cycles);
  $finish;
 end
endmodule
'@
Set-Content "tb\tb_conv2_validation.v" $tb -Encoding ascii

$compare = @'
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
'@
Set-Content "scripts\compare_conv2_accumulators.py" $compare -Encoding ascii

$xvlog=Join-Path $vivado "xvlog.bat"
$xelab=Join-Path $vivado "xelab.bat"
$xsim=Join-Path $vivado "xsim.bat"
& $xvlog -work xil_defaultlib rtl\conv2_shared_mac.v rtl\conv2_full_layer.v tb\tb_conv2_validation.v
if ($LASTEXITCODE -ne 0) { throw "XSim compilation failed." }
& $xelab xil_defaultlib.tb_conv2_validation -s conv2_validation_sim
if ($LASTEXITCODE -ne 0) { throw "XSim elaboration failed." }
& $xsim conv2_validation_sim -runall
if ($LASTEXITCODE -ne 0) { throw "XSim simulation failed." }
python scripts\compare_conv2_accumulators.py
if ($LASTEXITCODE -ne 0) { throw "Conv2 accumulator comparison failed." }
