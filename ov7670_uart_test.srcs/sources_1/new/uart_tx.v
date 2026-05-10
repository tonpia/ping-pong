// =============================================================================
// uart_tx.v
// Simple UART transmitter - 8N1 format (8 data bits, no parity, 1 stop bit)
//
// Usage:
//   Set 'data_in' to the byte you want to send.
//   Pulse 'send' high for 1 clock cycle.
//   Wait for 'busy' to go low before sending the next byte.
//
// Baud rate = clk_freq / BAUD_DIV
// For 115200 baud at 100MHz: BAUD_DIV = 100_000_000 / 115200 = 868
// =============================================================================

module uart_tx #(
    parameter BAUD_DIV = 868   // 100MHz / 115200 baud
)(
    input  wire       clk,       // 100MHz system clock
    input  wire       rst,
    input  wire [7:0] data_in,   // Byte to transmit
    input  wire       send,      // Pulse high to start transmission
    output reg        tx,        // UART TX line (to USB-UART bridge)
    output reg        busy       // High while transmitting
);

    localparam IDLE  = 2'd0;
    localparam START = 2'd1;
    localparam DATA  = 2'd2;
    localparam STOP  = 2'd3;

    reg [1:0]  state;
    reg [9:0]  baud_cnt;    // Counts up to BAUD_DIV
    reg [3:0]  bit_cnt;     // Which data bit we're sending (0-7)
    reg [7:0]  shift_reg;   // Byte being shifted out

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state     <= IDLE;
            tx        <= 1'b1;   // UART idle = high
            busy      <= 1'b0;
            baud_cnt  <= 10'd0;
            bit_cnt   <= 4'd0;
            shift_reg <= 8'd0;
        end else begin
            case (state)
                // ---------------------------------------------------------
                IDLE: begin
                    tx   <= 1'b1;
                    busy <= 1'b0;
                    if (send) begin
                        shift_reg <= data_in;
                        baud_cnt  <= 10'd0;
                        busy      <= 1'b1;
                        state     <= START;
                    end
                end

                // ---------------------------------------------------------
                // Send start bit (logic 0)
                START: begin
                    tx <= 1'b0;
                    if (baud_cnt == BAUD_DIV - 1) begin
                        baud_cnt <= 10'd0;
                        bit_cnt  <= 4'd0;
                        state    <= DATA;
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end

                // ---------------------------------------------------------
                // Send 8 data bits, LSB first
                DATA: begin
                    tx <= shift_reg[0];
                    if (baud_cnt == BAUD_DIV - 1) begin
                        baud_cnt  <= 10'd0;
                        shift_reg <= {1'b0, shift_reg[7:1]}; // Shift right
                        if (bit_cnt == 4'd7) begin
                            state <= STOP;
                        end else begin
                            bit_cnt <= bit_cnt + 1;
                        end
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end

                // ---------------------------------------------------------
                // Send stop bit (logic 1)
                STOP: begin
                    tx <= 1'b1;
                    if (baud_cnt == BAUD_DIV - 1) begin
                        baud_cnt <= 10'd0;
                        state    <= IDLE;
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule