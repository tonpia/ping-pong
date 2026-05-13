`timescale 1ns / 1ps

// pixel_filter is purely combinational.
// sw[1:0] = main mode, sw[3:2] = sub-mode, sw[7:4] = threshold
//
// Mode map:
//   00 -> passthrough
//   01 -> grayscale  (R*3 + G*6 + B*1) >> 4  (4-bit result replicated)
//   10 -> color channel  (sw[3:2]: 00=R, 01=G, 10=B, 11=pass)
//   11 -> special        (sw[3:2]: 00=invert, 01=threshold)

module tb_pixel_filter;

    reg  [11:0] pixel_in;
    reg  [11:0] sw;
    wire [11:0] pixel_out;

    pixel_filter uut (
        .pixel_in  (pixel_in),
        .sw        (sw),
        .pixel_out (pixel_out)
    );

    // Gray4 = upper nibble of (R*3 + G*6 + B*1)
    function [3:0] gray4;
        input [3:0] r, g, b;
        reg [7:0] g8;
        begin
            g8 = r*3 + g*6 + b;
            gray4 = g8[7:4];
        end
    endfunction

    task check;
        input [11:0] in_pix;
        input [11:0] switches;
        input [11:0] expected;
        input [79:0] label;
        begin
            pixel_in = in_pix; sw = switches; #10;
            if (pixel_out === expected)
                $display("PASS [%s] in=%h sw=%h out=%h", label, in_pix, switches, pixel_out);
            else
                $display("FAIL [%s] in=%h sw=%h  got=%h  expected=%h",
                         label, in_pix, switches, pixel_out, expected);
        end
    endtask

    reg [3:0] r, g, b, gv;
    reg [3:0] thresh;

    initial begin
        $dumpfile("tb_pixel_filter.vcd");
        $dumpvars(0, tb_pixel_filter);
        $timeformat(-9, 1, " ns", 10);
        $display("===== tb_pixel_filter =====");
        $monitor("%t  sw=%h pixel_in=%h | pixel_out=%h",
                 $time, sw, pixel_in, pixel_out);

        // -------------------------------------------------------
        // MODE 00 : passthrough
        // -------------------------------------------------------
        $display("-- MODE 00: passthrough --");
        check(12'hA53, 12'h000, 12'hA53, "passthrough_A53");
        check(12'h000, 12'h000, 12'h000, "passthrough_000");
        check(12'hFFF, 12'h000, 12'hFFF, "passthrough_FFF");

        // -------------------------------------------------------
        // MODE 01 : weighted grayscale
        // gray8 = R*3 + G*6 + B*1;  gray4 = gray8[7:4]
        // -------------------------------------------------------
        $display("-- MODE 01: grayscale --");

        // Pure red R=F,G=0,B=0 -> 15*3=45=0x2D -> gray4=2
        r=4'hF; g=4'h0; b=4'h0; gv=gray4(r,g,b);
        check(12'hF00, 12'h001, {gv,gv,gv}, "gray_pure_red");

        // Pure green R=0,G=F,B=0 -> 15*6=90=0x5A -> gray4=5
        r=4'h0; g=4'hF; b=4'h0; gv=gray4(r,g,b);
        check(12'h0F0, 12'h001, {gv,gv,gv}, "gray_pure_green");

        // Pure blue R=0,G=0,B=F -> 15*1=15=0x0F -> gray4=0
        r=4'h0; g=4'h0; b=4'hF; gv=gray4(r,g,b);
        check(12'h00F, 12'h001, {gv,gv,gv}, "gray_pure_blue");

        // Mixed R=A,G=5,B=3 -> 10*3+5*6+3 = 30+30+3 = 63 = 0x3F -> gray4=3
        r=4'hA; g=4'h5; b=4'h3; gv=gray4(r,g,b);
        check(12'hA53, 12'h001, {gv,gv,gv}, "gray_mixed");

        // -------------------------------------------------------
        // MODE 10 : color channel isolate
        // -------------------------------------------------------
        $display("-- MODE 10: color channel isolate --");

        r=4'hA; g=4'h5; b=4'h3;

        // sw[3:2]=00 -> R only
        check(12'hA53, 12'h002, {r,4'h0,4'h0}, "channel_R");

        // sw[3:2]=01 -> G only
        check(12'hA53, 12'h006, {4'h0,g,4'h0}, "channel_G");

        // sw[3:2]=10 -> B only
        check(12'hA53, 12'h00A, {4'h0,4'h0,b}, "channel_B");

        // sw[3:2]=11 -> passthrough fallback
        check(12'hA53, 12'h00E, 12'hA53,       "channel_fallback");

        // -------------------------------------------------------
        // MODE 11 sw[3:2]=00 : invert (~R, ~G, ~B)
        // -------------------------------------------------------
        $display("-- MODE 11/00: invert --");
        r=4'hA; g=4'h5; b=4'h3;
        check(12'hA53, 12'h003, {~r,~g,~b},    "invert_A53");
        check(12'h000, 12'h003, 12'hFFF,        "invert_black->white");
        check(12'hFFF, 12'h003, 12'h000,        "invert_white->black");

        // -------------------------------------------------------
        // MODE 11 sw[3:2]=01 : brightness threshold
        //   white if gray4 > thresh, else black
        // -------------------------------------------------------
        $display("-- MODE 11/01: brightness threshold --");

        // White pixel (gray4=F), thresh=0  -> white
        thresh = 4'h0;
        check(12'hFFF, {4'b0,thresh,4'b0111}, 12'hFFF, "thresh_white_t0");

        // Black pixel (gray4=0), thresh=F  -> black
        thresh = 4'hF;
        check(12'h000, {4'b0,thresh,4'b0111}, 12'h000, "thresh_black_tF");

        // Mid-grey R=8,G=8,B=8 -> gray8=8*3+8*6+8=80=0x50 -> gray4=5
        // thresh=4 -> gray4(5) > thresh(4) -> white
        r=4'h8; g=4'h8; b=4'h8; gv=gray4(r,g,b);
        thresh = 4'h4;
        check(12'h888, {4'b0,thresh,4'b0111}, 12'hFFF, "thresh_mid_above");

        // same pixel, thresh=6 -> gray4(5) <= thresh(6) -> black
        thresh = 4'h6;
        check(12'h888, {4'b0,thresh,4'b0111}, 12'h000, "thresh_mid_below");

        $display("===== DONE =====");
        $finish;
    end

endmodule
