`timescale 1ns/1ps

module tb_conv1_single_pixel;
    reg signed [17:0] acc;
    wire [7:0] q;
    integer errors;

    conv1_single_pixel #(
        .ACC_WIDTH(18),
        .MULTIPLIER(5863783),
        .SHIFT(31)
    ) dut (
        .acc(acc),
        .q(q)
    );

    task check;
        input integer value;
        input integer expected;
        begin
            acc = value;
            #1;
            if (q !== expected[7:0]) begin
                $display("FAIL acc=%0d expected=%0d got=%0d",
                         value, expected, q);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0;

        check(-65555, 0);
        check(-1, 0);
        check(0, 0);
        check(1, 0);
        check(1000, 3);
        check(75727, 207);

        if (errors == 0)
            $display("PASS: wrapper boundary tests");
        else
            $display("FAIL: %0d errors", errors);

        $finish;
    end
endmodule
