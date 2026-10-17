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
