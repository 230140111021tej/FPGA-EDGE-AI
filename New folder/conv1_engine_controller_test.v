
`timescale 1ns / 1ps

module conv1_engine #(
    parameter IMAGE_W = 5,
    parameter IMAGE_H = 5
) (
    input  wire clk,
    input  wire rst,
    input  wire start,

    output reg busy,
    output reg done,
    output reg out_valid,
    output reg [3:0] out_index,
    output reg [7:0] out_data
);

    reg [3:0] count;
    reg [1:0] state;

    localparam IDLE = 2'd0;
    localparam RUN  = 2'd1;

    always @(posedge clk) begin
        if (rst) begin
            busy      <= 1'b0;
            done      <= 1'b0;
            out_valid <= 1'b0;
            out_index <= 4'd0;
            out_data  <= 8'd0;
            count     <= 4'd0;
            state     <= IDLE;
        end else begin
            done      <= 1'b0;
            out_valid <= 1'b0;

            case (state)
                IDLE: begin
                    busy <= 1'b0;

                    if (start) begin
                        busy  <= 1'b1;
                        count <= 4'd0;
                        state <= RUN;
                    end
                end

                RUN: begin
                    out_valid <= 1'b1;
                    out_index <= count;
                    out_data  <= count;
                    count     <= count + 1'b1;

                    if (count == 4'd8) begin
                        busy  <= 1'b0;
                        done  <= 1'b1;
                        state <= IDLE;
                    end
                end

                default: begin
                    busy  <= 1'b0;
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
