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
    reg        clk;
    reg        we_a;
    reg [16:0] addr_a;
    reg [11:0] din_a;
    reg [16:0] addr_b;
    wire[11:0] dout_b;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    frame_buffer dut (
        .clk    (clk),
        .we_a   (we_a),
        .addr_a (addr_a),
        .din_a  (din_a),
        .addr_b (addr_b),
        .dout_b (dout_b)
    );

    // -------------------------------------------------------------------------
    // 100MHz system clock
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;   // 10ns period

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
        // Test 1: Write several pixels, then read them back one cycle later
        // ------------------------------------------------------------------
        $display("--- Test 1: sequential write then read-back ---");

        @(posedge clk); #1;
        we_a = 1; addr_a = 17'd0;     din_a = 12'hABC;
        @(posedge clk); #1;
        we_a = 1; addr_a = 17'd1;     din_a = 12'hDEF;
        @(posedge clk); #1;
        we_a = 1; addr_a = 17'd76799; din_a = 12'hF0F;  // last valid address
        @(posedge clk); #1;
        we_a = 0;

        // Read addr 0: set addr_b, wait one clock, then sample
        addr_b = 17'd0;
        @(posedge clk); #1;
        check(0, 12'hABC, dout_b);

        addr_b = 17'd1;
        @(posedge clk); #1;
        check(1, 12'hDEF, dout_b);

        addr_b = 17'd76799;
        @(posedge clk); #1;
        check(76799, 12'hF0F, dout_b);

        // ------------------------------------------------------------------
        // Test 2: Simultaneous read/write to DIFFERENT addresses
        // (typical operation: frame_capture writing while VGA is reading)
        // ------------------------------------------------------------------
        $display("--- Test 2: simultaneous read/write different addresses ---");

        // Pre-load addr 100
        we_a = 1; addr_a = 17'd100; din_a = 12'h123;
        @(posedge clk); #1;
        we_a = 0;

        // On the same clock: write addr 200, read addr 100
        addr_b = 17'd100;
        we_a   = 1; addr_a = 17'd200; din_a = 12'h456;
        @(posedge clk); #1;
        we_a = 0;
        // dout_b now holds mem[100] captured at the clock edge
        check(100, 12'h123, dout_b);

        // Read back addr 200
        addr_b = 17'd200;
        @(posedge clk); #1;
        check(200, 12'h456, dout_b);

        // ------------------------------------------------------------------
        // Test 3: Frame corner addresses
        // Row 0 col 319 → addr = 319
        // Row 239 col 0 → addr = 239*320 = 76480
        // ------------------------------------------------------------------
        $display("--- Test 3: frame corner addresses ---");

        we_a = 1; addr_a = 17'd319;   din_a = 12'hCAF;
        @(posedge clk); #1;
        we_a = 1; addr_a = 17'd76480; din_a = 12'hBEE;
        @(posedge clk); #1;
        we_a = 0;

        addr_b = 17'd319;
        @(posedge clk); #1;
        check(319, 12'hCAF, dout_b);

        addr_b = 17'd76480;
        @(posedge clk); #1;
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
