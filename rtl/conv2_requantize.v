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
