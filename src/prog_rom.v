// ============================================================================
// prog_rom.v  -  program ROM for the RISC8 CPU (256 x 16 bits)
// ----------------------------------------------------------------------------
// The CPU's program, written directly as 16-bit numbers (one per address).
// The CPU reads address 'addr' (= its PC) and gets the instruction 'data'.
//
// How to read one instruction, e.g. 16'h8EF0:
//     8      E F 0
//     |      `-+-'
//   opcode   the rest:  1110 1111 0000 -> rd = 111 (r7), value = 0xF0
//   So 16'h8EF0 means "r7 = 0xF0".
//
// Bits:  [15:12] opcode | [11:9] rd | [8:6] rs1 | [5:3] rs2   (register ops)
//        [15:12] opcode | [11:9] rd | [7:0] value or address  (LDI/ADDI/branch)
// Opcodes (same as risc8_core.v):
//   1 ADD  2 SUB  3 AND  4 OR  5 XOR  6 SHL  7 SHR  8 LDI (load value)
//   9 ADDI A LD (read memory)  B ST (write memory)  C BEQZ  D BNEZ  E JMP  F HALT
//
// UART addresses: 0xF0 = TX data, 0xF1 = status (bit0 tx_busy, bit1 rx_valid),
//                 0xF2 = RX data.   RAM: 0x00 - 0x0F.
// ============================================================================
`timescale 1ns/1ps
module prog_rom (
    input  wire [7:0]  addr,
    output reg  [15:0] data
);

    always @(*) begin
        case (addr)

            // ---- Part 1: set up the UART addresses ----
            8'h00: data = 16'h8EF0;   // r7 = 0xF0   (address of UART TX data)
            8'h01: data = 16'h8CF1;   // r6 = 0xF1   (address of UART status)
            8'h02: data = 16'h8AF2;   // r5 = 0xF2   (address of UART RX data)
            8'h03: data = 16'h8600;   // r3 = 0
            8'h04: data = 16'h9601;   // r3 = r3 + 1 = 1   (mask for the tx_busy bit)

            // ---- Part 2: send "OK!\r\n" (each character uses a different ALU operation) ----
            // 'O' with ADD
            8'h05: data = 16'h8227;   // r1 = 0x27
            8'h06: data = 16'h8428;   // r2 = 0x28
            8'h07: data = 16'h1850;   // r4 = r1 + r2 = 0x4F = 'O'
            8'h08: data = 16'hA580;   // r2 = UART status            <- wait here
            8'h09: data = 16'h3498;   // r2 = r2 & r3   (keep only tx_busy)
            8'h0A: data = 16'hD408;   // if r2 != 0 go to 0x08   (UART busy: wait)
            8'h0B: data = 16'hB9C0;   // send r4 to UART TX   ('O')
            // 'K' with SUB
            8'h0C: data = 16'h8250;   // r1 = 0x50
            8'h0D: data = 16'h8405;   // r2 = 0x05
            8'h0E: data = 16'h2850;   // r4 = r1 - r2 = 0x4B = 'K'
            8'h0F: data = 16'hA580;   // r2 = UART status            <- wait here
            8'h10: data = 16'h3498;   // r2 = r2 & r3   (keep only tx_busy)
            8'h11: data = 16'hD40F;   // if r2 != 0 go to 0x0F
            8'h12: data = 16'hB9C0;   // send r4 to UART TX   ('K')
            // '!' with SHR (shift right)
            8'h13: data = 16'h8242;   // r1 = 0x42
            8'h14: data = 16'h7840;   // r4 = r1 >> 1 = 0x21 = '!'
            8'h15: data = 16'hA580;   // r2 = UART status            <- wait here
            8'h16: data = 16'h3498;   // r2 = r2 & r3
            8'h17: data = 16'hD415;   // if r2 != 0 go to 0x15
            8'h18: data = 16'hB9C0;   // send r4 to UART TX   ('!')
            // carriage return with OR
            8'h19: data = 16'h8208;   // r1 = 0x08
            8'h1A: data = 16'h8405;   // r2 = 0x05
            8'h1B: data = 16'h4850;   // r4 = r1 | r2 = 0x0D = carriage return
            8'h1C: data = 16'hA580;   // r2 = UART status            <- wait here
            8'h1D: data = 16'h3498;   // r2 = r2 & r3
            8'h1E: data = 16'hD41C;   // if r2 != 0 go to 0x1C
            8'h1F: data = 16'hB9C0;   // send r4 to UART TX   (\r)
            // new line with XOR
            8'h20: data = 16'h820F;   // r1 = 0x0F
            8'h21: data = 16'h8405;   // r2 = 0x05
            8'h22: data = 16'h5850;   // r4 = r1 ^ r2 = 0x0A = new line
            8'h23: data = 16'hA580;   // r2 = UART status            <- wait here
            8'h24: data = 16'h3498;   // r2 = r2 & r3
            8'h25: data = 16'hD423;   // if r2 != 0 go to 0x23
            8'h26: data = 16'hB9C0;   // send r4 to UART TX   (\n)

            // ---- Part 3: echo - wait for a byte on RX, store it in RAM, send it back on TX ----
            8'h27: data = 16'h8201;   // r1 = 1                      <- ECHO LOOP starts here
            8'h28: data = 16'h6240;   // r1 = r1 << 1 = 2   (mask for the rx_valid bit)
            8'h29: data = 16'hA580;   // r2 = UART status
            8'h2A: data = 16'h3488;   // r2 = r2 & r1   (keep only rx_valid)
            8'h2B: data = 16'hC427;   // if r2 == 0 go to 0x27   (nothing received yet)
            8'h2C: data = 16'hA940;   // r4 = received byte   (reading it clears rx_valid)
            8'h2D: data = 16'hB800;   // RAM[0] = r4   (r0 is always 0)
            8'h2E: data = 16'hA800;   // r4 = RAM[0]   (read it back from RAM)
            8'h2F: data = 16'hA580;   // r2 = UART status            <- wait here
            8'h30: data = 16'h3498;   // r2 = r2 & r3   (keep only tx_busy)
            8'h31: data = 16'hD42F;   // if r2 != 0 go to 0x2F
            8'h32: data = 16'hB9C0;   // send r4 to UART TX   (echo the byte back)
            8'h33: data = 16'hE027;   // go to 0x27   (repeat forever)

            default: data = 16'h0000;   // empty address: NOP (do nothing)
        endcase
    end

endmodule