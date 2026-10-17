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
