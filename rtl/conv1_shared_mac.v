`timescale 1ns/1ps
module conv1_shared_mac (
 input wire clk, input wire rst, input wire start,
 input wire [71:0] pixels, input wire [71:0] weights,
 input wire signed [31:0] bias,
 output reg signed [19:0] acc, output reg busy, output reg done
);
 reg [3:0] index;
 reg signed [19:0] sum;
 reg signed [8:0] p;
 reg signed [7:0] w;
 reg signed [16:0] product;
 always @(posedge clk) begin
  if (rst) begin index<=0; sum<=0; acc<=0; busy<=0; done<=0; p<=0; w<=0; product<=0; end
  else begin
   done<=0;
   if (start && !busy) begin index<=0; sum<=bias[19:0]; busy<=1; end
   else if (busy) begin
    p={1'b0,pixels[index*8 +: 8]};
    w=$signed(weights[index*8 +: 8]);
    product=p*w;
    sum<=sum+product;
    if(index==8) begin acc<=sum+product; busy<=0; done<=1; end
    else index<=index+1'b1;
   end
  end
 end
endmodule

