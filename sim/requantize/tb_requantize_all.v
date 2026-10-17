`timescale 1ns/1ps

module tb_requantize_all;
    reg [31:0] acc;
    wire [7:0] q_conv1, q_conv2, q_fc1;

    integer fd, rc;
    integer expected1, expected2, expected3;
    integer errors = 0;
    integer tests = 0;
    reg [31:0] value;

    requantize_u8 #(.MULTIPLIER(5863783), .SHIFT(31)) u1 (
        .acc(acc), .q(q_conv1)
    );
    requantize_u8 #(.MULTIPLIER(3005712), .SHIFT(31)) u2 (
        .acc(acc), .q(q_conv2)
    );
    requantize_u8 #(.MULTIPLIER(1427002), .SHIFT(31)) u3 (
        .acc(acc), .q(q_fc1)
    );

    initial begin
        fd = $fopen("sim/requantize/requant_vectors.txt", "r");
        if (fd == 0) begin
            $display("ERROR: cannot open reference vectors");
            $finish;
        end

        while (!$feof(fd)) begin
            rc = $fscanf(fd, "%d %d %d %d\n",
                         value, expected1, expected2, expected3);
            if (rc == 4) begin
                acc = value;
                #1;
                tests = tests + 1;
                if (q_conv1 !== expected1[7:0] ||
                    q_conv2 !== expected2[7:0] ||
                    q_fc1   !== expected3[7:0]) begin
                    errors = errors + 1;
                    if (errors <= 10)
                        $display("FAIL acc=%0d: RTL=%0d,%0d,%0d REF=%0d,%0d,%0d",
                            value, q_conv1, q_conv2, q_fc1,
                            expected1, expected2, expected3);
                end
            end
        end
        $fclose(fd);

        if (errors == 0)
            $display("PASS: %0d vectors, all three multipliers", tests);
        else
            $display("FAIL: %0d errors out of %0d vectors", errors, tests);
        $finish;
    end
endmodule
