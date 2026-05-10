`timescale 1ns / 1ps
// =============================================================================
// tb_filters.v — self-checking testbench for filters.v
//
// Filter modes (sw[1:0]):
//   00 = raw passthrough
//   01 = grayscale (R>>2 + G>>1 + B>>2 replicated to all 3 channels)
//   10 = bitwise inversion
//   11 = channel isolation (sw[2]=R, sw[3]=G, sw[4]=B)
// =============================================================================
module tb_filters;

    reg  [11:0] pixel_in;
    reg  [4:0]  sw;
    wire [11:0] pixel_out;

    filters dut (
        .pixel_in  (pixel_in),
        .sw        (sw),
        .pixel_out (pixel_out)
    );

    integer errors = 0;

    task check;
        input [11:0] expected;
        input [255:0] label;
        begin
            #1;
            if (pixel_out !== expected) begin
                $display("FAIL [%0s]: in=%h sw=%b -> got %h, expected %h",
                         label, pixel_in, sw, pixel_out, expected);
                errors = errors + 1;
            end else begin
                $display("  OK [%0s]: in=%h sw=%b -> %h",
                         label, pixel_in, sw, pixel_out);
            end
        end
    endtask

    function [11:0] expected_gray;
        input [11:0] p;
        reg [3:0] r, g, b, gray;
        begin
            r = p[11:8];
            g = p[7:4];
            b = p[3:0];
            gray = (r >> 2) + (g >> 1) + (b >> 2);
            expected_gray = {gray, gray, gray};
        end
    endfunction

    initial begin
        // ---------------- Mode 00: raw passthrough ----------------
        sw = 5'b00000;
        pixel_in = 12'h000; check(12'h000, "raw black");
        pixel_in = 12'hFFF; check(12'hFFF, "raw white");
        pixel_in = 12'hA5C; check(12'hA5C, "raw mix");

        // ---------------- Mode 01: grayscale ----------------
        sw = 5'b00001;
        pixel_in = 12'hF00; check(expected_gray(12'hF00), "gray pure red");
        pixel_in = 12'h0F0; check(expected_gray(12'h0F0), "gray pure green");
        pixel_in = 12'h00F; check(expected_gray(12'h00F), "gray pure blue");
        pixel_in = 12'hFFF; check(expected_gray(12'hFFF), "gray white");
        pixel_in = 12'h000; check(expected_gray(12'h000), "gray black");
        pixel_in = 12'hABC; check(expected_gray(12'hABC), "gray mix");

        // ---------------- Mode 10: invert ----------------
        sw = 5'b00010;
        pixel_in = 12'h000; check(12'hFFF, "invert black");
        pixel_in = 12'hFFF; check(12'h000, "invert white");
        pixel_in = 12'hA5C; check(~12'hA5C, "invert mix");

        // ---------------- Mode 11: channel isolation ----------------
        // sw[2]=R, sw[3]=G, sw[4]=B
        pixel_in = 12'hABC;

        sw = 5'b00011;                               // all channels off
        check(12'h000, "isolate none");

        sw = 5'b00111;                               // R only
        check(12'hA00, "isolate R");

        sw = 5'b01011;                               // G only
        check(12'h0B0, "isolate G");

        sw = 5'b10011;                               // B only
        check(12'h00C, "isolate B");

        sw = 5'b01111;                               // R+G
        check(12'hAB0, "isolate RG");

        sw = 5'b11111;                               // all on (passthrough-like)
        check(12'hABC, "isolate RGB");

        // ---------------- Summary ----------------
        if (errors == 0) $display("=== TEST PASSED ===");
        else             $display("=== TEST FAILED with %0d errors ===", errors);
        $finish;
    end

    initial begin
        $dumpfile("tb_filters.vcd");
        $dumpvars(0, tb_filters);
    end

endmodule
