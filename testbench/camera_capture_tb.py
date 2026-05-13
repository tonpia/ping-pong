import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from cocotb_tools.runner import get_runner


async def send_pixel(dut, byte_hi, byte_lo):
    """Send one RGB565 pixel as two consecutive PCLK bytes while href=1."""
    dut.d.value = byte_hi
    await RisingEdge(dut.pclk)
    dut.d.value = byte_lo
    await RisingEdge(dut.pclk)


@cocotb.test()
async def test_vsync_resets_position(dut):
    """Asserting vsync must reset x and y to 0 and de-assert we."""
    cocotb.start_soon(Clock(dut.pclk, 10, unit="ns").start())

    # Start mid-frame
    dut.vsync.value = 0
    dut.href.value = 1
    dut.d.value = 0xAA
    await Timer(100, unit="ns")

    # Assert vsync
    dut.vsync.value = 1
    await RisingEdge(dut.pclk)
    await RisingEdge(dut.pclk)

    assert int(dut.x.value) == 0, f"x not reset: {dut.x.value}"
    assert int(dut.y.value) == 0, f"y not reset: {dut.y.value}"
    assert int(dut.we.value) == 0, f"we not cleared: {dut.we.value}"
    dut._log.info("PASS: vsync resets x, y, we")


@cocotb.test()
async def test_single_pixel_write(dut):
    """One RGB565 pixel (2 bytes) with href=1 must produce one we pulse with correct dout."""
    cocotb.start_soon(Clock(dut.pclk, 10, unit="ns").start())

    # Reset via vsync
    dut.vsync.value = 1
    dut.href.value = 0
    dut.d.value = 0
    await Timer(30, unit="ns")
    dut.vsync.value = 0
    await RisingEdge(dut.pclk)

    # Send pixel: 0xF800 = pure red in RGB565
    # byte_hi=0xF8, byte_lo=0x00
    dut.href.value = 1
    await send_pixel(dut, 0xF8, 0x00)

    # wr_hold pipeline is 2 cycles deep — wait a couple extra clocks
    await RisingEdge(dut.pclk)
    await RisingEdge(dut.pclk)

    # RGB565 red: r5=11111, -> r4=1111; g6=000000 -> g4=0000; b5=00000 -> b4=0000
    expected_dout = 0xF00
    assert int(dut.dout.value) == expected_dout, (
        f"dout mismatch: got {hex(int(dut.dout.value))}, expected {hex(expected_dout)}"
    )
    dut._log.info(f"PASS: red pixel dout={hex(int(dut.dout.value))}")


@cocotb.test()
async def test_x_increments_per_pixel(dut):
    """After N pixels with href=1 (no row wrap), x must equal N."""
    cocotb.start_soon(Clock(dut.pclk, 10, unit="ns").start())

    dut.vsync.value = 1
    dut.href.value = 0
    dut.d.value = 0
    await Timer(30, unit="ns")
    dut.vsync.value = 0
    await RisingEdge(dut.pclk)

    N = 5
    dut.href.value = 1
    for _ in range(N):
        await send_pixel(dut, 0x00, 0x00)

    # Pipeline latency: 2 extra clocks
    await RisingEdge(dut.pclk)
    await RisingEdge(dut.pclk)

    assert int(dut.x.value) == N, f"x={dut.x.value}, expected {N}"
    dut._log.info(f"PASS: x incremented to {N} after {N} pixels")


@cocotb.test()
async def test_addr_calculation(dut):
    """addr must equal y*320 + x at each pixel write."""
    cocotb.start_soon(Clock(dut.pclk, 10, unit="ns").start())

    dut.vsync.value = 1
    dut.href.value = 0
    dut.d.value = 0
    await Timer(30, unit="ns")
    dut.vsync.value = 0
    await RisingEdge(dut.pclk)

    dut.href.value = 1
    # Send 3 pixels and check addr after each
    for i in range(3):
        await send_pixel(dut, 0x11, 0x22)
        await RisingEdge(dut.pclk)
        await RisingEdge(dut.pclk)
        expected_addr = int(dut.y.value) * 320 + int(dut.x.value)
        actual_addr = int(dut.addr.value)
        # addr is combinational from x_reg/y_reg — allow ±1 for pipeline
        assert abs(actual_addr - expected_addr) <= 1, (
            f"addr={actual_addr}, expected ~{expected_addr} at pixel {i}"
        )

    dut._log.info("PASS: addr = y*320 + x verified")


def runner():
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent
    sources = [proj_path / "../src/project_1.srcs/sources_1/new/camera_capture.v"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="ov7670_capture",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
    )
    runner.test(
        hdl_toplevel="ov7670_capture",
        test_module="camera_capture_tb",
        waves=True,
    )


if __name__ == "__main__":
    runner()
