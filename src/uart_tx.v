`timescale 1ns/1ps
// ============================================================================
// uart_tx.v  -  UART transmitter, 8 data bits, no parity, 1 stop bit (8N1)
// ----------------------------------------------------------------------------
// Frame on the wire (LSB first):
//   idle=1 | start=0 | d0 d1 d2 d3 d4 d5 d6 d7 | stop=1 | idle=1
// CLKS_PER_BIT = clock frequency / baud rate
//   200 MHz / 115200 baud = 1736
// ============================================================================
module uart_tx #(
    parameter CLKS_PER_BIT = 1736
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,     // 1-cycle pulse: send 'data'
    input  wire [7:0] data,
    output reg        tx,        // serial output
    output wire       busy       // 1 while a frame is being sent
);

    localparam S_IDLE  = 2'd0, S_START = 2'd1, S_DATA = 2'd2, S_STOP = 2'd3;

    reg [1:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  shreg;

    wire bit_done = (clk_cnt == CLKS_PER_BIT - 1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= S_IDLE;
            clk_cnt <= 16'd0;
            bit_idx <= 3'd0;
            shreg   <= 8'h00;
            tx      <= 1'b1;
        end else begin
            case (state)
                S_IDLE: begin
                    tx      <= 1'b1;
                    clk_cnt <= 16'd0;
                    if (start) begin
                        shreg <= data;
                        state <= S_START;
                    end
                end
                S_START: begin
                    tx <= 1'b0;                       // start bit
                    if (bit_done) begin
                        clk_cnt <= 16'd0;
                        bit_idx <= 3'd0;
                        state   <= S_DATA;
                    end else
                        clk_cnt <= clk_cnt + 16'd1;
                end
                S_DATA: begin
                    tx <= shreg[0];                   // LSB first
                    if (bit_done) begin
                        clk_cnt <= 16'd0;
                        shreg   <= {1'b0, shreg[7:1]};
                        if (bit_idx == 3'd7)
                            state <= S_STOP;
                        else
                            bit_idx <= bit_idx + 3'd1;
                    end else
                        clk_cnt <= clk_cnt + 16'd1;
                end
                S_STOP: begin
                    tx <= 1'b1;                       // stop bit
                    if (bit_done) begin
                        clk_cnt <= 16'd0;
                        state   <= S_IDLE;
                    end else
                        clk_cnt <= clk_cnt + 16'd1;
                end
            endcase
        end
    end

    assign busy = (state != S_IDLE);

endmodule