`timescale 1ns / 1ps
// =============================================================================
// top.v
// Top-level for OV7670 camera UART test on Basys 3.
//
// DEBUG LED MAP (updated):
//   LED[15] = config_done (solid after ~500ms)
//   LED[14] = pixel_valid heartbeat (toggles each captured pixel)
//   LED[13] = VSYNC toggle (toggles each frame ~30Hz, visible blink)
//   LED[12] = HREF toggle (toggles each line rising edge ~15kHz, looks solid dim)
//   LED[11] = PCLK toggle divided by 2^20 (visible blink if PCLK running)
//   LED[10] = href_ever_high (sticky latch: HIGH if HREF pulsed at least once)
//   LED[9]  = vsync_ever_high (sticky latch)
//   LED[8]  = pclk_ever_seen  (sticky latch)
//   LED[7:0]= upper byte of last captured pixel
// =============================================================================
module top (
    input  wire        clk,
    input  wire        btnC,
    // OV7670
    input  wire        cam_pclk,
    input  wire        cam_vsync,
    input  wire        cam_href,
    input  wire [7:0]  cam_data,
    output wire        cam_xclk,
    output wire        cam_scl,
    output wire        cam_sda,
    output wire        cam_pwdn,
    output wire        cam_rst,
    // UART
    output wire        uart_txd,
    // LEDs
    output wire [15:0] led
);
    wire rst = btnC;

    // Static camera control
    assign cam_pwdn = 1'b0;
    assign cam_rst  = 1'b1;

    // -------------------------------------------------------------------------
    // XCLK generation (25MHz)
    // -------------------------------------------------------------------------
    clk_div u_clk_div (
        .clk_100mhz (clk),
        .rst        (rst),
        .xclk       (cam_xclk)
    );

    // -------------------------------------------------------------------------
    // SCCB config
    // -------------------------------------------------------------------------
    wire config_done;
    wire sda_out;
    assign cam_sda = sda_out;

    camera_config u_cam_cfg (
        .clk         (clk),
        .rst         (rst),
        .scl         (cam_scl),
        .sda         (sda_out),
        .config_done (config_done)
    );

    // -------------------------------------------------------------------------
    // Pixel capture
    // -------------------------------------------------------------------------
    wire [15:0] pixel_data;
    wire        pixel_valid;

    pixel_capture u_pix_cap (
        .clk         (clk),
        .rst         (rst),
        .config_done (config_done),
        .cam_pclk    (cam_pclk),
        .cam_vsync   (cam_vsync),
        .cam_href    (cam_href),
        .cam_data    (cam_data),
        .pixel_data  (pixel_data),
        .pixel_valid (pixel_valid)
    );

    // -------------------------------------------------------------------------
    // UART print
    // -------------------------------------------------------------------------
    wire uart_busy;
    uart_print u_uart_print (
        .clk          (clk),
        .rst          (rst),
        .pixel_data   (pixel_data),
        .trigger      (pixel_valid),
        .uart_tx_line (uart_txd),
        .busy         (uart_busy)
    );

    // =========================================================================
    // DEBUG: synchronize camera signals into sys clock domain
    // =========================================================================
    reg pclk_r1,  pclk_r2,  pclk_r3;
    reg vsync_r1, vsync_r2, vsync_r3;
    reg href_r1,  href_r2,  href_r3;
    always @(posedge clk) begin
        pclk_r1  <= cam_pclk;  pclk_r2  <= pclk_r1;  pclk_r3  <= pclk_r2;
        vsync_r1 <= cam_vsync; vsync_r2 <= vsync_r1; vsync_r3 <= vsync_r2;
        href_r1  <= cam_href;  href_r2  <= href_r1;  href_r3  <= href_r2;
    end
    wire pclk_rise  = (pclk_r2  && !pclk_r3);
    wire href_rise  = (href_r2  && !href_r3);
    wire vsync_rise = (vsync_r2 && !vsync_r3);

    // -------------------------------------------------------------------------
    // Toggle flops - these blink if the signal has edges
    // -------------------------------------------------------------------------
    reg vsync_toggle;
    reg href_toggle;
    reg [20:0] pclk_div;   // Divide 25MHz PCLK edges down to ~12Hz visible blink

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            vsync_toggle <= 1'b0;
            href_toggle  <= 1'b0;
            pclk_div     <= 21'd0;
        end else begin
            if (vsync_rise) vsync_toggle <= ~vsync_toggle;
            if (href_rise)  href_toggle  <= ~href_toggle;
            if (pclk_rise)  pclk_div     <= pclk_div + 1;
        end
    end

    // -------------------------------------------------------------------------
    // Sticky "ever seen" latches - these go HIGH forever once the
    // corresponding signal has been observed high at least once
    // -------------------------------------------------------------------------
    reg href_ever_high;
    reg vsync_ever_high;
    reg pclk_ever_seen;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            href_ever_high  <= 1'b0;
            vsync_ever_high <= 1'b0;
            pclk_ever_seen  <= 1'b0;
        end else begin
            if (href_r2)   href_ever_high  <= 1'b1;
            if (vsync_r2)  vsync_ever_high <= 1'b1;
            if (pclk_rise) pclk_ever_seen  <= 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // Heartbeats
    // -------------------------------------------------------------------------
    reg config_done_r;
    reg pixel_seen;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            config_done_r <= 1'b0;
            pixel_seen    <= 1'b0;
        end else begin
            if (config_done) config_done_r <= 1'b1;
            if (pixel_valid) pixel_seen    <= ~pixel_seen;
        end
    end

    // -------------------------------------------------------------------------
    // LED assignments
    // -------------------------------------------------------------------------
    assign led[15]  = config_done_r;     // Solid after ~500ms
    assign led[14]  = pixel_seen;        // Toggles each captured pixel
    assign led[13]  = vsync_toggle;      // Visible blink ~15Hz if camera streaming
    assign led[12]  = href_toggle;       // Very fast toggle, looks dim-solid if lines active
    assign led[11]  = pclk_div[20];      // ~12Hz blink if PCLK is actually running
    assign led[10]  = href_ever_high;    // Sticky: did HREF ever pulse?
    assign led[9]   = vsync_ever_high;   // Sticky: did VSYNC ever pulse?
    assign led[8]   = pclk_ever_seen;    // Sticky: did PCLK ever have an edge?
    assign led[7:0] = pixel_data[15:8];  // Upper byte of last pixel

endmodule