`timescale 1ns / 1ps

// ============================================================
// VGA DISPLAY CONTROLLER  -  640x480 @ 60 Hz
// ------------------------------------------------------------
// Reads pixels from a 320x240 frame buffer and shows them on a
// 640x480 VGA monitor using simple pixel doubling.
//
// Each source pixel is held for two pixel clock cycles
// horizontally and repeated on two consecutive scan lines
// vertically, so a 320x240 buffer fills the whole screen.
//
// Pixel clock : 25 MHz
// Sync        : industry standard VGA 640x480 @ 60Hz
// ------------------------------------------------------------
// Frame buffer layout (RGB444, 12-bit):
//     addr = y * 320 + x      with x in [0..319], y in [0..239]
// ============================================================

module vga_display (
    input              pclk25,      // 25 MHz VGA pixel clock

    // VGA pins
    output reg [3:0]   vga_red,
    output reg [3:0]   vga_green,
    output reg [3:0]   vga_blue,
    output reg         vga_hsync,
    output reg         vga_vsync,

    // Frame buffer port
    output     [16:0]  frame_addr,
    input      [11:0]  frame_pixel
);

    // ----------------------------------------------------------
    // 640x480 @ 60Hz timing parameters
    // ----------------------------------------------------------
    localparam H_ACTIVE   = 640;
    localparam H_FP       = 16;
    localparam H_SYNC_W   = 96;
    localparam H_BP       = 48;
    localparam H_TOTAL    = 800;     // 640 + 16 + 96 + 48

    localparam V_ACTIVE   = 480;
    localparam V_FP       = 10;
    localparam V_SYNC_W   = 2;
    localparam V_BP       = 33;
    localparam V_TOTAL    = 525;     // 480 + 10 + 2 + 33

    // ----------------------------------------------------------
    // Horizontal / vertical pixel counters
    // ----------------------------------------------------------
    reg [9:0] h_cnt = 0;
    reg [9:0] v_cnt = 0;

    wire end_of_line  = (h_cnt == H_TOTAL - 1);
    wire end_of_frame = (v_cnt == V_TOTAL - 1);

    always @(posedge pclk25) begin
        if (end_of_line) begin
            h_cnt <= 0;
            v_cnt <= end_of_frame ? 10'd0 : (v_cnt + 1'b1);
        end else begin
            h_cnt <= h_cnt + 1'b1;
        end
    end

    // ----------------------------------------------------------
    // Sync pulses  (active-low for 640x480 @ 60Hz)
    // ----------------------------------------------------------
    wire h_sync_n = ~((h_cnt >= H_ACTIVE + H_FP) &&
                      (h_cnt <  H_ACTIVE + H_FP + H_SYNC_W));

    wire v_sync_n = ~((v_cnt >= V_ACTIVE + V_FP) &&
                      (v_cnt <  V_ACTIVE + V_FP + V_SYNC_W));

    wire visible  = (h_cnt < H_ACTIVE) && (v_cnt < V_ACTIVE);

    // ----------------------------------------------------------
    // Pixel doubling : drop LSB of each counter to address the
    // 320x240 source.   (h_cnt >> 1, v_cnt >> 1)
    // ----------------------------------------------------------
    wire [8:0] src_x = h_cnt[9:1];          // 0..319
    wire [7:0] src_y = v_cnt[8:1];          // 0..239

    assign frame_addr = src_y * 17'd320 + src_x;

    // ----------------------------------------------------------
    // BRAM read latency : the frame_pixel returned this cycle
    // corresponds to the address driven *last* cycle.  Delay
    // the sync / visible flags one clock to align them.
    // ----------------------------------------------------------
    reg h_sync_d, v_sync_d, visible_d;

    always @(posedge pclk25) begin
        h_sync_d  <= h_sync_n;
        v_sync_d  <= v_sync_n;
        visible_d <= visible;
    end

    // ----------------------------------------------------------
    // Drive VGA outputs
    // ----------------------------------------------------------
    always @(posedge pclk25) begin
        vga_hsync <= h_sync_d;
        vga_vsync <= v_sync_d;

        if (visible_d) begin
            vga_red   <= frame_pixel[11:8];
            vga_green <= frame_pixel[ 7:4];
            vga_blue  <= frame_pixel[ 3:0];
        end else begin
            vga_red   <= 4'h0;
            vga_green <= 4'h0;
            vga_blue  <= 4'h0;
        end
    end

endmodule
