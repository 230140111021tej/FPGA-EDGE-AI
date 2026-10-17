`timescale 1ns/1ps
module fc2_full_layer_hw #(
 parameter INPUT_FILE="rom/fc2_fc1_input_hex.mem",
 parameter WEIGHT_FILE="rom/fc2_weights_int8_hex.mem",
 parameter BIAS_FILE="rom/fc2_bias_int32_hex.mem",
 parameter LOAD_INPUT_ROM=1
)(
 input wire clk,input wire rst,input wire start,
 input wire input_we, input wire [5:0] input_addr, input wire [7:0] input_data,
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
  if (LOAD_INPUT_ROM != 0) $readmemh(INPUT_FILE,input_map);
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
   if (input_we) input_map[input_addr] <= input_data;
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


