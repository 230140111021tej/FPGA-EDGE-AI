
module mac_unit (
    input wire clk,
    input wire rst,
    input wire clear,
    input wire enable,

    input wire [7:0] activation,
    input wire signed [7:0] weight,

    output reg signed [31:0] accumulator
);

    // Extend the unsigned activation to a signed 9-bit value.
    wire signed [8:0] activation_signed;
    assign activation_signed = $signed({1'b0, activation});

    // Full-precision product: signed 9-bit x signed 8-bit.
    wire signed [16:0] product;
    assign product = activation_signed * weight;

    always @(posedge clk) begin
        if (rst) begin
            accumulator <= 32'sd0;
        end
        else if (clear) begin
            accumulator <= 32'sd0;
        end
        else if (enable) begin
            accumulator <= accumulator
                         + {{15{product[16]}}, product};
        end
    end

endmodule
