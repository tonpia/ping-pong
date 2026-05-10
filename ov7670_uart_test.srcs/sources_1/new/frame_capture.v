`timescale 1ns / 1ps
// =============================================================================
// frame_capture.v
// Captures a full QVGA 320x240 RGB565 frame from the OV7670 camera and writes
// 12-bit RGB444 pixels into an external dual-port BRAM (frame_buffer).
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
// Frame addressing:
//   addr = row * H_PIXELS + col   (sequential column-major within row)
//   range 0 .. H_PIXELS*V_PIXELS - 1   (76799 for QVGA)
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
    reg pclk_r1,  pclk_r2,  pclk_r3;
    reg vsync_r1, vsync_r2, vsync_r3;
    reg href_r1,  href_r2,  href_r3;
    reg [7:0] data_r1, data_r2;

    always @(posedge clk) begin
        pclk_r1  <= cam_pclk;  pclk_r2  <= pclk_r1;  pclk_r3  <= pclk_r2;
        vsync_r1 <= cam_vsync; vsync_r2 <= vsync_r1; vsync_r3 <= vsync_r2;
        href_r1  <= cam_href;  href_r2  <= href_r1;  href_r3  <= href_r2;
        data_r1  <= cam_data;  data_r2  <= data_r1;
    end

    wire pclk_rise  = ( pclk_r2  && !pclk_r3);
    wire vsync_rise = ( vsync_r2 && !vsync_r3);
    wire vsync_fall = (!vsync_r2 &&  vsync_r3);
    wire href_fall  = (!href_r2  &&  href_r3);

    // -------------------------------------------------------------------------
    // Byte-pair assembly state
    //   byte_sel = 0 -> next sampled byte is the high byte
    //   byte_sel = 1 -> next sampled byte is the low byte (completes a pixel)
    // -------------------------------------------------------------------------
    reg        byte_sel;
    reg [7:0]  byte_high;

    // -------------------------------------------------------------------------
    // Top-level FSM
    // -------------------------------------------------------------------------
    localparam S_WAIT_CONFIG = 2'd0;
    localparam S_WAIT_FRAME  = 2'd1;
    localparam S_CAPTURE     = 2'd2;
    reg [1:0] state;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state      <= S_WAIT_CONFIG;
            wr_addr    <= {ADDR_W{1'b0}};
            wr_data    <= 12'd0;
            wr_en      <= 1'b0;
            frame_done <= 1'b0;
            byte_sel   <= 1'b0;
            byte_high  <= 8'd0;
        end else begin
            // 1-cycle pulses default low
            wr_en      <= 1'b0;
            frame_done <= 1'b0;

            case (state)
                S_WAIT_CONFIG: begin
                    if (config_done)
                        state <= S_WAIT_FRAME;
                end

                S_WAIT_FRAME: begin
                    // VSYNC just went low -> active frame begins
                    if (vsync_fall) begin
                        wr_addr  <= {ADDR_W{1'b0}};
                        byte_sel <= 1'b0;
                        state    <= S_CAPTURE;
                    end
                end

                S_CAPTURE: begin
                    // End-of-frame: VSYNC rising returns to inactive
                    if (vsync_rise) begin
                        frame_done <= 1'b1;
                        state      <= S_WAIT_FRAME;
                    end
                    else if (pclk_rise && href_r2 &&
                             wr_addr < H_PIXELS*V_PIXELS) begin
                        if (byte_sel == 1'b0) begin
                            byte_high <= data_r2;
                            byte_sel  <= 1'b1;
                        end else begin
                            wr_data  <= { byte_high[7:4],            // R[4:1]
                                          byte_high[2:0], data_r2[7],// G[5:2]
                                          data_r2[4:1] };            // B[4:1]
                            wr_en    <= 1'b1;
                            byte_sel <= 1'b0;
                        end
                    end

                    // Re-align byte phase at end of every line in case a byte
                    // was ever dropped mid-line (defensive — OV7670 normally
                    // emits an even number of bytes per HREF).
                    if (href_fall) byte_sel <= 1'b0;

                    // Address advances one cycle AFTER the write fires
                    // (wr_en here is the registered value from the previous cycle,
                    //  so during the cycle BRAM sees wr_en=1, wr_addr is still
                    //  the destination; the increment lands the cycle after).
                    if (wr_en) begin
                        wr_addr <= wr_addr + 1'b1;
                    end
                end

                default: state <= S_WAIT_CONFIG;
            endcase
        end
    end

endmodule
