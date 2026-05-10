// =============================================================================
// vga_sync.v
// VGA timing controller for 640x480 @ 60Hz
// Pixel clock: 25MHz
// =============================================================================

`timescale 1ns / 1ps

module vga_sync (
    input  wire       clk,        // 25MHz pixel clock
    input  wire       reset,
    output wire       hsync,
    output wire       vsync,
    output wire [9:0] pixel_x,
    output wire [9:0] pixel_y,
    output wire       video_active
);

    // VGA 640x480 @ 60Hz timing constants
    // Horizontal (in pixel clocks)
    localparam H_VISIBLE    = 640;
    localparam H_FRONT      = 16;
    localparam H_SYNC       = 96;
    localparam H_BACK       = 48;
    localparam H_TOTAL      = 800;  // 640+16+96+48

    // Vertical (in lines)
    localparam V_VISIBLE    = 480;
    localparam V_FRONT      = 10;
    localparam V_SYNC       = 2;
    localparam V_BACK       = 33;
    localparam V_TOTAL      = 525;  // 480+10+2+33

    // Counters
    reg [9:0] h_count = 0;
    reg [9:0] v_count = 0;

    // Horizontal counter
    always @(posedge clk) begin
        if (reset) begin
            h_count <= 0;
        end else if (h_count == H_TOTAL - 1) begin
            h_count <= 0;
        end else begin
            h_count <= h_count + 1;
        end
    end

    // Vertical counter — increments at end of each line
    always @(posedge clk) begin
        if (reset) begin
            v_count <= 0;
        end else if (h_count == H_TOTAL - 1) begin
            if (v_count == V_TOTAL - 1)
                v_count <= 0;
            else
                v_count <= v_count + 1;
        end
    end

    // Sync pulses (active low)
    // HSYNC active during [H_VISIBLE + H_FRONT, H_VISIBLE + H_FRONT + H_SYNC)
    assign hsync = ~((h_count >= H_VISIBLE + H_FRONT) &&
                     (h_count <  H_VISIBLE + H_FRONT + H_SYNC));

    // VSYNC active during [V_VISIBLE + V_FRONT, V_VISIBLE + V_FRONT + V_SYNC)
    assign vsync = ~((v_count >= V_VISIBLE + V_FRONT) &&
                     (v_count <  V_VISIBLE + V_FRONT + V_SYNC));

    // Expose counters
    assign pixel_x = h_count;
    assign pixel_y = v_count;

    // Video active only in visible region
    assign video_active = (h_count < H_VISIBLE) && (v_count < V_VISIBLE);

endmodule
