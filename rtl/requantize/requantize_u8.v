`timescale 1ns/1ps

module requantize_u8 #(
    parameter integer MULTIPLIER = 5863783,
    parameter integer SHIFT = 31,
    parameter integer ACC_WIDTH = 32
)(
    input  wire [ACC_WIDTH-1:0] acc,
    output reg  [7:0]  q
);

    // Unsigned accumulator input: expected to be nonnegative.
    // 64-bit intermediate prevents overflow for the configured multipliers.
    wire [63:0] product;
    wire [63:0] rounded;

    assign product = {{(64-ACC_WIDTH){1'b0}}, acc} * MULTIPLIER;
    assign rounded = product + (64'd1 << (SHIFT - 1));

    always @* begin
        if ((rounded >> SHIFT) > 64'd255)
            q = 8'd255;
        else
            q = (rounded >> SHIFT);
    end

endmodule
