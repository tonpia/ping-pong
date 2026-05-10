// =============================================================================
// sccb_master.v
// Implements the SCCB (Serial Camera Control Bus) protocol to configure
// the OV7670 camera registers. SCCB is I2C-like but has no ACK.
//
// OV7670 SCCB device write address = 0x42
//
// This module:
//   1. Takes a register address and data byte
//   2. Sends a 3-phase write: [0x42] -> [reg_addr] -> [reg_data]
//   3. Pulses 'done' when the transaction is complete
//
// SCL frequency = clk_freq / (4 * CLKDIV) 
// With 100MHz clk and CLKDIV=250 -> SCL ~100kHz
// =============================================================================
`timescale 1ns / 1ps
module sccb_master #(
    parameter CLKDIV = 250   // Divider to produce ~100kHz SCL from 100MHz clk
)(
    input  wire       clk,        // 100MHz system clock
    input  wire       rst,        // Active-high reset
    input  wire       start,      // Pulse high for 1 cycle to begin transaction
    input  wire [7:0] reg_addr,   // Camera register address to write
    input  wire [7:0] reg_data,   // Data byte to write into register
    output reg        done,        // Pulses high for 1 cycle when transaction done
    output reg        scl,         // SCCB clock line (to camera SCL pin)
    output reg        sda          // SCCB data line (to camera SDA pin)
);

    // -------------------------------------------------------------------------
    // State machine states
    // -------------------------------------------------------------------------
    localparam IDLE       = 4'd0;
    localparam START_BIT  = 4'd1;
    localparam SEND_BYTE  = 4'd2;
    localparam DONT_CARE  = 4'd3;   // SCCB has no ACK; master releases SDA for 1 bit
    localparam NEXT_PHASE = 4'd4;
    localparam STOP_BIT   = 4'd5;
    localparam DONE_STATE = 4'd6;

    reg [3:0]  state;
    reg [3:0]  bit_index;    // Which bit we're currently sending (7 down to 0)
    reg [1:0]  phase;        // Which of the 3 bytes we're sending (0=addr, 1=reg, 2=data)
    reg [7:0]  shift_reg;    // Byte currently being shifted out
    reg [8:0]  clk_cnt;      // Clock divider counter
    reg        clk_phase;    // 0=SCL low, 1=SCL high within one SCL cycle
    reg        clk_tick;     // Pulses every CLKDIV cycles (quarter-period tick)

    // -------------------------------------------------------------------------
    // Clock divider - generates a tick every CLKDIV system clocks
    // Each SCL cycle = 4 ticks (low, rising, high, falling)
    // -------------------------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_cnt  <= 9'd0;
            clk_tick <= 1'b0;
        end else begin
            if (clk_cnt == CLKDIV - 1) begin
                clk_cnt  <= 9'd0;
                clk_tick <= 1'b1;
            end else begin
                clk_cnt  <= clk_cnt + 1;
                clk_tick <= 1'b0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // SCCB state machine
    // -------------------------------------------------------------------------
    // Internal tick counter for SCL phases (4 ticks per SCL bit period)
    reg [1:0] tick_cnt;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state     <= IDLE;
            scl       <= 1'b1;
            sda       <= 1'b1;
            done      <= 1'b0;
            bit_index <= 4'd7;
            phase     <= 2'd0;
            shift_reg <= 8'd0;
            tick_cnt  <= 2'd0;
        end else begin
            done <= 1'b0; // Default

            case (state)
                // ---------------------------------------------------------
                IDLE: begin
                    scl <= 1'b1;
                    sda <= 1'b1;
                    if (start) begin
                        phase     <= 2'd0;
                        shift_reg <= 8'h42; // OV7670 write address
                        bit_index <= 4'd7;
                        tick_cnt  <= 2'd0;
                        state     <= START_BIT;
                    end
                end

                // ---------------------------------------------------------
                // START condition: SDA goes LOW while SCL is HIGH
                START_BIT: begin
                    if (clk_tick) begin
                        tick_cnt <= tick_cnt + 1;
                        case (tick_cnt)
                            2'd0: begin scl <= 1'b1; sda <= 1'b1; end
                            2'd1: begin scl <= 1'b1; sda <= 1'b0; end // SDA falls
                            2'd2: begin scl <= 1'b0; sda <= 1'b0; end // SCL falls
                            2'd3: begin
                                tick_cnt <= 2'd0;
                                state    <= SEND_BYTE;
                            end
                        endcase
                    end
                end

                // ---------------------------------------------------------
                // Send 8 bits of current byte, MSB first
                SEND_BYTE: begin
                    if (clk_tick) begin
                        tick_cnt <= tick_cnt + 1;
                        case (tick_cnt)
                            2'd0: begin
                                scl <= 1'b0;
                                sda <= shift_reg[bit_index]; // Set data while SCL low
                            end
                            2'd1: begin scl <= 1'b1; end     // SCL rises (data sampled)
                            2'd2: begin scl <= 1'b1; end     // SCL stays high
                            2'd3: begin
                                scl <= 1'b0;
                                tick_cnt <= 2'd0;
                                if (bit_index == 0) begin
                                    state <= DONT_CARE;      // Done with this byte
                                end else begin
                                    bit_index <= bit_index - 1;
                                end
                            end
                        endcase
                    end
                end

                // ---------------------------------------------------------
                // Don't-care bit (replaces ACK in SCCB)
                // Master releases SDA (drives high), ignores response
                DONT_CARE: begin
                    if (clk_tick) begin
                        tick_cnt <= tick_cnt + 1;
                        case (tick_cnt)
                            2'd0: begin scl <= 1'b0; sda <= 1'b1; end
                            2'd1: begin scl <= 1'b1; end
                            2'd2: begin scl <= 1'b1; end
                            2'd3: begin
                                scl      <= 1'b0;
                                tick_cnt <= 2'd0;
                                state    <= NEXT_PHASE;
                            end
                        endcase
                    end
                end

                // ---------------------------------------------------------
                // Move to next byte phase or stop
                NEXT_PHASE: begin
                    phase     <= phase + 1;
                    bit_index <= 4'd7;
                    tick_cnt  <= 2'd0;
                    case (phase)
                        2'd0: begin shift_reg <= reg_addr; state <= SEND_BYTE; end
                        2'd1: begin shift_reg <= reg_data; state <= SEND_BYTE; end
                        2'd2: begin state <= STOP_BIT; end
                        default: state <= STOP_BIT;
                    endcase
                end

                // ---------------------------------------------------------
                // STOP condition: SDA goes HIGH while SCL is HIGH
                STOP_BIT: begin
                    if (clk_tick) begin
                        tick_cnt <= tick_cnt + 1;
                        case (tick_cnt)
                            2'd0: begin scl <= 1'b0; sda <= 1'b0; end
                            2'd1: begin scl <= 1'b1; sda <= 1'b0; end
                            2'd2: begin scl <= 1'b1; sda <= 1'b1; end // SDA rises
                            2'd3: begin
                                tick_cnt <= 2'd0;
                                state    <= DONE_STATE;
                            end
                        endcase
                    end
                end

                // ---------------------------------------------------------
                DONE_STATE: begin
                    done  <= 1'b1;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule