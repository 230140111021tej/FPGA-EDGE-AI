
`timescale 1ns / 1ps

module mac_demo_top_tb;

    reg clk = 0;
    reg btnC = 0;
    reg btnU = 0;
    reg btnR = 0;
    reg btnD = 0;
    reg [7:0] sw = 0;
    wire [7:0] led;

    mac_demo_top dut (
        .clk(clk),
        .btnC(btnC),
        .btnU(btnU),
        .btnR(btnR),
        .btnD(btnD),
        .sw(sw),
        .led(led)
    );

    always #5 clk = ~clk;

    task press_button;
        input integer button_id;
        begin
            @(negedge clk);
            case (button_id)
                0: btnU = 1;
                1: btnR = 1;
                2: btnD = 1;
                3: btnC = 1;
            endcase

            repeat (5) @(negedge clk);

            case (button_id)
                0: btnU = 0;
                1: btnR = 0;
                2: btnD = 0;
                3: btnC = 0;
            endcase

            repeat (5) @(negedge clk);
        end
    endtask

    initial begin
        // Load activation = 10.
        sw = 8'd10;
        press_button(0);

        // Load weight = 3.
        sw = 8'd3;
        press_button(1);

        // Execute: accumulator = 10 * 3 = 30.
        press_button(2);

$display("activation=%0d weight=%0d enable=%b clear=%b accumulator=%0d",
         dut.activation, dut.weight, dut.enable, dut.clear,
         dut.accumulator);

if (led !== 8'd30)
    $display("FAIL: expected 30, got %0d", led);
        else
            $display("PASS: wrapper result = %0d", led);

        // Clear the accumulator.
        press_button(3);

        if (led !== 8'd0)
            $display("FAIL: clear expected 0, got %0d", led);
        else
            $display("PASS: wrapper clear = 0");

        $finish;
    end

endmodule
