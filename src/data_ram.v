`timescale 1ns/1ps
// ============================================================================
// data_ram.v  -  16 x 8-bit data RAM built from flip-flops
// ----------------------------------------------------------------------------
//  * synchronous write, asynchronous (combinational) read
//  * small on purpose: no SRAM macro is needed, so the PnR flow stays simple
// ============================================================================
module data_ram (
    input  wire       clk,
    input  wire       we,
    input  wire [3:0] addr,
    input  wire [7:0] wdata,
    output wire [7:0] rdata
);

    reg [7:0] mem [0:15];

    always @(posedge clk) begin
        if (we)
            mem[addr] <= wdata;
    end

    assign rdata = mem[addr];

endmodule