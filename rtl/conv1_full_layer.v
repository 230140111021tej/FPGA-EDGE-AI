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
