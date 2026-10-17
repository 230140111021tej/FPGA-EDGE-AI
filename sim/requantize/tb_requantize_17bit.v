`timescale 1ns/1ps

module tb_requantize_17bit;

    reg  [16:0] acc;
    wire [7:0] q;

    reg [63:0] product;
    reg [63:0] rounded;
    reg [63:0] expected;
    integer i;

    requantize_u8 #(
        .MULTIPLIER(5863783),
        .SHIFT(31),
        .ACC_WIDTH(17)
    ) dut (
        .acc(acc),
        .q(q)
    );

    initial begin
        for (i = 0; i <= 93914; i = i + 1) begin
            acc = i;
            #1;

            product = i * 64'd5863783;
            rounded = product + (64'd1 << 30);
            expected = rounded >> 31;

            if (expected > 255)
                expected = 255;

            if (q !== expected[7:0]) begin
                $display(
                    "FAIL acc=%0d got=%0d expected=%0d",
                    i, q, expected
                );
                $finish;
            end
        end

        $display("PASS: all 93915 Conv1 accumulator values checked");
        $finish;
    end

endmodule
