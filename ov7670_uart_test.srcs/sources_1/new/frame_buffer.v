`timescale 1ns / 1ps
// =============================================================================
// frame_buffer.v — Dual-Port BRAM, 320x240 @ 12-bit (RGB444)
//
// Port A: write port — driven by frame_capture, clocked by clk_a (100 MHz sys)
// Port B: read port  — driven by VGA controller, clocked by clk_b (25 MHz pix)
//
// True dual-port BRAM with independent clocks per port: the BRAM array itself
// performs the clock-domain crossing between the 100 MHz write side and the
// 25 MHz VGA read side, so no external synchronizers are required.
//
// 76800 entries × 12 bits = 900 Kbits ≈ 25 × 36Kb BRAM blocks on Basys 3.
// The (* ram_style = "block" *) attribute forces Vivado to use block RAM.
// =============================================================================
module frame_buffer (
    input  wire        clk_a,       // 100 MHz write-side clock (sys)
    input  wire        clk_b,       //  25 MHz read-side clock  (VGA pixel)

    // Port A — write (from frame_capture)
    input  wire        we_a,        // write enable
    input  wire [16:0] addr_a,      // write address, range 0..76799
    input  wire [11:0] din_a,       // 12-bit RGB444 pixel to write

    // Port B — read (from VGA / pixel_scaler)
    input  wire [16:0] addr_b,      // read address, range 0..76799
    output reg  [11:0] dout_b       // 12-bit RGB444 pixel (1-cycle latency)
);

    // 76800 entries × 12 bits
    (* ram_style = "block" *)
    reg [11:0] mem [0:76799];

    // Port A: synchronous write on 100 MHz sys clock
    always @(posedge clk_a) begin
        if (we_a)
            mem[addr_a] <= din_a;
    end

    // Port B: synchronous read on 25 MHz VGA clock — output registered
    // dout_b is valid 1 clk_b cycle after addr_b is presented
    always @(posedge clk_b) begin
        dout_b <= mem[addr_b];
    end

endmodule
