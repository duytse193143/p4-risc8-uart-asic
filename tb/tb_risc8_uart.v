// ============================================================================
// tb_risc8_uart.v  -  self-checking testbench for risc8_uart_top
// ----------------------------------------------------------------------------
// Checks:
//   1. After reset the CPU prints "OK!\r\n" on uart_tx
//   2. Bytes sent into uart_rx are echoed back on uart_tx
// Prints "TEST PASSED" or "TEST FAILED" at the end.
//
// RTL simulation (fast, 16 clocks per UART bit):
//   iverilog -g2005 -o sim.out tb/tb_risc8_uart.v src/*.v && vvp sim.out
// Gate-level simulation (netlist uses the real 1736 clocks per bit):
//   compile with -DGATE_LEVEL plus the netlist and the Sky130 cell models
// ============================================================================
`timescale 1ns/1ps

module tb_risc8_uart;

`ifdef GATE_LEVEL
    localparam CPB = 1736;      // netlist was built with the default value
`else
    localparam CPB = 16;        // short bit time for fast RTL simulation
`endif
    localparam CLK_PERIOD = 5.0;                 // 200 MHz
    localparam BIT_TIME   = CPB * CLK_PERIOD;    // ns per UART bit

    reg  clk     = 1'b0;
    reg  rst_n   = 1'b0;
    reg  uart_rx = 1'b1;                          // idle line is high
    wire uart_tx;
    wire halted;

`ifdef JITTER
    // D45 jitter demo: every half period is 2.5 ns +/- up to 0.3 ns (random).
    // The design still works in simulation: simulation checks function,
    // not timing. Timing margins for jitter are checked by STA instead.
    real    jit;
    real    last_rise, period, pmin, pmax;
    integer seed = 7, nper = 0;
    initial begin
        pmin = 100.0; pmax = 0.0; last_rise = -1.0;
        forever begin
            jit = ($random(seed) % 301) / 1000.0;     // -0.300 .. +0.300 ns
            #(CLK_PERIOD / 2.0 + jit) clk = ~clk;
            if (clk) begin
                if (last_rise >= 0.0) begin
                    period = $realtime - last_rise;
                    if (period < pmin) pmin = period;
                    if (period > pmax) pmax = period;
                    if (nper < 12) $display("JITTER period %0d = %0.3f ns", nper + 1, period);
                    nper = nper + 1;
                end
                last_rise = $realtime;
            end
        end
    end
`else
    always #(CLK_PERIOD / 2.0) clk = ~clk;
`endif

    // ---------------- device under test ----------------
`ifdef GATE_LEVEL
    risc8_uart_top dut (
`else
    risc8_uart_top #(.CLKS_PER_BIT(CPB)) dut (
`endif
        .clk     (clk),
        .rst_n   (rst_n),
        .uart_rx (uart_rx),
        .uart_tx (uart_tx),
        .halted  (halted)
    );

    // ---------------- UART monitor: decodes uart_tx ----------------
    reg [7:0] rx_fifo [0:63];
    integer   rx_count = 0;
    reg [7:0] b;
    integer   i;

    initial begin : monitor
        forever begin
            @(negedge uart_tx);                   // start bit begins
            #(BIT_TIME * 1.5);                    // middle of bit 0
            for (i = 0; i < 8; i = i + 1) begin
                b[i] = uart_tx;
                #(BIT_TIME);
            end
            if (uart_tx !== 1'b1)
                $display("[%0t] ERROR: bad stop bit", $time);
            rx_fifo[rx_count] = b;
            rx_count = rx_count + 1;
            $display("[%0t] uart_tx -> 0x%02h '%s'", $time, b,
                     (b >= 8'h20 && b < 8'h7F) ? b : 8'h2E);
        end
    end

    // ---------------- task: send one byte into uart_rx ----------------
    task send_byte(input [7:0] data);
        integer k;
        begin
            uart_rx = 1'b0;                       // start bit
            #(BIT_TIME);
            for (k = 0; k < 8; k = k + 1) begin
                uart_rx = data[k];
                #(BIT_TIME);
            end
            uart_rx = 1'b1;                       // stop bit
            #(BIT_TIME);
        end
    endtask

    // ---------------- task: wait until n bytes were received ----------------
    task wait_bytes(input integer n);
        integer guard;
        begin
            guard = 0;
            while (rx_count < n && guard < 40) begin
                #(BIT_TIME * 10);
                guard = guard + 1;
            end
        end
    endtask

    // ---------------- test sequence ----------------
    integer errors = 0;
    reg [7:0] expected [0:6];

    task check(input integer idx);
        begin
            if (rx_count <= idx) begin
                $display("ERROR: byte %0d never arrived", idx);
                errors = errors + 1;
            end else if (rx_fifo[idx] !== expected[idx]) begin
                $display("ERROR: byte %0d = 0x%02h, expected 0x%02h",
                         idx, rx_fifo[idx], expected[idx]);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
`ifndef GATE_LEVEL
        $dumpfile("tb_risc8_uart.vcd");    // waveform for GTKWave (RTL only;
        $dumpvars(0, tb_risc8_uart);       // gate-level dump would be ~1 GB)
`endif

        expected[0] = "O";   expected[1] = "K";   expected[2] = "!";
        expected[3] = 8'h0D; expected[4] = 8'h0A;   // "\r\n"
        expected[5] = "A";   expected[6] = "z";     // echo test

        // reset
        #(CLK_PERIOD * 10);
        rst_n = 1'b1;

        // 1. boot message
        wait_bytes(5);
        for (i = 0; i < 5; i = i + 1) check(i);

        // 2. echo test
        send_byte("A");
        wait_bytes(6);
        send_byte("z");
        wait_bytes(7);
        check(5);
        check(6);

        if (halted) begin
            $display("ERROR: CPU halted unexpectedly");
            errors = errors + 1;
        end

`ifdef JITTER
        $display("JITTER summary: %0d periods, shortest %0.3f ns, longest %0.3f ns (ideal 5.000)", nper, pmin, pmax);
`endif
        if (errors == 0) $display("TEST PASSED");
        else             $display("TEST FAILED (%0d errors)", errors);
        $finish;
    end

    // safety timeout
    initial begin
        #(BIT_TIME * 10 * 200);
        $display("TEST FAILED (timeout)");
        $finish;
    end

endmodule