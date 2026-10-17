
`timescale 1ns / 1ps

module mac_unit_tb;

    reg clk;
    reg rst;
    reg clear;
    reg enable;

    reg [7:0] activation;
    reg signed [7:0] weight;

    wire signed [31:0] accumulator;

    integer errors;

    mac_unit dut (
        .clk(clk),
        .rst(rst),
        .clear(clear),
        .enable(enable),
        .activation(activation),
        .weight(weight),
        .accumulator(accumulator)
    );

    always #5 clk = ~clk;

    task check_result;
        input integer expected;
        begin
            #1;
            if (accumulator !== expected) begin
                $display(
                    "FAIL: expected=%0d actual=%0d",
                    expected, accumulator
                );
                errors = errors + 1;
            end
            else begin
                $display(
                    "PASS: accumulator=%0d",
                    accumulator
                );
            end
        end
    endtask

    initial begin
        clk = 0;
        rst = 1;
        clear = 0;
        enable = 0;
        activation = 0;
        weight = 0;
        errors = 0;

        // Reset the accumulator.
        @(posedge clk);
        #1;
        if (accumulator !== 32'sd0) begin
            $display("FAIL: reset");
            errors = errors + 1;
        end

        @(negedge clk);
        rst = 0;
        clear = 1;

        @(posedge clk);
        #1;
        check_result(0);

        // 10 * 3 = 30
        @(negedge clk);
        clear = 0;
        enable = 1;
        activation = 8'd10;
        weight = 8'sd3;

        @(posedge clk);
        check_result(30);

        // 30 + (5 * -2) = 20
        @(negedge clk);
        activation = 8'd5;
        weight = -8'sd2;

        @(posedge clk);
        check_result(20);

        // 20 + (255 * -127) = -32365
        @(negedge clk);
        activation = 8'd255;
        weight = -8'sd127;

        @(posedge clk);
        check_result(-32365);

        // Disabled MAC must hold its previous value.
        @(negedge clk);
        enable = 0;
        activation = 8'd100;
        weight = 8'sd10;

        @(posedge clk);
        check_result(-32365);

        // Clear the accumulator.
        @(negedge clk);
        clear = 1;

        @(posedge clk);
        check_result(0);

        // 7 * -4 = -28
        @(negedge clk);
        clear = 0;
        enable = 1;
        activation = 8'd7;
        weight = -8'sd4;

        @(posedge clk);
        check_result(-28);

        @(negedge clk);
        enable = 0;

        if (errors == 0)
            $display("ALL MAC TESTS PASSED");
        else
            $display("MAC TESTS FAILED: %0d errors", errors);

        $finish;
    end

endmodule
