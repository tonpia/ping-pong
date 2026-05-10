`timescale 1ns / 1ps
// =============================================================================
// tb_frame_buffer.v — Testbench for frame_buffer
//
// Tests:
//   1. Sequential writes then read-back (verifies 1-cycle read latency)
//   2. Simultaneous read/write to different addresses
//   3. Frame corner addresses (addr 0, 319, 76480, 76799)
// =============================================================================
module tb_frame_buffer;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    reg        clk_a;       // 100 MHz write-side clock
    reg        clk_b;       //  25 MHz read-side clock
    reg        we_a;
    reg [16:0] addr_a;
    reg [11:0] din_a;
    reg [16:0] addr_b;
    wire[11:0] dout_b;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    frame_buffer dut (
        .clk_a  (clk_a),
        .clk_b  (clk_b),
        .we_a   (we_a),
        .addr_a (addr_a),
        .din_a  (din_a),
        .addr_b (addr_b),
        .dout_b (dout_b)
    );

    // -------------------------------------------------------------------------
    // Clocks: 100 MHz write port, 25 MHz read port
    // -------------------------------------------------------------------------
    initial clk_a = 0;
    always #5  clk_a = ~clk_a;   // 10 ns period -> 100 MHz

    initial clk_b = 0;
    always #20 clk_b = ~clk_b;   // 40 ns period ->  25 MHz

    // -------------------------------------------------------------------------
    // Pass/fail tracking
    // -------------------------------------------------------------------------
    integer errors;

    task check;
        input [16:0] addr;
        input [11:0] expected;
        input [11:0] got;
        begin
            if (got !== expected) begin
                $display("FAIL  addr=%0d  expected=%03h  got=%03h", addr, expected, got);
                errors = errors + 1;
            end else begin
                $display("PASS  addr=%0d  value=%03h", addr, got);
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Test sequence
    // -------------------------------------------------------------------------
    initial begin
        errors = 0;
        we_a   = 0;
        addr_a = 0;
        din_a  = 0;
        addr_b = 0;

        // ------------------------------------------------------------------
        // Test 1: Write several pixels on clk_a, then read them back on clk_b
        // ------------------------------------------------------------------
        $display("--- Test 1: sequential write (clk_a) then read-back (clk_b) ---");

        @(posedge clk_a); #1;
        we_a = 1; addr_a = 17'd0;     din_a = 12'hABC;
        @(posedge clk_a); #1;
        we_a = 1; addr_a = 17'd1;     din_a = 12'hDEF;
        @(posedge clk_a); #1;
        we_a = 1; addr_a = 17'd76799; din_a = 12'hF0F;  // last valid address
        @(posedge clk_a); #1;
        we_a = 0;

        // Read addr 0: set addr_b, wait one clk_b edge, then sample
        addr_b = 17'd0;
        @(posedge clk_b); #1;
        check(0, 12'hABC, dout_b);

        addr_b = 17'd1;
        @(posedge clk_b); #1;
        check(1, 12'hDEF, dout_b);

        addr_b = 17'd76799;
        @(posedge clk_b); #1;
        check(76799, 12'hF0F, dout_b);

        // ------------------------------------------------------------------
        // Test 2: Concurrent write (clk_a) and read (clk_b) on DIFFERENT addrs
        // (typical operation: frame_capture writing while VGA is reading)
        // ------------------------------------------------------------------
        $display("--- Test 2: simultaneous read/write different addresses ---");

        // Pre-load addr 100
        @(posedge clk_a); #1;
        we_a = 1; addr_a = 17'd100; din_a = 12'h123;
        @(posedge clk_a); #1;
        we_a = 0;

        // Begin concurrent: write addr 200 on clk_a, read addr 100 on clk_b
        addr_b = 17'd100;
        we_a   = 1; addr_a = 17'd200; din_a = 12'h456;
        @(posedge clk_b); #1;
        check(100, 12'h123, dout_b);
        // 40 ns of clk_b waiting = 4 clk_a edges, so the addr-200 write committed
        we_a = 0;

        // Read back addr 200 on clk_b
        addr_b = 17'd200;
        @(posedge clk_b); #1;
        check(200, 12'h456, dout_b);

        // ------------------------------------------------------------------
        // Test 3: Frame corner addresses
        // Row 0 col 319 → addr = 319
        // Row 239 col 0 → addr = 239*320 = 76480
        // ------------------------------------------------------------------
        $display("--- Test 3: frame corner addresses ---");

        @(posedge clk_a); #1;
        we_a = 1; addr_a = 17'd319;   din_a = 12'hCAF;
        @(posedge clk_a); #1;
        we_a = 1; addr_a = 17'd76480; din_a = 12'hBEE;
        @(posedge clk_a); #1;
        we_a = 0;

        addr_b = 17'd319;
        @(posedge clk_b); #1;
        check(319, 12'hCAF, dout_b);

        addr_b = 17'd76480;
        @(posedge clk_b); #1;
        check(76480, 12'hBEE, dout_b);

        // ------------------------------------------------------------------
        // Summary
        // ------------------------------------------------------------------
        if (errors == 0)
            $display("=== ALL TESTS PASSED ===");
        else
            $display("=== %0d TEST(S) FAILED ===", errors);

        $finish;
    end

    // -------------------------------------------------------------------------
    // Waveform dump
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_frame_buffer.vcd");
        $dumpvars(0, tb_frame_buffer);
    end

endmodule
