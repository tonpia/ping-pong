`timescale 1ns / 1ps
// =============================================================================
// top.v - OV7670 → BRAM → Filters → VGA pipeline (Basys 3)
//
//   100MHz ──┬──> clk_div ──> 25MHz pixel clock (also drives cam_xclk)
//            │
//            ├──> camera_config ──> SCCB ──> OV7670
//            │
//            ├──> frame_capture ──> frame_buffer (port A, 100MHz writes)
//            │
//            └──> vga_sync + pixel_scaler ──> frame_buffer (port B, 25MHz reads)
//                                       └──> filters ──> VGA RGB444 + HS/VS
//
// SW[1:0] selects filter mode (raw / grayscale / invert / channel isolate).
// SW[4:2] selects which channels survive in isolation mode.
// UART single-pixel debug path is kept for sanity checking.
// =============================================================================
module top (
    input  wire        clk,            // 100 MHz Basys 3 crystal
    input  wire        btnC,           // active-high reset

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

    // UART debug
    output wire        uart_txd,

    // Switches: filter mode + channel mask
    input  wire [4:0]  sw,

    // VGA
    output wire        vga_hs,
    output wire        vga_vs,
    output wire [3:0]  vga_r,
    output wire [3:0]  vga_g,
    output wire [3:0]  vga_b,

    // LEDs (slim debug)
    output wire [15:0] led
);
    wire rst = btnC;

    assign cam_pwdn = 1'b0;
    assign cam_rst  = 1'b1;

    // -------------------------------------------------------------------------
    // 25 MHz pixel clock - shared between OV7670 XCLK and VGA pipeline
    // -------------------------------------------------------------------------
    wire pclk_25;
    clk_div u_clk_div (
        .clk_100mhz (clk),
        .rst        (rst),
        .xclk       (pclk_25)
    );
    assign cam_xclk = pclk_25;

    // -------------------------------------------------------------------------
    // SCCB camera configuration
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
    // Frame capture: OV7670 → BRAM port A
    // -------------------------------------------------------------------------
    wire [16:0] wr_addr;
    wire [11:0] wr_data;
    wire        wr_en;
    wire        frame_done;

    frame_capture #(
        .H_PIXELS (320),
        .V_PIXELS (240),
        .ADDR_W   (17)
    ) u_frame_cap (
        .clk         (clk),
        .rst         (rst),
        .config_done (config_done),
        .cam_pclk    (cam_pclk),
        .cam_vsync   (cam_vsync),
        .cam_href    (cam_href),
        .cam_data    (cam_data),
        .wr_addr     (wr_addr),
        .wr_data     (wr_data),
        .wr_en       (wr_en),
        .frame_done  (frame_done)
    );

    // -------------------------------------------------------------------------
    // VGA timing controller
    // -------------------------------------------------------------------------
    wire        hsync_w;
    wire        vsync_w;
    wire [9:0]  pixel_x;
    wire [9:0]  pixel_y;
    wire        video_active;

    vga_sync u_vga (
        .clk          (pclk_25),
        .reset        (rst),
        .hsync        (hsync_w),
        .vsync        (vsync_w),
        .pixel_x      (pixel_x),
        .pixel_y      (pixel_y),
        .video_active (video_active)
    );

    // -------------------------------------------------------------------------
    // Pixel scaler (2x doubling): map 640x480 VGA → 320x240 buffer
    //   addr = (pixel_y >> 1) * 320 + (pixel_x >> 1)
    //        = (y << 8) + (y << 6) + x
    // Address is gated by video_active so blanking-region overflow can't
    // index past the end of the buffer.
    // -------------------------------------------------------------------------
    wire [8:0]  buf_y = pixel_y[9:1];
    wire [8:0]  buf_x = pixel_x[9:1];
    wire [16:0] read_addr = {buf_y, 8'b0} + {2'b00, buf_y, 6'b0} + {8'b0, buf_x};
    wire [16:0] addr_b    = video_active ? read_addr : 17'd0;

    // -------------------------------------------------------------------------
    // Dual-port frame buffer
    // -------------------------------------------------------------------------
    wire [11:0] dout_b;
    frame_buffer u_fb (
        .clk_a  (clk),
        .clk_b  (pclk_25),
        .we_a   (wr_en),
        .addr_a (wr_addr),
        .din_a  (wr_data),
        .addr_b (addr_b),
        .dout_b (dout_b)
    );

    // BRAM port B has 1 clk_b read latency. Register video_active so the
    // blanking gate aligns with dout_b. (1-pixel horizontal shift is invisible.)
    reg video_active_d;
    always @(posedge pclk_25) begin
        video_active_d <= video_active;
    end

    // -------------------------------------------------------------------------
    // Filter mux
    // -------------------------------------------------------------------------
    wire [11:0] filt_out;
    filters u_filt (
        .pixel_in  (dout_b),
        .sw        (sw),
        .pixel_out (filt_out)
    );

    wire [11:0] vga_rgb = video_active_d ? filt_out : 12'h000;
    assign vga_r  = vga_rgb[11:8];
    assign vga_g  = vga_rgb[7:4];
    assign vga_b  = vga_rgb[3:0];
    assign vga_hs = hsync_w;
    assign vga_vs = vsync_w;

    // -------------------------------------------------------------------------
    // UART debug - keep single-pixel sanity path
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

    wire uart_busy;
    uart_print u_uart_print (
        .clk          (clk),
        .rst          (rst),
        .pixel_data   (pixel_data),
        .trigger      (pixel_valid),
        .uart_tx_line (uart_txd),
        .busy         (uart_busy)
    );

    // -------------------------------------------------------------------------
    // LED debug
    //   [15] config_done sticky
    //   [14] frame_done heartbeat (toggles each captured frame ~30Hz)
    //   [13] vsync sticky-seen
    //   [12] href sticky-seen
    //   [11] pclk sticky-seen
    //   [4:0] mirror of switches
    // -------------------------------------------------------------------------
    reg config_done_r;
    reg frame_toggle;
    reg vsync_seen, href_seen, pclk_seen;
    reg pclk_r1, pclk_r2, pclk_r3;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            config_done_r <= 1'b0;
            frame_toggle  <= 1'b0;
            vsync_seen    <= 1'b0;
            href_seen     <= 1'b0;
            pclk_seen     <= 1'b0;
            pclk_r1       <= 1'b0;
            pclk_r2       <= 1'b0;
            pclk_r3       <= 1'b0;
        end else begin
            if (config_done) config_done_r <= 1'b1;
            if (frame_done)  frame_toggle  <= ~frame_toggle;
            if (cam_vsync)   vsync_seen    <= 1'b1;
            if (cam_href)    href_seen     <= 1'b1;

            pclk_r1 <= cam_pclk;
            pclk_r2 <= pclk_r1;
            pclk_r3 <= pclk_r2;
            if (pclk_r2 && !pclk_r3) pclk_seen <= 1'b1;
        end
    end

    assign led[15]   = config_done_r;
    assign led[14]   = frame_toggle;
    assign led[13]   = vsync_seen;
    assign led[12]   = href_seen;
    assign led[11]   = pclk_seen;
    assign led[10:5] = 6'b0;
    assign led[4:0]  = sw;

endmodule