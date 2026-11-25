`timescale 1ns/1ps
// ============================================================================
// uart_rx.v  -  UART receiver, 8N1
// ----------------------------------------------------------------------------
//  * rx is first passed through a 2-flip-flop synchronizer (it is asynchronous)
//  * the start bit is checked in its middle, then each data bit is sampled
//    in its middle (every CLKS_PER_BIT clocks)
//  * 'done' pulses for 1 clock when a byte with a valid stop bit is received
// ============================================================================
module uart_rx #(
    parameter CLKS_PER_BIT = 1736
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,        // serial input (asynchronous)
    output reg  [7:0] data,      // received byte
    output reg        done       // 1-cycle pulse: 'data' is valid
);

    localparam S_IDLE  = 2'd0, S_START = 2'd1, S_DATA = 2'd2, S_STOP = 2'd3;
    localparam HALF_BIT = (CLKS_PER_BIT - 1) / 2;

    // ---------------- 2-FF synchronizer ----------------
    reg rx_meta, rx_sync;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
        end
    end

    // ---------------- receive FSM ----------------
    reg [1:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  shreg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= S_IDLE;
            clk_cnt <= 16'd0;
            bit_idx <= 3'd0;
            shreg   <= 8'h00;
            data    <= 8'h00;
            done    <= 1'b0;
        end else begin
            done <= 1'b0;
            case (state)
                S_IDLE: begin
                    clk_cnt <= 16'd0;
                    if (rx_sync == 1'b0)              // falling edge = start bit
                        state <= S_START;
                end
                S_START: begin
                    if (clk_cnt == HALF_BIT) begin    // middle of start bit
                        clk_cnt <= 16'd0;
                        bit_idx <= 3'd0;
                        if (rx_sync == 1'b0)
                            state <= S_DATA;
                        else
                            state <= S_IDLE;          // glitch, not a start bit
                    end else
                        clk_cnt <= clk_cnt + 16'd1;
                end
                S_DATA: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin   // middle of data bit
                        clk_cnt <= 16'd0;
                        shreg   <= {rx_sync, shreg[7:1]};    // LSB first
                        if (bit_idx == 3'd7)
                            state <= S_STOP;
                        else
                            bit_idx <= bit_idx + 3'd1;
                    end else
                        clk_cnt <= clk_cnt + 16'd1;
                end
                S_STOP: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin   // middle of stop bit
                        clk_cnt <= 16'd0;
                        state   <= S_IDLE;
                        if (rx_sync == 1'b1) begin           // valid stop bit
                            data <= shreg;
                            done <= 1'b1;
                        end
                    end else
                        clk_cnt <= clk_cnt + 16'd1;
                end
            endcase
        end
    end

endmodule