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
