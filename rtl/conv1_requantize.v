`timescale 1ns/1ps
module conv1_requantize (
 input wire clk,
 input wire rst,
 input wire in_valid,
 input wire signed [19:0] in_acc,
 output reg out_valid,
 output reg [7:0] out_activation
);
 localparam signed [31:0] MULTIPLIER = 32'sd5863783;
 localparam signed [63:0] ROUNDING = 64'sd1073741824; // 2^30
 reg signed [19:0] relu_acc;
 reg signed [63:0] product_rounded;
 reg signed [63:0] scaled;
 always @(posedge clk) begin
  if (rst) begin
   out_valid <= 1'b0;
   out_activation <= 8'd0;
   relu_acc <= 0;
   product_rounded <= 0;
   scaled <= 0;
  end else begin
   out_valid <= in_valid;
   if (in_valid) begin
    if (in_acc < 0) begin
     out_activation <= 8'd0;
    end else begin
     relu_acc = in_acc;
     product_rounded = $signed({44'b0,relu_acc}) * $signed({32'b0,MULTIPLIER}) + ROUNDING;
     scaled = product_rounded >>> 31;
     if (scaled > 255)
      out_activation <= 8'd255;
     else if (scaled < 0)
      out_activation <= 8'd0;
     else
      out_activation <= scaled[7:0];
    end
   end
  end
 end
endmodule
