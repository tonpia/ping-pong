// =============================================================================
// camera_config.v
// OV7670 register initialization: QVGA RGB565, AWB/AEC/AGC enabled.
// Test pattern disabled (camera streams live scene).
// =============================================================================
`timescale 1ns / 1ps
module camera_config (
    input  wire clk,
    input  wire rst,
    output wire scl,
    output wire sda,
    output reg  config_done
);

    reg [15:0] config_rom [0:39];
    integer i;

    initial begin
        // --- Soft reset ---
        config_rom[0]  = 16'h1280; // COM7: full reset

        // --- Output format: QVGA RGB565 ---
        config_rom[1]  = 16'h1214; // COM7: QVGA + RGB
        config_rom[2]  = 16'h40D0; // COM15: full range + RGB565
        config_rom[3]  = 16'h3A04; // TSLB

        // --- QVGA scaling ---
        config_rom[4]  = 16'h0C0C; // COM3: DCW + scale enable
        config_rom[5]  = 16'h3E19; // COM14: DCW/scaling PCLK enable, divide by 2
        config_rom[6]  = 16'h1100; // CLKRC: PCLK = XCLK

        // --- AWB + AEC + AGC all enabled ---
        config_rom[7]  = 16'h13E7; // COM8

        // --- Brightness / contrast defaults ---
        config_rom[8]  = 16'h0000; // GAIN
        config_rom[9]  = 16'h1000; // AECH
        config_rom[10] = 16'h1E07; // MVFP

        // --- Color matrix ---
        config_rom[11] = 16'h4F6E;
        config_rom[12] = 16'h5038;
        config_rom[13] = 16'h5111;
        config_rom[14] = 16'h527B;
        config_rom[15] = 16'h5385;
        config_rom[16] = 16'h541E;
        config_rom[17] = 16'h581E;

        // --- Gamma ---
        config_rom[18] = 16'h7A20;
        config_rom[19] = 16'h7B10;
        config_rom[20] = 16'h7C1E;
        config_rom[21] = 16'h7D35;
        config_rom[22] = 16'h7E5A;
        config_rom[23] = 16'h7F69;
        config_rom[24] = 16'h8076;
        config_rom[25] = 16'h8180;
        config_rom[26] = 16'h8288;
        config_rom[27] = 16'h838F;
        config_rom[28] = 16'h8496;

        // --- Scaling coefficients (test pattern bits cleared) ---
        config_rom[29] = 16'h703A; // SCALING_XSC default
        config_rom[30] = 16'h7135; // SCALING_YSC default
        config_rom[31] = 16'h7211; // SCALING_DCWCTR: H/2, V/2 down-sample
        config_rom[32] = 16'h73F1; // SCALING_PCLK_DIV: divide scaling PCLK by 2
        config_rom[33] = 16'hA202; // SCALING_PCLK_DELAY

        // --- End sentinels ---
        config_rom[34] = 16'hFFFF;
        config_rom[35] = 16'hFFFF;
        config_rom[36] = 16'hFFFF;
        config_rom[37] = 16'hFFFF;
        config_rom[38] = 16'hFFFF;
        config_rom[39] = 16'hFFFF;
    end

    // -------------------------------------------------------------------------
    // State machine
    // -------------------------------------------------------------------------
    localparam S_RESET_SEND = 3'd0;
    localparam S_RESET_DONE = 3'd1;
    localparam S_RESET_WAIT = 3'd2;
    localparam S_LOAD       = 3'd3;
    localparam S_WRITE      = 3'd4;
    localparam S_WAIT_DONE  = 3'd5;
    localparam S_PAUSE      = 3'd6;
    localparam S_DONE       = 3'd7;

    reg [2:0]  state;
    reg [5:0]  rom_index;
    reg [7:0]  reg_addr_r;
    reg [7:0]  reg_data_r;
    reg        sccb_start;
    wire       sccb_done;

    reg [24:0] wait_cnt;
    localparam RESET_WAIT_CYCLES = 25'd2_000_000;
    localparam PAUSE_CYCLES      = 25'd100_000;

    sccb_master #(.CLKDIV(250)) u_sccb (
        .clk      (clk),
        .rst      (rst),
        .start    (sccb_start),
        .reg_addr (reg_addr_r),
        .reg_data (reg_data_r),
        .done     (sccb_done),
        .scl      (scl),
        .sda      (sda)
    );

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state       <= S_RESET_SEND;
            rom_index   <= 6'd0;
            sccb_start  <= 1'b0;
            config_done <= 1'b0;
            wait_cnt    <= 25'd0;
            reg_addr_r  <= 8'd0;
            reg_data_r  <= 8'd0;
        end else begin
            sccb_start <= 1'b0;
            case (state)
                S_RESET_SEND: begin
                    reg_addr_r <= config_rom[0][15:8];
                    reg_data_r <= config_rom[0][7:0];
                    sccb_start <= 1'b1;
                    rom_index  <= 6'd1;
                    state      <= S_RESET_DONE;
                end
                S_RESET_DONE: begin
                    if (sccb_done) begin
                        wait_cnt <= 25'd0;
                        state    <= S_RESET_WAIT;
                    end
                end
                S_RESET_WAIT: begin
                    if (wait_cnt < RESET_WAIT_CYCLES)
                        wait_cnt <= wait_cnt + 1;
                    else begin
                        wait_cnt <= 25'd0;
                        state    <= S_LOAD;
                    end
                end
                S_LOAD: begin
                    if (config_rom[rom_index] == 16'hFFFF)
                        state <= S_DONE;
                    else begin
                        reg_addr_r <= config_rom[rom_index][15:8];
                        reg_data_r <= config_rom[rom_index][7:0];
                        rom_index  <= rom_index + 1;
                        state      <= S_WRITE;
                    end
                end
                S_WRITE: begin
                    sccb_start <= 1'b1;
                    state      <= S_WAIT_DONE;
                end
                S_WAIT_DONE: begin
                    if (sccb_done) begin
                        wait_cnt <= 25'd0;
                        state    <= S_PAUSE;
                    end
                end
                S_PAUSE: begin
                    if (wait_cnt < PAUSE_CYCLES)
                        wait_cnt <= wait_cnt + 1;
                    else begin
                        wait_cnt <= 25'd0;
                        state    <= S_LOAD;
                    end
                end
                S_DONE: begin
                    config_done <= 1'b1;
                end
                default: state <= S_DONE;
            endcase
        end
    end
endmodule