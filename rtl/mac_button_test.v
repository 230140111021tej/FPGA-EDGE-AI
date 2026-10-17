module mac_button_test (
    input  wire       clk,
    input  wire       btnU,
    input  wire [7:0] sw,
    output wire [7:0] led
);
    reg [1:0] btn_sync = 2'b00;
    reg btn_prev = 1'b0;
    reg [7:0] captured = 8'h00;

    always @(posedge clk) begin
        btn_sync <= {btn_sync[0], btnU};
        btn_prev <= btn_sync[1];

        if (btn_sync[1] && !btn_prev)
            captured <= sw;
    end

    assign led = captured;
endmodule
