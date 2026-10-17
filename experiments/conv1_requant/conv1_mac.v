`timescale 1ns/1ps

module conv1_mac (
    input  wire [71:0] pixels,
    input  wire [71:0] weights,
    input  wire signed [31:0] bias,
    output reg  signed [17:0] acc
);
    integer i;
    reg [7:0] pixel_u;
    reg signed [7:0] weight_s;
    reg signed [15:0] product;
    reg signed [17:0] sum;
    reg signed [8:0] pixel_ext;

    always @* begin
        sum = bias;

        for (i = 0; i < 9; i = i + 1) begin
            pixel_u = pixels[i*8 +: 8];
            weight_s = $signed(weights[i*8 +: 8]);

            // Extend the unsigned pixel to signed 9-bit first.
            pixel_ext = $signed({1'b0, pixel_u});
            product = pixel_ext * weight_s;

            sum = sum + {{2{product[15]}}, product};
        end

        acc = sum;
    end
endmodule
