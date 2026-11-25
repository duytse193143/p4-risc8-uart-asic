`timescale 1ns/1ps
// ============================================================================
// alu.v  -  8-bit ALU for the RISC8 CPU
// ----------------------------------------------------------------------------
// Pure combinational logic. The opcode selects the operation.
// Opcode values match the instruction set in risc8_core.v.
// ============================================================================
module alu (
    input  wire [3:0] op,   // opcode = instruction bits [15:12]
    input  wire [7:0] a,    // operand A
    input  wire [7:0] b,    // operand B
    output reg  [7:0] y     // result
);

    always @(*) begin
        case (op)
            4'h1:    y = a + b;              // ADD
            4'h2:    y = a - b;              // SUB
            4'h3:    y = a & b;              // AND
            4'h4:    y = a | b;              // OR
            4'h5:    y = a ^ b;              // XOR
            4'h6:    y = {a[6:0], 1'b0};     // SHL  (shift left by 1)
            4'h7:    y = {1'b0, a[7:1]};     // SHR  (shift right by 1)
            4'h8:    y = b;                  // LDI  (pass immediate)
            4'h9:    y = a + b;              // ADDI (rd + imm)
            default: y = 8'h00;
        endcase
    end

endmodule