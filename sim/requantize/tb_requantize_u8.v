`timescale 1ns/1ps

module tb_requantize_u8;

    reg [31:0] acc;
    wire [7:0] q;
    integer errors = 0;
    integer i;

    requantize_u8 #(
        .MULTIPLIER(5863783),
        .SHIFT(31)
    ) dut (
        .acc(acc),
        .q(q)
    );

    task check;
        input [31:0] value;
        input [7:0] expected;
        begin
            acc = value;
            #1;
            if (q !== expected) begin
                $display("FAIL acc=%0d got=%0d expected=%0d",
                         value, q, expected);
                errors = errors + 1;
            end else begin
                $display("PASS acc=%0d q=%0d", value, q);
            end
        end
    endtask

    initial begin
        check(0, 0);
        check(1, 0);
        check(100, 0);
        check(1000, 3);
        check(100000, 255);
        check(32'hFFFFFFFF, 255);

        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TESTS FAILED: %0d errors", errors);

        $finish;
    end

endmodule
