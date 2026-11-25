`timescale 1ns/1ps
// ============================================================================
// risc8_core.v  -  simple 8-bit RISC CPU (3 cycles: FETCH, DECODE, EXECUTE)
// ----------------------------------------------------------------------------
// Instruction format (16 bits):
//   R-type : [15:12] op | [11:9] rd | [8:6] rs1 | [5:3] rs2 | [2:0] 000
//   I-type : [15:12] op | [11:9] rd | [8]   0   | [7:0] imm8
//   M-type : [15:12] op | [11:9] rd | [8:6] rs1 | [5:0] 000000
//   J-type : [15:12] op | [11:9] rd | [8]   0   | [7:0] addr8
//
// Instruction set:
//   0 NOP                       8 LDI  rd, imm      rd = imm
//   1 ADD  rd, rs1, rs2         9 ADDI rd, imm      rd = rd + imm
//   2 SUB  rd, rs1, rs2         A LD   rd, [rs1]    rd = mem[rs1]
//   3 AND  rd, rs1, rs2         B ST   rd, [rs1]    mem[rs1] = rd
//   4 OR   rd, rs1, rs2         C BEQZ rd, addr     if (rd == 0) pc = addr
//   5 XOR  rd, rs1, rs2         D BNEZ rd, addr     if (rd != 0) pc = addr
//   6 SHL  rd, rs1              E JMP  addr         pc = addr
//   7 SHR  rd, rs1              F HALT              stop the CPU
//
// Each instruction takes 3 clock cycles:
//   FETCH   : IR <= ROM[PC], PC <= PC + 1
//   DECODE  : read the register file, latch operands into OPA / OPB
//   EXECUTE : ALU / memory / branch using OPA, OPB; write the result
// Registering the operands splits the long path (decode -> register read ->
// ALU -> write back) into two short ones, so the CPU meets 200 MHz.
// ============================================================================
module risc8_core (
    input  wire        clk,
    input  wire        rst_n,
    // instruction ROM interface
    output wire [7:0]  pc_out,
    input  wire [15:0] instr_in,
    // data bus (RAM + UART registers)
    output wire [7:0]  mem_addr,
    output wire [7:0]  mem_wdata,
    output wire        mem_we,
    output wire        mem_re,
    input  wire [7:0]  mem_rdata,
    // status
    output wire        halted
);

    // ---------------- opcodes ----------------
    // (all listed for documentation; some are only used by the ALU)
    /* verilator lint_off UNUSEDPARAM */
    localparam OP_NOP  = 4'h0, OP_ADD  = 4'h1, OP_SUB  = 4'h2, OP_AND  = 4'h3,
               OP_OR   = 4'h4, OP_XOR  = 4'h5, OP_SHL  = 4'h6, OP_SHR  = 4'h7,
               OP_LDI  = 4'h8, OP_ADDI = 4'h9, OP_LD   = 4'hA, OP_ST   = 4'hB,
               OP_BEQZ = 4'hC, OP_BNEZ = 4'hD, OP_JMP  = 4'hE, OP_HALT = 4'hF;
    /* verilator lint_on UNUSEDPARAM */

    // ---------------- states ----------------
    localparam S_FETCH = 2'd0, S_DECODE = 2'd1, S_EXEC = 2'd2, S_HALT = 2'd3;

    reg  [1:0]  state;
    reg  [7:0]  pc;
    reg  [15:0] ir;
    reg  [7:0]  opa;          // operand A, latched in DECODE
    reg  [7:0]  opb;          // operand B, latched in DECODE

    // ---------------- instruction fields ----------------
    wire [3:0] op   = ir[15:12];
    wire [2:0] rd   = ir[11:9];
    wire [2:0] rs1  = ir[8:6];
    wire [2:0] rs2  = ir[5:3];
    wire [7:0] imm  = ir[7:0];

    wire exec = (state == S_EXEC);

    // ---------------- register file ----------------
    // Port A always reads rs1.
    // Port B reads rs2 for R-type ops (1..7), otherwise rd
    // (needed by ADDI, ST data, BEQZ, BNEZ).
    wire       is_rtype = (op >= OP_ADD) && (op <= OP_SHR);
    wire [2:0] raddr_b  = is_rtype ? rs2 : rd;
    wire [7:0] rdata_a, rdata_b;

    wire       reg_we   = exec && (op >= OP_ADD) && (op <= OP_LD);
    wire [7:0] alu_y;
    wire [7:0] reg_wdata = (op == OP_LD) ? mem_rdata : alu_y;

    regfile u_regfile (
        .clk     (clk),
        .rst_n   (rst_n),
        .we      (reg_we),
        .waddr   (rd),
        .wdata   (reg_wdata),
        .raddr_a (rs1),
        .rdata_a (rdata_a),
        .raddr_b (raddr_b),
        .rdata_b (rdata_b)
    );

    // ---------------- operand select (used in DECODE) ----------------
    //   OPA = rs1        (ADDI: rd)        -> ALU input A, memory address
    //   OPB = rs2 or rd  (LDI/ADDI: imm)   -> ALU input B, store data, branch test
    wire [7:0] opa_next = (op == OP_ADDI) ? rdata_b : rdata_a;
    wire [7:0] opb_next = ((op == OP_LDI) || (op == OP_ADDI)) ? imm : rdata_b;

    // ---------------- ALU (used in EXECUTE) ----------------
    alu u_alu (
        .op (op),
        .a  (opa),
        .b  (opb),
        .y  (alu_y)
    );

    // ---------------- data bus ----------------
    assign mem_addr  = opa;                     // address = rs1
    assign mem_wdata = opb;                     // store data = rd
    assign mem_we    = exec && (op == OP_ST);
    assign mem_re    = exec && (op == OP_LD);

    // ---------------- branch decision ----------------
    wire rd_is_zero  = (opb == 8'h00);
    wire take_branch = (op == OP_JMP) ||
                       ((op == OP_BEQZ) &&  rd_is_zero) ||
                       ((op == OP_BNEZ) && !rd_is_zero);

    // ---------------- control FSM ----------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_FETCH;
            pc    <= 8'h00;
            ir    <= 16'h0000;
            opa   <= 8'h00;
            opb   <= 8'h00;
        end else begin
            case (state)
                S_FETCH: begin
                    ir    <= instr_in;
                    pc    <= pc + 8'd1;
                    state <= S_DECODE;
                end
                S_DECODE: begin
                    opa   <= opa_next;
                    opb   <= opb_next;
                    state <= S_EXEC;
                end
                S_EXEC: begin
                    if (take_branch)
                        pc <= imm;
                    if (op == OP_HALT)
                        state <= S_HALT;
                    else
                        state <= S_FETCH;
                end
                default: state <= S_HALT;      // S_HALT: stay here forever
            endcase
        end
    end

    assign pc_out = pc;
    assign halted = (state == S_HALT);

endmodule