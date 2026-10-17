$ErrorActionPreference = "Stop"
$root = "D:\FPGA_EdgeAI\cnn_baseline"
$rtl = Join-Path $root "rtl"
$tb = Join-Path $root "tb"
$scripts = Join-Path $root "scripts"
New-Item -ItemType Directory -Force -Path $rtl,$tb,$scripts | Out-Null

@'
`timescale 1ns/1ps
module conv1_shared_mac (
 input wire clk, input wire rst, input wire start,
 input wire [71:0] pixels, input wire [71:0] weights,
 input wire signed [31:0] bias,
 output reg signed [19:0] acc, output reg busy, output reg done
);
 reg [3:0] index;
 reg signed [19:0] sum;
 reg [7:0] p;
 reg signed [7:0] w;
 reg signed [16:0] product;
 always @(posedge clk) begin
  if (rst) begin index<=0; sum<=0; acc<=0; busy<=0; done<=0; p<=0; w<=0; product<=0; end
  else begin
   done<=0;
   if (start && !busy) begin index<=0; sum<=bias[19:0]; busy<=1; end
   else if (busy) begin
    p=pixels[index*8 +: 8];
    w=$signed(weights[index*8 +: 8]);
    product=p*w;
    sum<=sum+product;
    if(index==8) begin acc<=sum+product; busy<=0; done<=1; end
    else index<=index+1'b1;
   end
  end
 end
endmodule
'@ | Set-Content (Join-Path $rtl "conv1_shared_mac.v") -Encoding ascii

@'
`timescale 1ns/1ps
module conv1_full_layer #(
 parameter IMAGE_FILE="rom/conv1_image_u8_hex.mem",
 parameter WEIGHT_FILE="rom/conv1_weights_int8_hex.mem",
 parameter BIAS_FILE="rom/conv1_bias_int32_hex.mem"
)(
 input wire clk, input wire rst, input wire start,
 output reg busy, output reg done, output reg [13:0] out_addr,
 output reg [3:0] out_filter, output reg signed [19:0] out_acc,
 output reg out_valid
);
 reg [7:0] image[0:783];
 reg [7:0] weights[0:143];
 reg [31:0] biases[0:15];
 reg [9:0] pixel_index;
 reg [3:0] filter_index;
 reg mac_start;
 reg [71:0] window_pixels, window_weights;
 reg signed [31:0] mac_bias;
 wire signed [19:0] mac_acc;
 wire mac_busy, mac_done;
 integer t, row, col, next_pos;
 conv1_shared_mac mac(.clk(clk),.rst(rst),.start(mac_start),
  .pixels(window_pixels),.weights(window_weights),.bias(mac_bias),
  .acc(mac_acc),.busy(mac_busy),.done(mac_done));
 initial begin
  $readmemh(IMAGE_FILE,image);
  $readmemh(WEIGHT_FILE,weights);
  $readmemh(BIAS_FILE,biases);
 end
 task load_window;
  input [9:0] pos;
  input [3:0] filt;
  integer rr,cc,kk;
  begin
   rr=pos/26; cc=pos%26;
   for(kk=0;kk<9;kk=kk+1) begin
    window_pixels[kk*8 +: 8] <= image[(rr+kk/3)*28+cc+kk%3];
    window_weights[kk*8 +: 8] <= weights[filt*9+kk];
   end
   mac_bias <= $signed(biases[filt]);
  end
 endtask
 always @(posedge clk) begin
  if(rst) begin
   busy<=0; done<=0; out_valid<=0; out_addr<=0; out_filter<=0; out_acc<=0;
   pixel_index<=0; filter_index<=0; mac_start<=0; window_pixels<=0;
   window_weights<=0; mac_bias<=0;
  end else begin
   done<=0; out_valid<=0; mac_start<=0;
   if(start && !busy) begin
    busy<=1; pixel_index<=0; filter_index<=0;
    load_window(0,0); mac_start<=1;
   end else if(busy && mac_done) begin
    out_addr<=filter_index*676+pixel_index;
    out_filter<=filter_index; out_acc<=mac_acc; out_valid<=1;
    if(pixel_index==675 && filter_index==15) begin busy<=0; done<=1; end
    else begin
     if(pixel_index==675) begin pixel_index<=0; filter_index<=filter_index+1'b1; load_window(0,filter_index+1'b1); end
     else begin pixel_index<=pixel_index+1'b1; load_window(pixel_index+1'b1,filter_index); end
     mac_start<=1;
    end
   end
  end
 end
endmodule
'@ | Set-Content (Join-Path $rtl "conv1_full_layer.v") -Encoding ascii

@'
`timescale 1ns/1ps
module tb_conv1_full_layer;
 reg clk=0,rst=1,start=0;
 wire busy,done,out_valid;
 wire [13:0] out_addr;
 wire [3:0] out_filter;
 wire signed [19:0] out_acc;
 integer count=0, cycles=0;
 always #5 clk=~clk;
 conv1_full_layer dut(.clk(clk),.rst(rst),.start(start),.busy(busy),.done(done),
  .out_addr(out_addr),.out_filter(out_filter),.out_acc(out_acc),.out_valid(out_valid));
 always @(posedge clk) if(out_valid) count<=count+1;
 initial begin
  repeat(4) @(posedge clk); rst<=0;
  @(posedge clk); start<=1; @(posedge clk); start<=0;
  while(!done && cycles<150000) begin @(posedge clk); cycles=cycles+1; end
  #1;
  if(!done || count!=10816) begin $display("FAIL done=%0b outputs=%0d cycles=%0d",done,count,cycles); $fatal(1); end
  $display("PASS output_count=%0d cycles=%0d",count,cycles); $finish;
 end
endmodule
'@ | Set-Content (Join-Path $tb "tb_conv1_full_layer.v") -Encoding ascii

@'
$ErrorActionPreference = "Stop"
Set-Location "D:\FPGA_EdgeAI\cnn_baseline"
if (!(Test-Path "rom\conv1_image_u8_hex.mem")) {
  $vals = for ($i=0; $i -lt 784; $i++) { "{0:X2}" -f (($i*7+13)%256) }
  Set-Content "rom\conv1_image_u8_hex.mem" $vals -Encoding ascii
  Write-Host "Created deterministic placeholder image. Replace with a real quantized MNIST image for model validation."
}
if (!(Get-Command iverilog -ErrorAction SilentlyContinue)) {
  throw "iverilog not found. Run the testbench in Vivado xsim, or install Icarus Verilog."
}
New-Item -ItemType Directory -Force build | Out-Null
iverilog -g2012 -s tb_conv1_full_layer -o build\conv1_full_layer.vvp rtl\conv1_shared_mac.v rtl\conv1_full_layer.v tb\tb_conv1_full_layer.v
if ($LASTEXITCODE -ne 0) { throw "Compile failed" }
vvp build\conv1_full_layer.vvp
if ($LASTEXITCODE -ne 0) { throw "Simulation failed" }
'@ | Set-Content (Join-Path $scripts "run_conv1_sim.ps1") -Encoding ascii

Write-Host "Created rtl\conv1_shared_mac.v, rtl\conv1_full_layer.v, tb\tb_conv1_full_layer.v, scripts\run_conv1_sim.ps1"
Write-Host "WARNING: This is an integration scaffold, not yet validated for hardware. Review simulation output before use."
