module mac_demo_top (
    input  wire       clk,
    input  wire       btnC,
    input  wire       btnU,
    input  wire       btnR,
    input  wire       btnD,
    input  wire [7:0] sw,
    output wire [7:0] led
);

    // Two-stage synchronizers for physical buttons.
    reg [1:0] btnC_sync = 2'b00;
    reg [1:0] btnU_sync = 2'b00;
    reg [1:0] btnR_sync = 2'b00;
    reg [1:0] btnD_sync = 2'b00;

    reg btnC_prev = 1'b0;
    reg btnU_prev = 1'b0;
    reg btnR_prev = 1'b0;
    reg btnD_prev = 1'b0;

    reg [7:0] activation = 8'd0;
    reg signed [7:0] weight = 8'sd0;

    wire clear_pulse = btnC_sync[1] & ~btnC_prev;
    wire load_activation = btnU_sync[1] & ~btnU_prev;
    wire load_weight = btnR_sync[1] & ~btnR_prev;
    wire execute_mac = btnD_sync[1] & ~btnD_prev;

    always @(posedge clk) begin
        btnC_sync <= {btnC_sync[0], btnC};
        btnU_sync <= {btnU_sync[0], btnU};
        btnR_sync <= {btnR_sync[0], btnR};
        btnD_sync <= {btnD_sync[0], btnD};

        btnC_prev <= btnC_sync[1];
        btnU_prev <= btnU_sync[1];
        btnR_prev <= btnR_sync[1];
        btnD_prev <= btnD_sync[1];

        if (load_activation)
            activation <= sw;

        if (load_weight)
            weight <= $signed(sw);
    end

    wire signed [31:0] accumulator;

    mac_unit mac_inst (
        .clk(clk),
        .rst(1'b0),
        .clear(clear_pulse),
        .enable(execute_mac),
        .activation(activation),
        .weight(weight),
        .accumulator(accumulator)
    );

    assign led = accumulator[7:0];

endmodule
