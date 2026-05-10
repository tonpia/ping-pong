module filters (
    input [11:0] pixel_in,
    input [4:0] sw,
    output [11:0] pixel_out
);

    // Extract individual color channels from 12-bit RGB444 pixel
    wire [3:0] red_in   = pixel_in[11:8];
    wire [3:0] green_in = pixel_in[7:4];
    wire [3:0] blue_in  = pixel_in[3:0];

    // Grayscale Filter: 0.25*R + 0.5*G + 0.25*B
    wire [3:0] gray = (red_in >> 2) + (green_in >> 1) + (blue_in >> 2);

    // Color Filter: Invert values
    wire [11:0] inverted = ~pixel_in;

    // Color Isolation
    // sw[2] = Allow Red
    // sw[3] = Allow Green
    // sw[4] = Allow Blue
    wire [3:0] isolated_red = (sw[2]) ? red_in : 4'b0000;
    wire [3:0] isolated_green = (sw[3]) ? green_in : 4'b0000;
    wire [3:0] isolated_blue = (sw[4]) ? blue_in : 4'b0000;
    wire [11:0] isolated = {isolated_red, isolated_green, isolated_blue};

    // Output based on sw[1:0]
    assign pixel_out = (sw[1:0] == 2'b00) ? pixel_in :
                       (sw[1:0] == 2'b01) ? {gray, gray, gray} :
                       (sw[1:0] == 2'b10) ? inverted :
                       isolated;
endmodule
