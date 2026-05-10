// =============================================================================
// tb_vga_sync.v
// Testbench for VGA timing controller (vga_sync.v)
// Verifies:
//   1. HSYNC period = 800 pixel clocks
//   2. HSYNC pulse width = 96 pixel clocks
//   3. VSYNC period = 525 lines (525 * 800 = 420,000 clocks)
//   4. VSYNC pulse width = 2 lines (1,600 clocks)
//   5. video_active HIGH only when pixel_x < 640 AND pixel_y < 480
// =============================================================================

`timescale 1ns / 1ps

module tb_vga_sync;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    reg         clk;
    reg         reset;
    wire        hsync;
    wire        vsync;
    wire [9:0]  pixel_x;
    wire [9:0]  pixel_y;
    wire        video_active;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    vga_sync dut (
        .clk          (clk),
        .reset        (reset),
        .hsync        (hsync),
        .vsync        (vsync),
        .pixel_x      (pixel_x),
        .pixel_y      (pixel_y),
        .video_active (video_active)
    );

    // -------------------------------------------------------------------------
    // 25MHz pixel clock (40ns period)
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #20 clk = ~clk;

    // -------------------------------------------------------------------------
    // Test variables
    // -------------------------------------------------------------------------
    integer errors = 0;
    integer clk_count;
    integer i;

    // For edge detection
    reg hsync_prev, vsync_prev;

    // Measurement storage
    integer hsync_rise_time, hsync_fall_time;
    integer hsync_period_start;
    integer hsync_pulse_width;
    integer hsync_period;
    integer hsync_periods_checked;

    integer vsync_rise_time, vsync_fall_time;
    integer vsync_period_start;
    integer vsync_pulse_width;
    integer vsync_period;

    // -------------------------------------------------------------------------
    // Main test sequence
    // -------------------------------------------------------------------------
    initial begin
        $display("=== VGA Sync Testbench Start ===");

        // Initialize
        reset = 1;
        hsync_prev = 1;
        vsync_prev = 1;
        hsync_periods_checked = 0;
        hsync_period_start = -1;
        vsync_period_start = -1;
        clk_count = 0;

        // Release reset after a few clocks
        repeat (5) @(posedge clk);
        reset = 0;
        $display("[%0t] Reset released", $time);

        // =====================================================================
        // TEST 1: Run for 2 full frames and measure timing
        // 2 frames = 2 * 525 * 800 = 840,000 clocks
        // Add margin for reset settling
        // =====================================================================
        fork
            // Clock counter
            begin
                forever begin
                    @(posedge clk);
                    clk_count = clk_count + 1;
                end
            end

            // HSYNC measurement: detect falling/rising edges (active-low sync)
            // HSYNC active-low: pulse is the LOW period
            begin
                forever begin
                    @(posedge clk);
                    // Falling edge of hsync = start of sync pulse
                    if (hsync_prev == 1 && hsync == 0) begin
                        hsync_fall_time = clk_count;
                        if (hsync_period_start >= 0) begin
                            hsync_period = hsync_fall_time - hsync_period_start;
                            if (hsync_period != 800) begin
                                $display("[ERROR] HSYNC period = %0d clocks (expected 800) at clk %0d",
                                         hsync_period, clk_count);
                                errors = errors + 1;
                            end
                            hsync_periods_checked = hsync_periods_checked + 1;
                        end
                        hsync_period_start = hsync_fall_time;
                    end
                    // Rising edge of hsync = end of sync pulse
                    if (hsync_prev == 0 && hsync == 1) begin
                        hsync_rise_time = clk_count;
                        hsync_pulse_width = hsync_rise_time - hsync_fall_time;
                        if (hsync_pulse_width != 96) begin
                            $display("[ERROR] HSYNC pulse width = %0d clocks (expected 96) at clk %0d",
                                     hsync_pulse_width, clk_count);
                            errors = errors + 1;
                        end
                    end
                    hsync_prev = hsync;
                end
            end

            // VSYNC measurement (active-low)
            begin
                forever begin
                    @(posedge clk);
                    // Falling edge of vsync = start of sync pulse
                    if (vsync_prev == 1 && vsync == 0) begin
                        vsync_fall_time = clk_count;
                        if (vsync_period_start >= 0) begin
                            vsync_period = vsync_fall_time - vsync_period_start;
                            if (vsync_period != 420000) begin
                                $display("[ERROR] VSYNC period = %0d clocks (expected 420000 = 525*800) at clk %0d",
                                         vsync_period, clk_count);
                                errors = errors + 1;
                            end else begin
                                $display("[PASS] VSYNC period = %0d clocks", vsync_period);
                            end
                        end
                        vsync_period_start = vsync_fall_time;
                    end
                    // Rising edge of vsync = end of sync pulse
                    if (vsync_prev == 0 && vsync == 1) begin
                        vsync_rise_time = clk_count;
                        vsync_pulse_width = vsync_rise_time - vsync_fall_time;
                        if (vsync_pulse_width != 1600) begin
                            $display("[ERROR] VSYNC pulse width = %0d clocks (expected 1600 = 2*800) at clk %0d",
                                     vsync_pulse_width, clk_count);
                            errors = errors + 1;
                        end else begin
                            $display("[PASS] VSYNC pulse width = %0d clocks", vsync_pulse_width);
                        end
                    end
                    vsync_prev = vsync;
                end
            end

            // VIDEO_ACTIVE continuous check
            begin
                // Wait for reset to clear
                @(negedge reset);
                @(posedge clk);
                forever begin
                    @(posedge clk);
                    if (pixel_x < 640 && pixel_y < 480) begin
                        if (video_active !== 1) begin
                            $display("[ERROR] video_active should be HIGH at pixel_x=%0d pixel_y=%0d (clk %0d)",
                                     pixel_x, pixel_y, clk_count);
                            errors = errors + 1;
                        end
                    end else begin
                        if (video_active !== 0) begin
                            $display("[ERROR] video_active should be LOW at pixel_x=%0d pixel_y=%0d (clk %0d)",
                                     pixel_x, pixel_y, clk_count);
                            errors = errors + 1;
                        end
                    end
                end
            end

            // Timeout: run for 2 full frames + margin
            begin
                repeat (2 * 525 * 800 + 1000) @(posedge clk);
            end
        join_any
        disable fork;

        // =====================================================================
        // TEST 2: Spot-check counter values at known points
        // Reset and watch the first few lines
        // =====================================================================
        $display("");
        $display("=== Spot-check: counter values after reset ===");
        reset = 1;
        repeat (3) @(posedge clk);
        reset = 0;
        @(posedge clk);

        // After reset, counters should start at 0
        if (pixel_x !== 0) begin
            $display("[ERROR] pixel_x should be 0 after reset, got %0d", pixel_x);
            errors = errors + 1;
        end else begin
            $display("[PASS] pixel_x = 0 after reset");
        end
        if (pixel_y !== 0) begin
            $display("[ERROR] pixel_y should be 0 after reset, got %0d", pixel_y);
            errors = errors + 1;
        end else begin
            $display("[PASS] pixel_y = 0 after reset");
        end

        // Run 800 clocks — pixel_x should wrap, pixel_y should increment
        repeat (800) @(posedge clk);
        if (pixel_x !== 0) begin
            $display("[ERROR] pixel_x should be 0 after 800 clocks, got %0d", pixel_x);
            errors = errors + 1;
        end else begin
            $display("[PASS] pixel_x wraps to 0 after 800 clocks");
        end
        if (pixel_y !== 1) begin
            $display("[ERROR] pixel_y should be 1 after 800 clocks, got %0d", pixel_y);
            errors = errors + 1;
        end else begin
            $display("[PASS] pixel_y = 1 after 800 clocks");
        end

        // =====================================================================
        // Results
        // =====================================================================
        $display("");
        $display("=== VGA Sync Testbench Complete ===");
        $display("HSYNC periods checked: %0d", hsync_periods_checked);
        if (errors == 0)
            $display("RESULT: ALL TESTS PASSED");
        else
            $display("RESULT: %0d ERROR(S) FOUND", errors);

        $finish;
    end

    // -------------------------------------------------------------------------
    // Dump waveforms
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_vga_sync.vcd");
        $dumpvars(0, tb_vga_sync);
    end

endmodule
