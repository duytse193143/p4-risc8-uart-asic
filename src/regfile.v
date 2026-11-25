`timescale 1ns/1ps
// ============================================================================
// regfile.v  -  8 x 8-bit register file (r0 .. r7)
// ----------------------------------------------------------------------------
//  * r0 always reads as 0 (writes to r0 are ignored), like RISC-V x0
//  * 2 read ports (combinational), 1 write port (on rising clock edge)
//  * every register has an asynchronous active-low reset
// Written with explicit registers (no array) so every flip-flop is easy to
// find in the synthesis and STA reports.
// ============================================================================
module regfile (
    input  wire       clk,
    input  wire       rst_n,
    // write port
    input  wire       we,
    input  wire [2:0] waddr,
    input  wire [7:0] wdata,
    // read port A
    input  wire [2:0] raddr_a,
    output reg  [7:0] rdata_a,
    // read port B
    input  wire [2:0] raddr_b,
    output reg  [7:0] rdata_b
);

    reg [7:0] r1, r2, r3, r4, r5, r6, r7;

    // ---------------- write port ----------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r1 <= 8'h00; r2 <= 8'h00; r3 <= 8'h00; r4 <= 8'h00;
            r5 <= 8'h00; r6 <= 8'h00; r7 <= 8'h00;
        end else if (we) begin
            case (waddr)
                3'd1: r1 <= wdata;
                3'd2: r2 <= wdata;
                3'd3: r3 <= wdata;
                3'd4: r4 <= wdata;
                3'd5: r5 <= wdata;
                3'd6: r6 <= wdata;
                3'd7: r7 <= wdata;
                default: ;            // r0: write ignored
            endcase
        end
    end

    // ---------------- read port A ----------------
    always @(*) begin
        case (raddr_a)
            3'd1: rdata_a = r1;
            3'd2: rdata_a = r2;
            3'd3: rdata_a = r3;
            3'd4: rdata_a = r4;
            3'd5: rdata_a = r5;
            3'd6: rdata_a = r6;
            3'd7: rdata_a = r7;
            default: rdata_a = 8'h00; // r0
        endcase
    end

    // ---------------- read port B ----------------
    always @(*) begin
        case (raddr_b)
            3'd1: rdata_b = r1;
            3'd2: rdata_b = r2;
            3'd3: rdata_b = r3;
            3'd4: rdata_b = r4;
            3'd5: rdata_b = r5;
            3'd6: rdata_b = r6;
            3'd7: rdata_b = r7;
            default: rdata_b = 8'h00; // r0
        endcase
    end

endmodule