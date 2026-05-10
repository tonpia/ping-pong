// =============================================================================
// clk_div.v
// Generates a ~24MHz clock for the OV7670 XCLK input.
// System clock is 100MHz on Basys 3.
// We divide by 4 to get 25MHz (close enough - OV7670 accepts 10-48MHz).
// =============================================================================

module clk_div (
    input  wire clk_100mhz,   // 100MHz system clock from Basys 3
    input  wire rst,           // Active-high reset
    output reg  xclk           // ~25MHz output to OV7670 XCLK pin
);

    reg [1:0] counter;

    always @(posedge clk_100mhz or posedge rst) begin
        if (rst) begin
            counter <= 2'd0;
            xclk    <= 1'b0;
        end else begin
            if (counter == 2'd1) begin
                counter <= 2'd0;
                xclk    <= ~xclk;   // Toggle every 2 cycles = divide by 4 = 25MHz
            end else begin
                counter <= counter + 1;
            end
        end
    end

endmodule