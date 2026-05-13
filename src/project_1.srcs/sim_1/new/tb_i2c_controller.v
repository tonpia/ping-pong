`timescale 1ns / 1ps

// Tests the I2C_Controller module (SCCB write path for OV7670).
//
// Transaction format (WR=1):
//   START -> 8-bit slave addr + ACK -> 8-bit reg addr + ACK ->
//   8-bit data + ACK -> STOP -> END=1
//
// SD_COUNTER advances on every iCLK rising edge while I2C_EN=1 and GO=1.
// Write transaction completes at SD_COUNTER==39, so END fires ~40 iCLK
// cycles after GO is asserted (plus any I2C_CLK phase alignment).
//
// No real slave is present; SDA is pulled high via a weak assign so the
// module sees NACK on all ACK cycles (ACK registers remain 1).
// Transaction completion (END) is still fully testable.

module tb_i2c_controller;

    // System clock
    reg iCLK   = 0;
    reg iRST_N = 0;

    // I2C bit clock (must toggle while transaction runs)
    reg I2C_CLK = 0;
    reg I2C_EN  = 0;

    // 24-bit word: [23:16]=slave_addr  [15:8]=reg_addr  [7:0]=data
    reg [23:0] I2C_WDATA = 24'h420F55;

    // Control
    reg WR = 1; // write mode
    reg GO = 0;

    // Status outputs
    wire       ACK;
    wire       END;
    wire [7:0] I2C_RDATA;

    // Physical lines
    wire I2C_SCLK;
    wire I2C_SDAT;

    // Weak pullup: when nobody drives SDA low, it reads 1 (NACK from slave).
    assign (weak1, weak0) I2C_SDAT = 1'b1;

    I2C_Controller uut (
        .iCLK      (iCLK),
        .iRST_N    (iRST_N),
        .I2C_CLK   (I2C_CLK),
        .I2C_EN    (I2C_EN),
        .I2C_WDATA (I2C_WDATA),
        .I2C_SCLK  (I2C_SCLK),
        .I2C_SDAT  (I2C_SDAT),
        .WR        (WR),
        .GO        (GO),
        .ACK       (ACK),
        .END       (END),
        .I2C_RDATA (I2C_RDATA)
    );

    // iCLK : 50 MHz (20 ns period)
    always #10 iCLK = ~iCLK;

    // I2C_CLK toggles at ~6.25 MHz (slower than iCLK)
    always #80 I2C_CLK = ~I2C_CLK;

    // Count SCLK rising edges during a transaction.
    integer sclk_pulses;
    always @(posedge I2C_SCLK) sclk_pulses = sclk_pulses + 1;

    integer timeout;

    // Wait for END with a cycle timeout; returns 1 on success, 0 on timeout.
    task wait_for_end;
        output success;
        begin
            timeout = 0; success = 0;
            while (!END && timeout < 5000) begin
                @(posedge iCLK); timeout = timeout + 1;
            end
            if (END) success = 1;
        end
    endtask

    reg success;

    initial begin
        $dumpfile("tb_i2c_controller.vcd");
        $dumpvars(0, tb_i2c_controller);
        $timeformat(-9, 1, " ns", 10);
        $display("===== tb_i2c_controller =====");
        $monitor("%t  GO=%b WR=%b I2C_EN=%b | SCLK=%b SDA=%b END=%b ACK=%b",
                 $time, GO, WR, I2C_EN, I2C_SCLK, I2C_SDAT, END, ACK);

        // -------------------------------------------------------
        // RESET
        // -------------------------------------------------------
        iRST_N = 0; GO = 0; I2C_EN = 0;
        repeat(8) @(posedge iCLK);
        iRST_N = 1;
        repeat(4) @(posedge iCLK);

        // -------------------------------------------------------
        // TEST 1 : idle state after reset
        // -------------------------------------------------------
        $display("-- TEST 1: idle state --");
        if (END === 1'b0)
            $display("PASS END=0 in idle");
        else
            $display("FAIL END should be 0 in idle, got %0d", END);
        if (I2C_SCLK === 1'b1)
            $display("PASS SCLK=1 in idle");
        else
            $display("FAIL SCLK should be 1 in idle, got %0d", I2C_SCLK);

        // -------------------------------------------------------
        // TEST 2 : write transaction completes (END pulses)
        // I2C_WDATA = 0x42_0F_55 (slave=0x42, reg=0x0F, data=0x55)
        // -------------------------------------------------------
        $display("-- TEST 2: write transaction 0x42_0F_55 --");
        I2C_WDATA = 24'h420F55;
        WR = 1; I2C_EN = 1; sclk_pulses = 0;
        GO = 1;
        wait_for_end(success);
        if (success)
            $display("PASS END asserted after %0d iCLK cycles  SCLK pulses=%0d",
                     timeout, sclk_pulses);
        else
            $display("FAIL END never asserted (timeout)");
        GO = 0;
        repeat(4) @(posedge iCLK);

        // -------------------------------------------------------
        // TEST 3 : second write (different register) also completes
        // -------------------------------------------------------
        $display("-- TEST 3: second write 0x42_12_AB --");
        I2C_WDATA = 24'h4212AB;
        sclk_pulses = 0;
        GO = 1;
        wait_for_end(success);
        if (success)
            $display("PASS second write END in %0d cycles", timeout);
        else
            $display("FAIL second write timed out");
        GO = 0;
        repeat(4) @(posedge iCLK);

        // -------------------------------------------------------
        // TEST 4 : SCLK returns to 1 after transaction
        // -------------------------------------------------------
        $display("-- TEST 4: SCLK idle-high after transaction --");
        repeat(10) @(posedge iCLK);
        if (I2C_SCLK === 1'b1)
            $display("PASS SCLK=1 after transaction");
        else
            $display("FAIL SCLK=%0d after transaction (expect 1)", I2C_SCLK);

        // -------------------------------------------------------
        // TEST 5 : I2C_EN=0 prevents transaction (END must not fire)
        // -------------------------------------------------------
        $display("-- TEST 5: I2C_EN=0 blocks transaction --");
        I2C_EN = 0; GO = 1;
        repeat(60) @(posedge iCLK);
        if (END === 1'b0)
            $display("PASS no transaction when I2C_EN=0");
        else
            $display("FAIL transaction ran with I2C_EN=0");
        GO = 0; I2C_EN = 1;
        repeat(4) @(posedge iCLK);

        // -------------------------------------------------------
        // TEST 6 : reset mid-transaction clears END
        // -------------------------------------------------------
        $display("-- TEST 6: async reset mid-transaction --");
        GO = 1; sclk_pulses = 0;
        repeat(15) @(posedge iCLK); // start but don't finish
        iRST_N = 0;
        repeat(4) @(posedge iCLK);
        iRST_N = 1; GO = 0;
        repeat(4) @(posedge iCLK);
        if (END === 1'b0)
            $display("PASS END=0 after mid-transaction reset");
        else
            $display("FAIL END=%0d after reset (expect 0)", END);

        // -------------------------------------------------------
        // TEST 7 : back-to-back write after reset recovers
        // -------------------------------------------------------
        $display("-- TEST 7: recovery -- write after reset --");
        I2C_WDATA = 24'h42FF00;
        GO = 1;
        wait_for_end(success);
        if (success)
            $display("PASS recovered write END in %0d cycles", timeout);
        else
            $display("FAIL recovery write timed out");
        GO = 0;

        $display("===== DONE =====");
        $finish;
    end

endmodule
