`timescale 1ns / 1ps

// ============================================================
// TOP MODULE  -  Baseline real-time video pipeline
// ------------------------------------------------------------
// Target board : Digilent Basys 3
// Camera       : OV7670 (RGB565 @ 320x240, sub-sampled)
// Display      : 640x480 @ 60Hz VGA (pixel-doubled 320x240)
// Filters      : 3 hardware filters selectable from switches
//
//                sw[1:0] = filter select
//                  00 -> raw camera
//                  01 -> grayscale
//                  10 -> single-channel isolation (sw[3:2])
//                  11 -> invert / binary threshold (sw[3:2])
//
//                sw[7:4] = threshold value
// ============================================================

module ov7670_top (
    // ---- System ----
    input         clk100,

    // ---- OV7670 camera ----
    input         OV7670_VSYNC,
    input         OV7670_HREF,
    input         OV7670_PCLK,
    input  [7:0]  OV7670_D,
    output        OV7670_XCLK,
    output        OV7670_SIOC,
    inout         OV7670_SIOD,
    output        pwdn,
    output        reset,

    // ---- VGA ----
    output [3:0]  vga_red,
    output [3:0]  vga_green,
    output [3:0]  vga_blue,
    output        vga_hsync,
    output        vga_vsync,

    // ---- User IO ----
    input         btn,
    input  [11:0] sw,
    output [3:0]  LED
);

    // ----------------------------------------------------------
    // Camera power control - keep camera powered, not held in
    // reset.  pwdn = 0 -> active.  reset = 1 -> deasserted.
    // ----------------------------------------------------------
    assign pwdn  = 1'b0;
    assign reset = 1'b1;

    // ----------------------------------------------------------
    // Clock generation (MMCM IP)
    //   clk50 - debouncer
    //   clk25 - VGA pixel clock and SCCB master clock
    //   clk24 - OV7670 XCLK
    //   clk_dbg - reserved (unused in baseline)
    //   clk_extra - reserved (unused in baseline)
    // ----------------------------------------------------------
    wire clk50, clk25, clk_dbg, clk24, clk_extra;

    clk_wiz_0 u_clocks (
        .clk_in1 (clk100),
        .clk_out1(clk50),
        .clk_out2(clk25),
        .clk_out3(clk_dbg),
        .clk_out4(clk24),
        .clk_out5(clk_extra)
    );

    assign OV7670_XCLK = clk24;

    // ----------------------------------------------------------
    // Camera pixel clock buffer.
    // OV7670_PCLK enters the FPGA on a non-clock-capable pin, so
    // the synthesizer would otherwise route it as fabric (long
    // skew, setup/hold violations on D[7:0] -> "color snow").
    // Force it onto a global clock network with an explicit
    // BUFG.  The CLOCK_DEDICATED_ROUTE FALSE constraint in the
    // XDC still applies on the IBUF -> BUFG net so Vivado does
    // not error on the non-CCIO pin source.
    // ----------------------------------------------------------
    wire pclk;
    BUFG u_pclk_bufg (
        .I (OV7670_PCLK),
        .O (pclk)
    );

    // ----------------------------------------------------------
    // Push-button -> resend camera SCCB configuration
    // ----------------------------------------------------------
    wire btn_stable;

    debounce u_btn (
        .clk (clk50),
        .i   (btn),
        .o   (btn_stable)
    );

    // ----------------------------------------------------------
    // SCCB configuration of the OV7670.
    // ----------------------------------------------------------
    wire config_done;

    I2C_AV_Config u_sccb (
        .iCLK        (clk25),
        .iRST_N      (~btn_stable),
        .Config_Done (config_done),
        .I2C_SCLK    (OV7670_SIOC),
        .I2C_SDAT    (OV7670_SIOD),
        .LUT_INDEX   (),
        .I2C_RDATA   ()
    );

    // Status LED -> high once camera registers have been written
    assign LED = {3'b000, config_done};

    // ----------------------------------------------------------
    // Pixel capture : convert OV7670 stream -> 12-bit RGB444
    // and produce write-side frame-buffer signals.
    // ----------------------------------------------------------
    wire [16:0] cap_addr;
    wire [11:0] cap_data;
    wire        cap_we;

    ov7670_capture u_capture (
        .pclk  (pclk),
        .vsync (OV7670_VSYNC),
        .href  (OV7670_HREF),
        .d     (OV7670_D),
        .addr  (cap_addr),
        .dout  (cap_data),
        .we    (cap_we),
        .x     (),
        .y     ()
    );

    // ----------------------------------------------------------
    // Dual-port frame buffer (Block-RAM IP).
    //   Port A : camera writes (OV7670_PCLK domain)
    //   Port B : VGA  reads    (clk25 domain)
    // ----------------------------------------------------------
    wire [16:0] vga_addr;
    wire [11:0] raw_pixel;

    blk_mem_gen_0 u_framebuffer (
        // Write port - camera side
        .clka  (pclk),
        .wea   (cap_we),
        .addra (cap_addr),
        .dina  (cap_data),
        // Read port - VGA side
        .clkb  (clk25),
        .addrb (vga_addr),
        .doutb (raw_pixel)
    );

    // ----------------------------------------------------------
    // Real-time pixel filter (raw / grayscale / channel / FX)
    // ----------------------------------------------------------
    wire [11:0] filtered_pixel;

    pixel_filter u_filter (
        .pixel_in  (raw_pixel),
        .sw        (sw),
        .pixel_out (filtered_pixel)
    );

    // ----------------------------------------------------------
    // VGA 640x480 controller : pixel-doubled 320x240 output
    // ----------------------------------------------------------
    vga_display u_vga (
        .pclk25      (clk25),
        .vga_red     (vga_red),
        .vga_green   (vga_green),
        .vga_blue    (vga_blue),
        .vga_hsync   (vga_hsync),
        .vga_vsync   (vga_vsync),
        .frame_addr  (vga_addr),
        .frame_pixel (filtered_pixel)
    );

endmodule
