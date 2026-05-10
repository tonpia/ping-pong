`timescale 1ns / 1ps
// =============================================================================
// pixel_capture.v  -- DIAGNOSTIC VERSION
// Samples one pixel per frame from near the CENTER of the QVGA frame
// (line ~120, pixel ~160), rather than top-left corner.
//
// With the color bar test pattern enabled in camera_config.v, this will
// sample a pixel from the middle of the pattern, which should give a
// predictable non-zero value.
// =============================================================================
module pixel_capture (
    input  wire        clk,
    input  wire        rst,
    input  wire        config_done,
    input  wire        cam_pclk,
    input  wire        cam_vsync,
    input  wire        cam_href,
    input  wire [7:0]  cam_data,
    output reg  [15:0] pixel_data,
    output reg         pixel_valid
);

    // -------------------------------------------------------------------------
    // Synchronizers
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
    wire vsync_fall = (!vsync_r2 &&  vsync_r3);
    wire vsync_rise = ( vsync_r2 && !vsync_r3);
    wire href_rise  = ( href_r2  && !href_r3);
    wire href_fall  = (!href_r2  &&  href_r3);

    // -------------------------------------------------------------------------
    // Target: line 120, pixel 160 (center of 320x240 QVGA frame)
    // -------------------------------------------------------------------------
    localparam [8:0] TARGET_LINE  = 9'd120;
    localparam [9:0] TARGET_PIXEL = 10'd160;
    localparam [9:0] TARGET_BYTE  = TARGET_PIXEL * 2;

    reg [8:0] line_cnt;
    reg [9:0] byte_cnt;

    // -------------------------------------------------------------------------
    // State machine
    // -------------------------------------------------------------------------
    localparam S_WAIT_CONFIG = 3'd0;
    localparam S_WAIT_FRAME  = 3'd1;
    localparam S_COUNT_LINES = 3'd2;
    localparam S_COUNT_BYTES = 3'd3;
    localparam S_GRAB_BYTE1  = 3'd4;
    localparam S_IDLE        = 3'd5;

    reg [2:0] state;
    reg [7:0] byte0;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state       <= S_WAIT_CONFIG;
            pixel_data  <= 16'd0;
            pixel_valid <= 1'b0;
            byte0       <= 8'd0;
            line_cnt    <= 9'd0;
            byte_cnt    <= 10'd0;
        end else begin
            pixel_valid <= 1'b0;

            case (state)
                S_WAIT_CONFIG: begin
                    if (config_done)
                        state <= S_WAIT_FRAME;
                end

                S_WAIT_FRAME: begin
                    if (vsync_fall) begin
                        line_cnt <= 9'd0;
                        byte_cnt <= 10'd0;
                        state    <= S_COUNT_LINES;
                    end
                end

                S_COUNT_LINES: begin
                    if (vsync_rise) begin
                        state <= S_WAIT_FRAME;
                    end else if (href_rise) begin
                        if (line_cnt == TARGET_LINE) begin
                            byte_cnt <= 10'd0;
                            state    <= S_COUNT_BYTES;
                        end else begin
                            line_cnt <= line_cnt + 1;
                        end
                    end
                end

                S_COUNT_BYTES: begin
                    if (href_fall) begin
                        state <= S_WAIT_FRAME;
                    end else if (pclk_rise && href_r2) begin
                        if (byte_cnt == TARGET_BYTE) begin
                            byte0 <= data_r2;
                            state <= S_GRAB_BYTE1;
                        end else begin
                            byte_cnt <= byte_cnt + 1;
                        end
                    end
                end

                S_GRAB_BYTE1: begin
                    if (pclk_rise && href_r2) begin
                        pixel_data  <= {byte0, data_r2};
                        pixel_valid <= 1'b1;
                        state       <= S_IDLE;
                    end
                end

                S_IDLE: begin
                    if (vsync_fall) begin
                        line_cnt <= 9'd0;
                        byte_cnt <= 10'd0;
                        state    <= S_COUNT_LINES;
                    end
                end

                default: state <= S_WAIT_CONFIG;
            endcase
        end
    end
endmodule