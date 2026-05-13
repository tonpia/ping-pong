`timescale 1ns / 1ps

// ============================================================
// OV7670 CAPTURE  -  RGB565 stream -> RGB444 frame buffer
// ------------------------------------------------------------
// The OV7670 outputs one RGB565 pixel as two bytes on D[7:0].
// We assemble the 16-bit pixel, shrink it to 12-bit RGB444 to
// match the Basys 3 VGA DAC, and emit:
//
//   * a flat linear address  : addr = y * 320 + x
//   * a one-cycle write pulse `we`
//   * the running (x, y) co-ordinates for downstream blocks
//
// All sequencing happens on the camera pixel clock (pclk).
// ============================================================

module ov7670_capture (
    input            pclk,
    input            vsync,
    input            href,
    input  [7:0]     d,

    output [16:0]    addr,
    output [11:0]    dout,
    output           we,

    output [9:0]     x,
    output [9:0]     y
);

    // ----------------------------------------------------------
    // HREF start-of-line gate.
    // Originally needed to skip a 1-3 PCLK preamble between HREF
    // rising and the first valid byte on D[7:0].  Once HSTART/
    // HSTOP are tuned (see the LUT in sccb_sender.v) HREF rises
    // exactly on the first valid byte, so the gate is no longer
    // protecting anything -- every cycle it skips is a pixel
    // dropped from the start of the row, which leaves the same
    // number of unwritten columns on the right edge of every
    // BRAM row.  Set to 0 unless your sensor exhibits an HREF
    // preamble; bump in even increments if so.
    // ----------------------------------------------------------
    localparam [2:0] HREF_SETTLE = 3'd0;

    reg [2:0] href_cnt = 3'd0;
    wire      href_ready = (href_cnt == HREF_SETTLE);

    always @(posedge pclk) begin
        if (!href)
            href_cnt <= 3'd0;
        else if (!href_ready)
            href_cnt <= href_cnt + 3'd1;
    end

    // ----------------------------------------------------------
    // Byte assembly : OV7670 sends byte 1 (R/G upper) then
    // byte 2 (G lower / B).  Shift-register makes the join easy.
    // ----------------------------------------------------------
    reg [15:0] pixel_word = 16'h0000;

    always @(posedge pclk) begin
        pixel_word <= {pixel_word[7:0], d};
    end

    // ----------------------------------------------------------
    // Toggle flag : asserts on the second byte of every pixel.
    // While the line is active (href = 1 AND past the settle
    // window) it alternates 0 / 1; otherwise it is forced back
    // to 0 so we never write garbage.
    // ----------------------------------------------------------
    reg byte_phase  = 1'b0;
    reg pixel_ready = 1'b0;

    always @(posedge pclk) begin
        if (!href || !href_ready) begin
            byte_phase  <= 1'b0;
            pixel_ready <= 1'b0;
        end else begin
            byte_phase  <= ~byte_phase;
            pixel_ready <=  byte_phase;     // 1 cycle after second byte
        end
    end

    // ----------------------------------------------------------
    // RGB565 -> RGB444 truncation
    //   R[4:0] -> R[3:0]    (drop LSB)
    //   G[5:0] -> G[3:0]    (drop two LSBs)
    //   B[4:0] -> B[3:0]    (drop LSB)
    // ----------------------------------------------------------
    wire [3:0] r4 = pixel_word[15:12];
    wire [3:0] g4 = pixel_word[10: 7];
    wire [3:0] b4 = pixel_word[ 4: 1];

    // ----------------------------------------------------------
    // Pixel co-ordinates.
    //
    // End-of-line is detected from the camera's HREF falling
    // edge, not from a pixel count.  If we counted pixels and
    // wrapped at x_pos == 319 we'd be assuming the capture
    // window emits *exactly* 320 pixels per HREF -- but the
    // HREF_SETTLE gate above drops the first few cycles, and
    // some OV7670 batches stretch HREF a couple of cycles past
    // the last valid pixel.  Either offset causes x_pos to
    // never reach 319 (or to overshoot it), which leaves the
    // row counter stuck on row 0 and makes every subsequent
    // row drift right by the per-line error.  That accumulates
    // into a diagonal shear of the whole image.
    //
    // Using HREF directly: x resets and y advances exactly once
    // per camera line, regardless of how many bytes the camera
    // chose to emit in that window.  x_pos is clamped at 319
    // so a camera that emits >320 pixels can't bleed into the
    // next row.
    // ----------------------------------------------------------
    reg [9:0] x_pos = 10'd0;
    reg [9:0] y_pos = 10'd0;

    reg href_q = 1'b0;
    always @(posedge pclk) begin
        href_q <= href;
    end
    wire href_fall = href_q & ~href;

    always @(posedge pclk) begin
        if (vsync) begin
            x_pos <= 10'd0;
            y_pos <= 10'd0;
        end else if (href_fall) begin
            x_pos <= 10'd0;
            y_pos <= (y_pos == 10'd239) ? 10'd0 : (y_pos + 1'b1);
        end else if (pixel_ready && (x_pos != 10'd319)) begin
            x_pos <= x_pos + 1'b1;
        end
    end

    // ----------------------------------------------------------
    // Output pipeline.
    // ------------------------------------------------------------
    // Without registering, addr / dout / we are driven from three
    // different sources that update on the same edge that the
    // BRAM samples on, so the address presented to the BRAM lands
    // one position ahead of the pixel data (pixel N ends up in
    // address N+1, and address 0 stays at its init value).  Stage
    // them all into the same register set so they are presented
    // to the BRAM consistently one cycle later.
    // ----------------------------------------------------------
    reg [16:0] addr_q = 17'd0;
    reg [11:0] dout_q = 12'h000;
    reg        we_q   = 1'b0;

    always @(posedge pclk) begin
        if (vsync) begin
            we_q <= 1'b0;
        end else begin
            we_q <= pixel_ready;
            if (pixel_ready) begin
                addr_q <= y_pos * 17'd320 + x_pos;
                dout_q <= {r4, g4, b4};
            end
        end
    end

    assign addr = addr_q;
    assign dout = dout_q;
    assign we   = we_q;
    assign x    = x_pos;
    assign y    = y_pos;

endmodule
