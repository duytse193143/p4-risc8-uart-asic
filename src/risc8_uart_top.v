`timescale 1ns/1ps
// ============================================================================
// risc8_uart_top.v  -  TOP LEVEL: RISC8 CPU + ROM + RAM + UART
// ----------------------------------------------------------------------------
// Memory map (8-bit address from the CPU):
//   0x00 - 0x0F : data RAM (16 bytes)
//   0xF0        : UART TX data   (write)  -> starts sending the byte
//   0xF1        : UART status    (read)   -> bit0 = tx_busy, bit1 = rx_valid
//   0xF2        : UART RX data   (read)   -> received byte, clears rx_valid
//
// Chip pins: clk, rst_n, uart_rx, uart_tx, halted
// ============================================================================
module risc8_uart_top #(
    parameter CLKS_PER_BIT = 1736          // 200 MHz / 115200 baud
) (
    input  wire clk,
    input  wire rst_n,
    input  wire uart_rx,
    output wire uart_tx,
    output wire halted
);

    // ---------------- CPU ----------------
    wire [7:0]  pc;
    wire [15:0] instr;
    wire [7:0]  mem_addr, mem_wdata, mem_rdata;
    wire        mem_we, mem_re;

    risc8_core u_core (
        .clk       (clk),
        .rst_n     (rst_n),
        .pc_out    (pc),
        .instr_in  (instr),
        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_we    (mem_we),
        .mem_re    (mem_re),
        .mem_rdata (mem_rdata),
        .halted    (halted)
    );

    // ---------------- program ROM ----------------
    prog_rom u_rom (
        .addr (pc),
        .data (instr)
    );

    // ---------------- address decode ----------------
    wire sel_ram    = (mem_addr[7:4] == 4'h0);
    wire sel_txdata = (mem_addr == 8'hF0);
    wire sel_status = (mem_addr == 8'hF1);
    wire sel_rxdata = (mem_addr == 8'hF2);

    // ---------------- data RAM ----------------
    wire [7:0] ram_rdata;

    data_ram u_ram (
        .clk   (clk),
        .we    (mem_we && sel_ram),
        .addr  (mem_addr[3:0]),
        .wdata (mem_wdata),
        .rdata (ram_rdata)
    );

    // ---------------- UART transmitter ----------------
    wire tx_busy;

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_uart_tx (
        .clk   (clk),
        .rst_n (rst_n),
        .start (mem_we && sel_txdata),
        .data  (mem_wdata),
        .tx    (uart_tx),
        .busy  (tx_busy)
    );

    // ---------------- UART receiver + RX buffer ----------------
    wire [7:0] rx_byte;
    wire       rx_done;
    reg  [7:0] rx_buf;
    reg        rx_valid;

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_uart_rx (
        .clk   (clk),
        .rst_n (rst_n),
        .rx    (uart_rx),
        .data  (rx_byte),
        .done  (rx_done)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_buf   <= 8'h00;
            rx_valid <= 1'b0;
        end else if (rx_done) begin               // new byte arrived
            rx_buf   <= rx_byte;
            rx_valid <= 1'b1;
        end else if (mem_re && sel_rxdata) begin  // CPU read the byte
            rx_valid <= 1'b0;
        end
    end

    // ---------------- read data mux ----------------
    assign mem_rdata = sel_ram    ? ram_rdata :
                       sel_status ? {6'b000000, rx_valid, tx_busy} :
                       sel_rxdata ? rx_buf :
                                    8'h00;

endmodule