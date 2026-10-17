module mac_io_test (
    input  wire [7:0] sw,
    output wire [7:0] led
);
    assign led = sw;
endmodule
