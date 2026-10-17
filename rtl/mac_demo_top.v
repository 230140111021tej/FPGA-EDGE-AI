
module mac_demo_top (
    input  wire       clk,
    input  wire       btnC,
    input  wire       btnU,
    input  wire       btnR,
    input  wire       btnD,
    input  wire [7:0] sw,
    output wire [7:0] led
);

    // Startup reset: hold the MAC in reset initially.
    reg [3:0] startup_count = 4'd0;

    always @(posedge clk) begin
        if (startup_count != 4'd15)
            startup_count <= startup_count + 1'b1;
    end

    wire startup_reset = (startup_count != 4'd15);

    reg [7:0] activation = 8'd0;
    reg signed [7:0] weight = 8'sd0;
    reg clear = 1'b0;
    reg enable = 1'b0;

    wire signed [31:0] accumulator;

    // Synchronize button inputs to the FPGA clock.
    reg [1:0] btnC_sync = 2'b00;
    reg [1:0] btnU_sync = 2'b00;
    reg [1:0] btnR_sync = 2'b00;
    reg [1:0] btnD_sync = 2'b00;

    always @(posedge clk) begin
        btnC_sync <= {btnC_sync[0], btnC};
        btnU_sync <= {btnU_sync[0], btnU};
        btnR_sync <= {btnR_sync[0], btnR};
        btnD_sync <= {btnD_sync[0], btnD};
    end

    // Edge detection: generate one action per press.
    reg btnC_prev = 1'b0;
    reg btnU_prev = 1'b0;
    reg btnR_prev = 1'b0;
    reg btnD_prev = 1'b0;

    always @(posedge clk) begin
        enable <= 1'b0;
        clear  <= 1'b0;

        btnC_prev <= btnC_sync[1];
        btnU_prev <= btnU_sync[1];
        btnR_prev <= btnR_sync[1];
        btnD_prev <= btnD_sync[1];

        if (btnC_sync[1] && !btnC_prev) begin
            clear <= 1'b1;
        end else if (btnU_sync[1] && !btnU_prev) begin
            activation <= sw;
        end else if (btnR_sync[1] && !btnR_prev) begin
            weight <= $signed(sw);
        end else if (btnD_sync[1] && !btnD_prev) begin
            enable <= 1'b1;
        end
    end

    mac_unit mac_inst (
        .clk(clk),
        .rst(startup_reset),
        .clear(clear),
        .enable(enable),
        .activation(activation),
        .weight(weight),
        .accumulator(accumulator)
    );

    assign led = accumulator[7:0];

endmodule
