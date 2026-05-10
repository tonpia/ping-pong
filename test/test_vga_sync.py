"""
Cocotb testbench for vga_sync.v
Verifies VGA 640x480 @ 60Hz timing:
  1. HSYNC period = 800 pixel clocks
  2. HSYNC pulse width = 96 pixel clocks
  3. VSYNC period = 525 lines = 420,000 clocks
  4. VSYNC pulse width = 2 lines = 1,600 clocks
  5. video_active HIGH only when pixel_x < 640 AND pixel_y < 480
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles


async def reset_dut(dut):
    """Apply reset for a few clock cycles."""
    dut.reset.value = 1
    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    await RisingEdge(dut.clk)


@cocotb.test()
async def test_reset_values(dut):
    """After reset, counters should be 0."""
    clock = Clock(dut.clk, 40, units="ns")  # 25MHz
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    assert dut.pixel_x.value == 0, f"pixel_x after reset: {dut.pixel_x.value}"
    assert dut.pixel_y.value == 0, f"pixel_y after reset: {dut.pixel_y.value}"
    dut._log.info("PASS: counters are 0 after reset")


@cocotb.test()
async def test_h_counter_wraps_at_800(dut):
    """pixel_x should wrap from 799 back to 0 after 800 clocks."""
    clock = Clock(dut.clk, 40, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    # After reset pixel_x=0, run 799 more clocks to reach pixel_x=799
    await ClockCycles(dut.clk, 799)
    assert dut.pixel_x.value == 799, f"Expected pixel_x=799, got {dut.pixel_x.value}"

    # One more clock should wrap to 0
    await ClockCycles(dut.clk, 1)
    assert dut.pixel_x.value == 0, f"Expected pixel_x=0 after wrap, got {dut.pixel_x.value}"
    assert dut.pixel_y.value == 1, f"Expected pixel_y=1 after first line, got {dut.pixel_y.value}"
    dut._log.info("PASS: h_counter wraps at 800, v_counter increments")


@cocotb.test()
async def test_hsync_timing(dut):
    """HSYNC period = 800 clocks, pulse width = 96 clocks (active low)."""
    clock = Clock(dut.clk, 40, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    # Measure multiple HSYNC periods by counting clocks between falling edges
    NUM_LINES = 10

    for line in range(NUM_LINES):
        # Wait for hsync falling edge (start of sync pulse)
        while dut.hsync.value == 0:
            await RisingEdge(dut.clk)
        while dut.hsync.value == 1:
            await RisingEdge(dut.clk)
        # hsync just went low — count pulse width
        pulse_width = 0
        while dut.hsync.value == 0:
            await RisingEdge(dut.clk)
            pulse_width += 1

        assert pulse_width == 96, f"Line {line}: HSYNC pulse width = {pulse_width}, expected 96"

        # Now count until next falling edge for the period remainder
        remainder = 0
        while dut.hsync.value == 1:
            await RisingEdge(dut.clk)
            remainder += 1

        period = pulse_width + remainder
        assert period == 800, f"Line {line}: HSYNC period = {period}, expected 800"

    dut._log.info(f"PASS: HSYNC timing correct over {NUM_LINES} lines (period=800, pulse=96)")


@cocotb.test()
async def test_vsync_timing(dut):
    """VSYNC period = 420,000 clocks, pulse width = 1,600 clocks (active low)."""
    clock = Clock(dut.clk, 40, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    # Wait for first vsync falling edge
    while dut.vsync.value == 0:
        await RisingEdge(dut.clk)
    while dut.vsync.value == 1:
        await RisingEdge(dut.clk)
    # vsync just went low

    # Measure pulse width
    pulse_width = 0
    while dut.vsync.value == 0:
        await RisingEdge(dut.clk)
        pulse_width += 1

    assert pulse_width == 1600, f"VSYNC pulse width = {pulse_width}, expected 1600"
    dut._log.info(f"PASS: VSYNC pulse width = {pulse_width}")

    # Measure period: count until next falling edge
    remainder = 0
    while dut.vsync.value == 1:
        await RisingEdge(dut.clk)
        remainder += 1

    period = pulse_width + remainder
    assert period == 420000, f"VSYNC period = {period}, expected 420000"
    dut._log.info(f"PASS: VSYNC period = {period}")


@cocotb.test()
async def test_video_active(dut):
    """video_active should be HIGH only in the 640x480 visible region."""
    clock = Clock(dut.clk, 40, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    errors = 0

    # Check every clock for 2 full lines at the start (visible region)
    for _ in range(2 * 800):
        px = int(dut.pixel_x.value)
        py = int(dut.pixel_y.value)
        va = int(dut.video_active.value)
        expected = 1 if (px < 640 and py < 480) else 0
        if va != expected:
            dut._log.error(f"video_active={va} at ({px},{py}), expected {expected}")
            errors += 1
        await RisingEdge(dut.clk)

    # Jump to line 479 (last visible) and check transition to 480 (blanking)
    # Run to start of line 479: need (479 * 800 - 2*800) more clocks from current position
    await ClockCycles(dut.clk, 477 * 800)

    for _ in range(2 * 800):
        px = int(dut.pixel_x.value)
        py = int(dut.pixel_y.value)
        va = int(dut.video_active.value)
        expected = 1 if (px < 640 and py < 480) else 0
        if va != expected:
            dut._log.error(f"video_active={va} at ({px},{py}), expected {expected}")
            errors += 1
        await RisingEdge(dut.clk)

    assert errors == 0, f"video_active had {errors} errors"
    dut._log.info("PASS: video_active correct at visible/blanking boundaries")
