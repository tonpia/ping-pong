// =============================================================================
// uart_print.v
// Takes a 16-bit pixel value and sends it over UART as a readable hex string.
// Output format in TeraTerm: "PX: AABB\r\n"
// Where AA = high byte, BB = low byte in hex.
//
// When 'trigger' pulses high, this module serializes the message
// and sends each character through uart_tx one at a time.
// =============================================================================

module uart_print (
    input  wire        clk,
    input  wire        rst,
    input  wire [15:0] pixel_data,   // 16-bit RGB565 pixel to print
    input  wire        trigger,      // Pulse to start sending message
    output wire        uart_tx_line, // Connects to Basys 3 UART TX pin
    output reg         busy          // High while printing
);

    // -------------------------------------------------------------------------
    // UART TX instance
    // -------------------------------------------------------------------------
    reg  [7:0] tx_data;
    reg        tx_send;
    wire       tx_busy;

    uart_tx #(.BAUD_DIV(868)) u_uart (
        .clk     (clk),
        .rst     (rst),
        .data_in (tx_data),
        .send    (tx_send),
        .tx      (uart_tx_line),
        .busy    (tx_busy)
    );

    // -------------------------------------------------------------------------
    // Hex digit lookup function
    // -------------------------------------------------------------------------
    function [7:0] hex_char;
        input [3:0] nibble;
        begin
            case (nibble)
                4'h0: hex_char = "0";
                4'h1: hex_char = "1";
                4'h2: hex_char = "2";
                4'h3: hex_char = "3";
                4'h4: hex_char = "4";
                4'h5: hex_char = "5";
                4'h6: hex_char = "6";
                4'h7: hex_char = "7";
                4'h8: hex_char = "8";
                4'h9: hex_char = "9";
                4'hA: hex_char = "A";
                4'hB: hex_char = "B";
                4'hC: hex_char = "C";
                4'hD: hex_char = "D";
                4'hE: hex_char = "E";
                4'hF: hex_char = "F";
                default: hex_char = "?";
            endcase
        end
    endfunction

    // -------------------------------------------------------------------------
    // Message ROM: "PX: AABB\r\n" = 10 characters
    // Index: 0='P', 1='X', 2=':', 3=' ', 4=HI_HI, 5=HI_LO, 6=LO_HI, 7=LO_LO, 8='\r', 9='\n'
    // -------------------------------------------------------------------------
    reg [7:0] msg [0:9];
    reg [3:0] char_index;
    reg [3:0] state;

    localparam S_IDLE    = 4'd0;
    localparam S_LOAD    = 4'd1;
    localparam S_WAIT_TX = 4'd2;
    localparam S_SEND    = 4'd3;
    localparam S_NEXT    = 4'd4;
    localparam S_DONE    = 4'd5;

    reg [15:0] pixel_latch;  // Latch pixel when trigger fires

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state      <= S_IDLE;
            busy       <= 1'b0;
            tx_send    <= 1'b0;
            tx_data    <= 8'd0;
            char_index <= 4'd0;
            pixel_latch<= 16'd0;
        end else begin
            tx_send <= 1'b0; // default

            case (state)
                // ---------------------------------------------------------
                S_IDLE: begin
                    busy <= 1'b0;
                    if (trigger) begin
                        pixel_latch <= pixel_data;
                        busy        <= 1'b1;
                        state       <= S_LOAD;
                    end
                end

                // ---------------------------------------------------------
                // Build the message string using the latched pixel value
                S_LOAD: begin
                    msg[0] <= "P";
                    msg[1] <= "X";
                    msg[2] <= ":";
                    msg[3] <= " ";
                    msg[4] <= hex_char(pixel_latch[15:12]);
                    msg[5] <= hex_char(pixel_latch[11:8]);
                    msg[6] <= hex_char(pixel_latch[7:4]);
                    msg[7] <= hex_char(pixel_latch[3:0]);
                    msg[8] <= 8'h0D;  // '\r'
                    msg[9] <= 8'h0A;  // '\n'
                    char_index <= 4'd0;
                    state      <= S_SEND;
                end

                // ---------------------------------------------------------
                // Send current character
                S_SEND: begin
                    if (!tx_busy) begin
                        tx_data <= msg[char_index];
                        tx_send <= 1'b1;
                        state   <= S_WAIT_TX;
                    end
                end

                // ---------------------------------------------------------
                // Wait for UART to finish sending this byte
                S_WAIT_TX: begin
                    if (!tx_busy && !tx_send) begin
                        state <= S_NEXT;
                    end
                end

                // ---------------------------------------------------------
                S_NEXT: begin
                    if (char_index == 4'd9) begin
                        state <= S_DONE;
                    end else begin
                        char_index <= char_index + 1;
                        state      <= S_SEND;
                    end
                end

                // ---------------------------------------------------------
                S_DONE: begin
                    busy  <= 1'b0;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule