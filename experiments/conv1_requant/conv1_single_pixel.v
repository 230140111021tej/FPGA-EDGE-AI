`timescale 1ns/1ps

module conv1_single_pixel #(
    parameter integer ACC_WIDTH = 18,
    parameter integer MULTIPLIER = 5863783,
    parameter integer SHIFT = 31
)(
    input  wire signed [ACC_WIDTH-1:0] acc,
    output wire [7:0] q
);

    wire [ACC_WIDTH-1:0] positive_acc;

    assign positive_acc = acc[ACC_WIDTH-1] ? {ACC_WIDTH{1'b0}} : acc;

    requantize_u8 #(
        .MULTIPLIER(MULTIPLIER),
        .SHIFT(SHIFT),
        .ACC_WIDTH(ACC_WIDTH)
    ) u_requantize (
        .acc(positive_acc),
        .q(q)
    );

endmodule
