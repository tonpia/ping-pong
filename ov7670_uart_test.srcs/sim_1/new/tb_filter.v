`timescale 1ns / 1ps

module tb_filter;
    // 1. Signal Declarations
    reg [11:0] pixel_in;
    reg [4:0] sw;
    wire [11:0] pixel_out;

    // 2. Unit Under Test (UUT) Instantiation
    filters uut (
        .pixel_in(pixel_in),
        .sw(sw),
        .pixel_out(pixel_out)
    );

    // 3. Stimulus Logic
    initial begin
        // Initialize Inputs
        pixel_in = 12'hA5C; // Test pixel: R=A, G=5, B=C
        sw = 5'b00000;
        #10;

        // Test Mode 00: Passthrough (Raw)
        sw[1:0] = 2'b00;
        #10;
        $display("Mode 00: In=%h, Out=%h (Expected: %h)", pixel_in, pixel_out, pixel_in);

        // Test Mode 01: Grayscale
        // Math: (A>>2) + (5>>1) + (C>>2) = 2 + 2 + 3 = 7
        // Expected Out: 777
        sw[1:0] = 2'b01;
        #10;
        $display("Mode 01: In=%h, Out=%h (Expected: 777)", pixel_in, pixel_out);

        // Test Mode 10: Inversion
        // Expected Out: ~A5C = 5A3
        sw[1:0] = 2'b10;
        #10;
        $display("Mode 10: In=%h, Out=%h (Expected: 5A3)", pixel_in, pixel_out);

        // Test Mode 11: Isolation (Red Only)
        sw[1:0] = 2'b11;
        sw[4:2] = 3'b001; // Allow Red, block G/B
        #10;
        $display("Mode 11 (Red): In=%h, Out=%h (Expected: A00)", pixel_in, pixel_out);

        // Test Mode 11: Isolation (Green & Blue Only)
        sw[4:2] = 3'b110; // Block Red, allow G/B
        #10;
        $display("Mode 11 (G&B): In=%h, Out=%h (Expected: 05C)", pixel_in, pixel_out);

        $finish;
    end
endmodule
