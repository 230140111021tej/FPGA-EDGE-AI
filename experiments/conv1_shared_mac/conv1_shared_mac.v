`timescale 1ns/1ps

module conv1_shared_mac (
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire [71:0] pixels,
    input  wire [71:0] weights,
    input  wire signed [31:0] bias,
    output reg signed [17:0] acc,
    output reg busy,
    output reg done
);

    reg [3:0] index;
    reg signed [17:0] sum;

    wire signed [16:0] pixel_signed;
    wire signed [16:0] weight_signed;
    wire signed [16:0] product;
    wire signed [17:0] product_ext;

    assign pixel_signed =
        $signed({9'b0, pixels[index*8 +: 8]});

    assign weight_signed =
        $signed({{9{weights[index*8+7]}},
                  weights[index*8 +: 8]});

    assign product = pixel_signed * weight_signed;
    assign product_ext = {product[16], product};

    always @(posedge clk) begin
        if (rst) begin
            index <= 0;
            sum   <= 0;
            acc   <= 0;
            busy  <= 0;
            done  <= 0;
        end else begin
            done <= 0;

            if (start && !busy) begin
                index <= 0;
                sum   <= bias[17:0];
                busy  <= 1;
            end else if (busy) begin
                if (index == 8) begin
                    acc  <= sum + product_ext;
                    busy <= 0;
                    done <= 1;
                end else begin
                    sum   <= sum + product_ext;
                    index <= index + 1'b1;
                end
            end
        end
    end

endmodule
