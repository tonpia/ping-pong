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
        btnC      = 1;
        cam_vsync = 0;
        cam_href  = 0;
        cam_data  = 8'hAB;
    
        // Release reset
        #200;
        btnC = 0;
    
        // *** BYPASS config wait - force config_done high ***
        #500;
        force dut.config_done = 1;
        #100;
        release dut.config_done;
    
        // Now inject camera frame immediately
        $display("=== Injecting fake VSYNC pulse ===");
    
        @(posedge cam_pclk); #2;
        cam_vsync = 1;
        @(posedge cam_pclk); #2;
        @(posedge cam_pclk); #2;
        cam_vsync = 0;
    
        repeat(5) @(posedge cam_pclk);
    
        $display("=== Injecting HREF + pixel data ===");
        cam_href = 1;
        cam_data = 8'hAB;
        @(posedge cam_pclk); #2;
        cam_data = 8'hCD;
        @(posedge cam_pclk); #2;
        cam_href = 0;
    
        $display("=== Expected: PX: ABCD ===");
    
        // Wait for UART to print (~10 chars)
        #(868 * 10 * 12);
    
        $display("=== Second frame ===");
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
    
        #(868 * 10 * 12);
        $display("=== Done ===");
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