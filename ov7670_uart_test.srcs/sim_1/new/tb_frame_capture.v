`timescale 1ns / 1ps
// =============================================================================
// tb_frame_capture.v
// Self-checking testbench for frame_capture.v.
//
// Strategy:
//   - Instantiate the DUT with a small 4x2 frame (8 pixels) so we don't have
//     to clock 76800 pixels through the synchronizer in simulation.
//   - Drive realistic OV7670 timing: cam_data and cam_href change on negedge
//     of cam_pclk, so they are stable across the posedge that the DUT samples.
//   - Capture every (wr_en, wr_addr, wr_data) tuple into arrays.
//   - After two frames, compare against expected RGB444 values and check that
//     the address counter resets between frames.
// =============================================================================
module tb_frame_capture;

    // -------------------------------------------------------------------------
    // Frame geometry kept tiny for fast simulation
    // -------------------------------------------------------------------------
    localparam integer H      = 4;
    localparam integer V      = 2;
    localparam integer N      = H * V;       // 8 pixels
    localparam integer ADDR_W = 4;           // > log2(8)

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    reg               clk         = 1'b0;
    reg               rst         = 1'b1;
    reg               config_done = 1'b0;
    reg               cam_pclk    = 1'b0;
    reg               cam_vsync   = 1'b1;    // idle high between frames
    reg               cam_href    = 1'b0;
    reg [7:0]         cam_data    = 8'h00;

    wire [ADDR_W-1:0] wr_addr;
    wire [11:0]       wr_data;
    wire              wr_en;
    wire              frame_done;

    frame_capture #(
        .H_PIXELS(H),
        .V_PIXELS(V),
        .ADDR_W  (ADDR_W)
    ) dut (
        .clk        (clk),
        .rst        (rst),
        .config_done(config_done),
        .cam_pclk   (cam_pclk),
        .cam_vsync  (cam_vsync),
        .cam_href   (cam_href),
        .cam_data   (cam_data),
        .wr_addr    (wr_addr),
        .wr_data    (wr_data),
        .wr_en      (wr_en),
        .frame_done (frame_done)
    );

    // -------------------------------------------------------------------------
    // Clocks
    //   sys clk : 100 MHz (10 ns period)
    //   cam pclk: 25 MHz  (40 ns period) - independent toggle
    // -------------------------------------------------------------------------
    always #5  clk      = ~clk;
    always #20 cam_pclk = ~cam_pclk;

    // -------------------------------------------------------------------------
    // Test vectors and expected results
    // -------------------------------------------------------------------------
    reg [15:0] pixels_f1   [0:N-1];
    reg [15:0] pixels_f2   [0:N-1];
    reg [11:0] expected_f1 [0:N-1];
    reg [11:0] expected_f2 [0:N-1];

    function [11:0] rgb565_to_rgb444;
        input [15:0] p;
        begin
            // R[4:1] | G[5:2] | B[4:1]
            rgb565_to_rgb444 = { p[15:12], p[10:7], p[4:1] };
        end
    endfunction

    // -------------------------------------------------------------------------
    // Capture buffers - record every wr_en pulse from the DUT
    // -------------------------------------------------------------------------
    reg [11:0]       cap_data [0:2*N-1];
    reg [ADDR_W-1:0] cap_addr [0:2*N-1];
    integer          cap_cnt   = 0;
    integer          frames_done = 0;
    integer          errors    = 0;

    always @(posedge clk) begin
        if (wr_en) begin
            if (cap_cnt < 2*N) begin
                cap_addr[cap_cnt] = wr_addr;
                cap_data[cap_cnt] = wr_data;
            end
            cap_cnt = cap_cnt + 1;
        end
        if (frame_done) frames_done = frames_done + 1;
    end

    // -------------------------------------------------------------------------
    // Stimulus tasks
    //
    // Drive one camera byte. We change cam_data on the falling edge of
    // cam_pclk so it is stable for the rising edge that follows (where the
    // OV7670 would clock the byte out, and where the DUT's sync chain will
    // eventually latch it).
    // -------------------------------------------------------------------------
    task send_byte(input [7:0] b);
        begin
            @(negedge cam_pclk);
            cam_data = b;
            @(posedge cam_pclk);
        end
    endtask

    // Drive one HREF line of H pixels (= 2H bytes). HREF and the first byte
    // are presented together on a negedge, so by the time the next posedge
    // arrives both signals are valid in the camera domain.
    task drive_line(input [15:0] p0, input [15:0] p1,
                    input [15:0] p2, input [15:0] p3);
        begin
            @(negedge cam_pclk);
            cam_href = 1'b1;
            cam_data = p0[15:8];           // first high byte appears with HREF
            @(posedge cam_pclk);           // first byte clocked

            send_byte(p0[ 7:0]);
            send_byte(p1[15:8]);
            send_byte(p1[ 7:0]);
            send_byte(p2[15:8]);
            send_byte(p2[ 7:0]);
            send_byte(p3[15:8]);
            send_byte(p3[ 7:0]);

            @(negedge cam_pclk);
            cam_href = 1'b0;
            cam_data = 8'h00;
            // Inter-line gap
            repeat (3) @(posedge cam_pclk);
        end
    endtask

    // Drive a complete frame: VSYNC pulse, V lines of H pixels, VSYNC rise.
    task drive_frame(input integer base_idx,
                     input [(16*N)-1:0] flat_pixels);
        integer r;
        reg [15:0] frame_pix [0:N-1];
        integer    j;
        begin
            // Unpack flat vector (Verilog-2001 has no array port passing)
            for (j = 0; j < N; j = j + 1) begin
                frame_pix[j] = flat_pixels[16*(N-1-j) +: 16];
            end

            // VSYNC pulse: high (idle) -> low (active region)
            @(negedge cam_pclk);
            cam_vsync = 1'b1;
            repeat (4) @(posedge cam_pclk);
            @(negedge cam_pclk);
            cam_vsync = 1'b0;
            repeat (4) @(posedge cam_pclk);

            // Two HREF lines, 4 pixels each
            for (r = 0; r < V; r = r + 1) begin
                drive_line(frame_pix[r*H + 0],
                           frame_pix[r*H + 1],
                           frame_pix[r*H + 2],
                           frame_pix[r*H + 3]);
            end

            // End of active region: VSYNC rises again
            repeat (4) @(posedge cam_pclk);
            @(negedge cam_pclk);
            cam_vsync = 1'b1;
            repeat (8) @(posedge cam_pclk);
        end
    endtask

    // -------------------------------------------------------------------------
    // Main test sequence
    // -------------------------------------------------------------------------
    integer i;
    integer cap_base;

    initial begin
        // Frame 1 test pixels - corners of the color cube + a couple mixes
        pixels_f1[0] = 16'hF800;   // pure red    -> 0xF00
        pixels_f1[1] = 16'h07E0;   // pure green  -> 0x0F0
        pixels_f1[2] = 16'h001F;   // pure blue   -> 0x00F
        pixels_f1[3] = 16'hFFFF;   // white       -> 0xFFF
        pixels_f1[4] = 16'h0000;   // black       -> 0x000
        pixels_f1[5] = 16'hABCD;   // mix         -> 0xA76
        pixels_f1[6] = 16'h1234;   // mix         -> 0x14A
        pixels_f1[7] = 16'h5555;   // mid-grey-ish-> 0x5AA

        // Frame 2 - all-different vector to confirm addr resets and overwrites
        pixels_f2[0] = 16'hDEAD;
        pixels_f2[1] = 16'hBEEF;
        pixels_f2[2] = 16'hCAFE;
        pixels_f2[3] = 16'h1234;
        pixels_f2[4] = 16'h5678;
        pixels_f2[5] = 16'h9ABC;
        pixels_f2[6] = 16'h0F0F;
        pixels_f2[7] = 16'hF0F0;

        for (i = 0; i < N; i = i + 1) begin
            expected_f1[i] = rgb565_to_rgb444(pixels_f1[i]);
            expected_f2[i] = rgb565_to_rgb444(pixels_f2[i]);
        end

        // -------- Reset --------
        rst         = 1'b1;
        config_done = 1'b0;
        cam_vsync   = 1'b1;
        cam_href    = 1'b0;
        cam_data    = 8'h00;
        repeat (10) @(posedge clk);
        rst = 1'b0;
        repeat (5) @(posedge clk);

        // Confirm no spurious writes before config_done
        if (cap_cnt != 0) begin
            $display("ERROR: %0d writes occurred before config_done", cap_cnt);
            errors = errors + 1;
        end

        config_done = 1'b1;
        repeat (10) @(posedge clk);

        // ---------------- Frame 1 ----------------
        $display("=== Driving frame 1 ===");
        drive_frame(0, {pixels_f1[0], pixels_f1[1], pixels_f1[2], pixels_f1[3],
                        pixels_f1[4], pixels_f1[5], pixels_f1[6], pixels_f1[7]});

        // Let the FSM see vsync_rise and pulse frame_done
        repeat (50) @(posedge clk);

        $display("Frame 1: captured %0d writes (expected %0d)", cap_cnt, N);
        if (cap_cnt != N) begin
            $display("ERROR: frame 1 write count = %0d, expected %0d", cap_cnt, N);
            errors = errors + 1;
        end
        for (i = 0; i < N && i < cap_cnt; i = i + 1) begin
            if (cap_addr[i] !== i[ADDR_W-1:0]) begin
                $display("ERROR f1: write %0d had addr=%0d, expected %0d",
                         i, cap_addr[i], i);
                errors = errors + 1;
            end
            if (cap_data[i] !== expected_f1[i]) begin
                $display("ERROR f1: pixel %0d (RGB565=%h): got %h, expected %h",
                         i, pixels_f1[i], cap_data[i], expected_f1[i]);
                errors = errors + 1;
            end else begin
                $display("  OK  f1 pixel %0d: addr=%0d  RGB565=%h -> RGB444=%h",
                         i, cap_addr[i], pixels_f1[i], cap_data[i]);
            end
        end
        if (frames_done < 1) begin
            $display("ERROR: frame_done never asserted after frame 1");
            errors = errors + 1;
        end

        // ---------------- Frame 2 ----------------
        cap_base = cap_cnt;
        $display("=== Driving frame 2 ===");
        drive_frame(0, {pixels_f2[0], pixels_f2[1], pixels_f2[2], pixels_f2[3],
                        pixels_f2[4], pixels_f2[5], pixels_f2[6], pixels_f2[7]});
        repeat (50) @(posedge clk);

        $display("Frame 2: captured %0d new writes (expected %0d)",
                 cap_cnt - cap_base, N);
        if ((cap_cnt - cap_base) != N) begin
            $display("ERROR: frame 2 write count = %0d, expected %0d",
                     cap_cnt - cap_base, N);
            errors = errors + 1;
        end
        for (i = 0; i < N && (cap_base + i) < cap_cnt; i = i + 1) begin
            if (cap_addr[cap_base + i] !== i[ADDR_W-1:0]) begin
                $display("ERROR f2: write %0d had addr=%0d, expected %0d (addr should reset)",
                         i, cap_addr[cap_base + i], i);
                errors = errors + 1;
            end
            if (cap_data[cap_base + i] !== expected_f2[i]) begin
                $display("ERROR f2: pixel %0d (RGB565=%h): got %h, expected %h",
                         i, pixels_f2[i], cap_data[cap_base + i], expected_f2[i]);
                errors = errors + 1;
            end else begin
                $display("  OK  f2 pixel %0d: addr=%0d  RGB565=%h -> RGB444=%h",
                         i, cap_addr[cap_base + i], pixels_f2[i],
                         cap_data[cap_base + i]);
            end
        end
        if (frames_done < 2) begin
            $display("ERROR: frame_done not asserted twice (saw %0d)", frames_done);
            errors = errors + 1;
        end

        // ---------------- Summary ----------------
        if (errors == 0)
            $display("=== TEST PASSED (%0d frames, %0d writes) ===",
                     frames_done, cap_cnt);
        else
            $display("=== TEST FAILED with %0d errors ===", errors);

        $finish;
    end

    // Optional waveform dump
    initial begin
        $dumpfile("tb_frame_capture.vcd");
        $dumpvars(0, tb_frame_capture);
    end

    // Safety net so a bug can't hang the sim
    initial begin
        #2_000_000;   // 2 ms simulated
        $display("ERROR: simulation timeout");
        $finish;
    end

endmodule
