// =============================================================================
// tb_top.v
// Testbench for OV7670 UART test design.
// Simulates:
//   - System clock
//   - Reset pulse
//   - Fake camera signals (VSYNC, HREF, PCLK, DATA)
//     to verify pixel capture and UART print logic
// =============================================================================

`timescale 1ns / 1ps

module tb_top;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    reg         clk;
    reg         btnC;
    reg         cam_pclk;
    reg         cam_vsync;
    reg         cam_href;
    reg [7:0]   cam_data;
    wire        cam_xclk;
    wire        cam_scl;
    wire        cam_sda;
    wire        cam_pwdn;
    wire        cam_rst;
    wire        uart_txd;
    wire [15:0] led;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    top dut (
        .clk      (clk),
        .btnC     (btnC),
        .cam_pclk (cam_pclk),
        .cam_vsync(cam_vsync),
        .cam_href (cam_href),
        .cam_data (cam_data),
        .cam_xclk (cam_xclk),
        .cam_scl  (cam_scl),
        .cam_sda  (cam_sda),
        .cam_pwdn (cam_pwdn),
        .cam_rst  (cam_rst),
        .uart_txd (uart_txd),
        .led      (led)
    );

    // -------------------------------------------------------------------------
    // 100MHz system clock
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;   // 10ns period = 100MHz

    // -------------------------------------------------------------------------
    // Camera PCLK (~25MHz, matches XCLK)
    // -------------------------------------------------------------------------
    initial cam_pclk = 0;
    always #20 cam_pclk = ~cam_pclk;  // 40ns period = 25MHz

    // -------------------------------------------------------------------------
    // Test sequence
    // NOTE: We skip the full SCCB config wait in simulation by watching
    //       config_done. We manually force config_done-like behavior by
    //       driving fake VSYNC/HREF/DATA after a short delay.
    // -------------------------------------------------------------------------
    initial begin
        // Initialize signals
        btnC      = 1;
        cam_vsync = 0;
        cam_href  = 0;
        cam_data  = 8'hAB;   // Fake pixel byte 1

        // Release reset after 200ns
        #200;
        btnC = 0;

        $display("=== Reset released, waiting for SCCB config... ===");

        // In simulation, skip the full 20ms reset wait - just wait a short time
        // The real hardware will wait properly
        #5000;

        // Force config_done by bypassing - we test pixel_capture and uart_print
        // directly by injecting camera signals.

        // ---------------------------------------------------------------
        // Simulate a camera frame:
        // 1. VSYNC high (start of frame)
        // 2. VSYNC low
        // 3. HREF high + PCLK edges (pixel data)
        // ---------------------------------------------------------------

        $display("=== Injecting fake VSYNC pulse ===");

        // VSYNC rising edge
        @(posedge cam_pclk); #2;
        cam_vsync = 1;
        @(posedge cam_pclk); #2;
        @(posedge cam_pclk); #2;
        cam_vsync = 0;

        // Wait a few PCLK cycles then assert HREF
        repeat(5) @(posedge cam_pclk);

        $display("=== Injecting HREF + pixel data ===");

        // HREF goes high, send first two bytes of pixel
        cam_href = 1;
        cam_data = 8'hAB;    // Byte 1: high byte of RGB565

        @(posedge cam_pclk); #2;   // Byte 1 clocked in

        cam_data = 8'hCD;    // Byte 2: low byte of RGB565
        @(posedge cam_pclk); #2;   // Byte 2 clocked in

        cam_href = 0;

        $display("=== Pixel 0xABCD injected. Watching UART output... ===");
        $display("=== Expected TeraTerm output: PX: ABCD ===");

        // Wait for UART to finish sending (~10 chars at 115200 baud)
        // Each char = ~868 cycles at 100MHz -> 10 chars = ~86800 cycles
        #(868 * 10 * 10 * 2);  // rough wait

        $display("=== Sending second fake frame ===");

        // Second frame with different pixel
        @(posedge cam_pclk); #2;
        cam_vsync = 1;
        @(posedge cam_pclk); #2;
        cam_vsync = 0;
        repeat(5) @(posedge cam_pclk);

        cam_href = 1;
        cam_data = 8'h12;
        @(posedge cam_pclk); #2;
        cam_data = 8'h34;
        @(posedge cam_pclk); #2;
        cam_href = 0;

        $display("=== Pixel 0x1234 injected. Expected: PX: 1234 ===");

        #(868 * 10 * 10 * 2);

        $display("=== Testbench complete ===");
        $finish;
    end

    // -------------------------------------------------------------------------
    // Monitor LED changes
    // -------------------------------------------------------------------------
    initial begin
        $monitor("Time=%0t | led=%016b | uart_tx=%b", $time, led, uart_txd);
    end

    // -------------------------------------------------------------------------
    // Dump waveforms for Vivado simulator
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_top.vcd");
        $dumpvars(0, tb_top);
    end

endmodule