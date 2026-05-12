`timescale 1ns / 1ps
// =============================================================================
// frame_capture.v
// Captures a full QVGA 320x240 RGB565 frame from the OV7670 camera and writes
// 12-bit RGB444 pixels into an external dual-port BRAM (frame_buffer).
//
// Writes are row-aligned:
//   - col_cnt resets to 0 on each HREF falling edge (end of line)
//   - row_cnt increments on each HREF falling edge
//   - both reset on VSYNC falling edge (start of frame)
//   - wr_addr = row_base + col_cnt, where row_base = row_cnt * H_PIXELS
// Extra pixels beyond H_PIXELS within a single HREF are dropped, so each
// buffer row always starts at the camera's HREF boundary. This eliminates
// diagonal skew if the camera emits slightly more/fewer pixels per line.
//
// OV7670 RGB565 byte ordering (per pixel, MSB byte first):
//   byte0 (high) = { R[4:0], G[5:3] }
//   byte1 (low)  = { G[2:0], B[4:0] }
// Combined pixel[15:0] = { R[4:0], G[5:0], B[4:0] }
//
// RGB565 -> RGB444 (drop LSB of each channel):
//   R4 = byte_high[7:4]                     -> R[4:1]
//   G4 = { byte_high[2:0], byte_low[7] }    -> G[5:2]
//   B4 = byte_low[4:1]                      -> B[4:1]
//
// All camera-domain signals (PCLK, VSYNC, HREF, DATA) are 3-stage
// synchronized into the 'clk' domain, identical to pixel_capture.v.
// =============================================================================
module frame_capture #(
    parameter H_PIXELS = 320,
    parameter V_PIXELS = 240,
    parameter ADDR_W   = 17                 // ceil(log2(320*240)) = 17
)(
    input  wire              clk,           // 100 MHz system clock
    input  wire              rst,           // Active-high reset
    input  wire              config_done,   // Camera config has finished

    // OV7670 (asynchronous to clk)
    input  wire              cam_pclk,
    input  wire              cam_vsync,
    input  wire              cam_href,
    input  wire [7:0]        cam_data,

    // BRAM write port (synchronous to clk)
    output reg  [ADDR_W-1:0] wr_addr,
    output reg  [11:0]       wr_data,
    output reg               wr_en,

    // 1-cycle pulse on VSYNC rising edge (end of active frame)
    output reg               frame_done
);

    // -------------------------------------------------------------------------
    // 3-stage synchronizers for camera-domain signals
    // -------------------------------------------------------------------------
    reg pclk_r1,  pclk_r2,  pclk_r3, pclk_r4;
    reg vsync_r1, vsync_r2, vsync_r3;
    reg href_r1,  href_r2,  href_r3;
    reg [7:0] data_r1, data_r2;

    always @(posedge clk) begin
        pclk_r1 <= cam_pclk;  pclk_r2 <= pclk_r1;  pclk_r3 <= pclk_r2;  pclk_r4 <= pclk_r3;
        vsync_r1 <= cam_vsync; vsync_r2 <= vsync_r1; vsync_r3 <= vsync_r2;
        href_r1  <= cam_href;  href_r2  <= href_r1;  href_r3  <= href_r2;
        data_r1  <= cam_data;  data_r2  <= data_r1;
    end

    wire pclk_rise  = ( pclk_r3  && !pclk_r4);     // rising edge
    wire vsync_fall = ( vsync_r2 && !vsync_r3);     // 1->0 transition
    wire vsync_rise = (!vsync_r2 &&  vsync_r3);     // 0->1 transition
    wire href_fall  = ( href_r2  && !href_r3);      // 1->0 (end of line)
    wire href_rise  = (!href_r2  &&  href_r3);      // 0->1 (start of line)

    // -------------------------------------------------------------------------
    // Byte-pair assembly state
    //   byte_sel = 0 -> next sampled byte is the high byte
    //   byte_sel = 1 -> next sampled byte is the low byte (completes a pixel)
    // -------------------------------------------------------------------------
    reg        byte_sel;
    reg [7:0]  byte_high;

    // -------------------------------------------------------------------------
    // Row/column tracking — wr_addr = row_base + col_cnt where
    // row_base is maintained as (row_cnt * H_PIXELS) so we never need a
    // runtime multiplier.
    // -------------------------------------------------------------------------
    reg [8:0]         row_cnt;     // 0 .. V_PIXELS-1
    reg [9:0]         col_cnt;     // 0 .. H_PIXELS-1
    reg [ADDR_W-1:0]  row_base;    // row_cnt * H_PIXELS

    // -------------------------------------------------------------------------
    // Top-level FSM
    // -------------------------------------------------------------------------
    localparam S_WAIT_CONFIG = 2'd0;
    localparam S_WAIT_FRAME  = 2'd1;
    localparam S_CAPTURE     = 2'd2;
    reg [1:0] state;
    
    // Debug: count captured pixels per frame
    reg [16:0] pixel_count;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state       <= S_WAIT_CONFIG;
            wr_addr     <= {ADDR_W{1'b0}};
            wr_data     <= 12'd0;
            wr_en       <= 1'b0;
            frame_done  <= 1'b0;
            byte_sel    <= 1'b0;
            byte_high   <= 8'd0;
            row_cnt     <= 9'd0;
            col_cnt     <= 10'd0;
            row_base    <= {ADDR_W{1'b0}};
            pixel_count <= 17'd0;
        end else begin
            // 1-cycle pulses default low
            wr_en       <= 1'b0;
            frame_done  <= 1'b0;

            case (state)
                S_WAIT_CONFIG: begin
                    if (config_done)
                        state <= S_WAIT_FRAME;
                end

                S_WAIT_FRAME: begin
                    // Try: VSYNC rising (0->1) triggers frame capture
                    if (vsync_rise) begin
                        row_cnt     <= 9'd0;
                        col_cnt     <= 10'd0;
                        row_base    <= {ADDR_W{1'b0}};
                        byte_sel    <= 1'b0;
                        pixel_count <= 17'd0;
                        state       <= S_CAPTURE;
                    end
                end

                S_CAPTURE: begin
                    // End-of-frame: VSYNC falling (1->0) ends capture
                    if (vsync_fall) begin
                        frame_done  <= 1'b1;
                        state       <= S_WAIT_FRAME;
                    end
                    // End-of-line: advance row_base, reset col + byte phase
                    else if (href_fall) begin
                        col_cnt  <= 10'd0;
                        byte_sel <= 1'b0;
                        if (row_cnt < V_PIXELS - 1) begin
                            row_cnt  <= row_cnt + 1'b1;
                            row_base <= row_base + H_PIXELS;
                        end
                    end
                    // Sample a pixel byte; drop anything past H_PIXELS
                    // columns or V_PIXELS rows.
                    // Sample when HREF is HIGH (during active pixel time)
                    else if (pclk_rise && href_r2 &&
                             col_cnt < H_PIXELS && row_cnt < V_PIXELS) begin
                        if (byte_sel == 1'b0) begin
                            byte_high <= data_r2;
                            byte_sel  <= 1'b1;
                        end else begin
                            // FIXED: Swap R and B channels (R was displaying B, making red artifacts)
                            // Assume: data_r2 (second)  = { R[4:0], G[5:3] }
                            //         byte_high (first) = { G[2:0], B[4:0] }
                            wr_data      <= { byte_high[4:1],           // B[4:1] -> R output (was too red, now corrected)
                                              data_r2[2:0], byte_high[7],// G[5:2] (unchanged)
                                              data_r2[7:4] };            // R[4:1] -> B output
                            wr_addr      <= row_base + col_cnt;
                            wr_en        <= 1'b1;
                            col_cnt      <= col_cnt + 1'b1;
                            byte_sel     <= 1'b0;
                            pixel_count  <= pixel_count + 1'b1;
                        end
                    end
                end

                default: state <= S_WAIT_CONFIG;
            endcase
        end
    end

endmodule
