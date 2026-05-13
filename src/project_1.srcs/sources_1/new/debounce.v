`timescale 1ns / 1ps

// ============================================================
// BUTTON DEBOUNCE MODULE
// Removes mechanical button bouncing
//
// When button is held HIGH long enough,
// output becomes HIGH.
//
// Used for:
// - reset buttons
// - camera reconfigure button
// - menu buttons
//
// clk : system clock
// i   : noisy pushbutton input
// o   : stable debounced output
// ============================================================

module debounce(

    input clk,
    input i,

    output reg o
);

// ============================================================
// COUNTER
// Counts how long button stays pressed
//
// 24-bit counter:
// at 50 MHz:
// 2^24 / 50e6 ≈ 0.33 sec
// ============================================================

reg [23:0] c;

// ============================================================
// INITIAL VALUES
// ============================================================

initial begin
    c = 24'b0;
    o = 0;
end

// ============================================================
// DEBOUNCE LOGIC
// ============================================================

always @(posedge clk) begin

    // --------------------------------------------------------
    // button pressed
    // --------------------------------------------------------
    if(i == 1) begin

        // if counter reached maximum:
        // button has been stable long enough
        if(c == 24'hFFFFFF)

            // valid stable press
            o <= 1;

        else begin

            // not stable yet
            o <= 0;

            // continue counting
            c <= c + 1;
        end
    end

    // --------------------------------------------------------
    // button released
    // reset everything
    // --------------------------------------------------------
    else begin

        c <= 24'b0;
        o <= 0;
    end
end

endmodule