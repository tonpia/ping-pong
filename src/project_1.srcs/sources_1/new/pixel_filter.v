`timescale 1ns / 1ps

// ============================================================
// PIXEL FILTER  -  three selectable real-time effects
// ------------------------------------------------------------
// Each helper block computes one filtered RGB444 pixel.
// A final multiplexer selects which output is forwarded to the
// VGA controller, driven by the user switches.
//
// Switch layout
//   sw[1:0] : main mode
//      00 = raw pass-through
//      01 = grayscale
//      10 = single-channel isolation (sw[3:2] picks R/G/B)
//      11 = effects               (sw[3:2] picks invert / threshold)
//   sw[7:4] : threshold level used in binary mode
// ============================================================

module pixel_filter (
    input  [11:0] pixel_in,
    input  [11:0] sw,
    output [11:0] pixel_out
);

    // ----------------------------------------------------------
    // Split incoming RGB444 pixel into its three components.
    // ----------------------------------------------------------
    wire [3:0] r = pixel_in[11:8];
    wire [3:0] g = pixel_in[ 7:4];
    wire [3:0] b = pixel_in[ 3:0];

    // ----------------------------------------------------------
    // Helper 1 : luminance approximation
    //   Y ~= 0.30 R + 0.60 G + 0.10 B
    //   Implemented as 3R + 6G + B, then >> 4 to bring it back
    //   to 4 bits.
    // ----------------------------------------------------------
    wire [7:0] luma8 = (r * 3) + (g * 6) + b;
    wire [3:0] luma  = luma8[7:4];

    wire [11:0] px_gray = {luma, luma, luma};

    // ----------------------------------------------------------
    // Helper 2 : channel isolation outputs.
    // ----------------------------------------------------------
    wire [11:0] px_red_only   = {r,    4'h0, 4'h0};
    wire [11:0] px_green_only = {4'h0, g,    4'h0};
    wire [11:0] px_blue_only  = {4'h0, 4'h0, b};

    // ----------------------------------------------------------
    // Helper 3 : effects.
    // ----------------------------------------------------------
    wire [11:0] px_invert    = {~r, ~g, ~b};
    wire [11:0] px_threshold = (luma > sw[7:4]) ? 12'hFFF : 12'h000;

    // ----------------------------------------------------------
    // Sub-mode selectors (one mux per category).
    // ----------------------------------------------------------
    reg [11:0] px_channel;
    always @(*) begin
        case (sw[3:2])
            2'b00:   px_channel = px_red_only;
            2'b01:   px_channel = px_green_only;
            2'b10:   px_channel = px_blue_only;
            default: px_channel = pixel_in;
        endcase
    end

    reg [11:0] px_effects;
    always @(*) begin
        case (sw[3:2])
            2'b00:   px_effects = px_invert;
            2'b01:   px_effects = px_threshold;
            default: px_effects = pixel_in;
        endcase
    end

    // ----------------------------------------------------------
    // Final output mux : main mode select.
    // ----------------------------------------------------------
    reg [11:0] result;
    always @(*) begin
        case (sw[1:0])
            2'b00:   result = pixel_in;     // raw
            2'b01:   result = px_gray;      // grayscale
            2'b10:   result = px_channel;   // channel isolation
            2'b11:   result = px_effects;   // invert / threshold
            default: result = pixel_in;
        endcase
    end

    assign pixel_out = result;

endmodule
