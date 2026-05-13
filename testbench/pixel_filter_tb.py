import os
from pathlib import Path

import cocotb
from cocotb.triggers import Timer
from cocotb_tools.runner import get_runner


def rgb444(r, g, b):
    return ((r & 0xF) << 8) | ((g & 0xF) << 4) | (b & 0xF)


def expected_gray(r, g, b):
    """Match RTL: gray8 = r*3 + g*6 + b; gray = gray8[7:4]."""
    return ((r * 3 + g * 6 + b) >> 4) & 0xF


async def drive(dut, pixel_in, sw):
    dut.pixel_in.value = pixel_in
    dut.sw.value = sw
    await Timer(1, unit="ns")
    return int(dut.pixel_out.value)


@cocotb.test()
async def test_normal_passthrough(dut):
    """sw[1:0] = 00 -> output matches input."""
    for pix in [0x000, 0xFFF, 0xA5C, 0x789]:
        result = await drive(dut, pix, sw=0b00)
        assert result == pix, f"normal: got {hex(result)}, expected {hex(pix)}"
    dut._log.info("PASS: normal mode passes pixel through unchanged")


@cocotb.test()
async def test_grayscale(dut):
    """sw[1:0] = 01 -> output is replicated gray on R,G,B."""
    for r, g, b in [(0, 0, 0), (0xF, 0xF, 0xF), (0xA, 0x5, 0x3), (0x8, 0x8, 0x8)]:
        gray = expected_gray(r, g, b)
        expected = (gray << 8) | (gray << 4) | gray
        result = await drive(dut, rgb444(r, g, b), sw=0b01)
        assert result == expected, (
            f"gray (r={r},g={g},b={b}): got {hex(result)}, expected {hex(expected)}"
        )
    dut._log.info("PASS: grayscale mode produces weighted-grey replicated to RGB")


@cocotb.test()
async def test_color_channel(dut):
    """sw[1:0] = 10 -> isolate one channel per sw[3:2]."""
    pix = rgb444(0xA, 0xB, 0xC)

    # sw[3:2] = 00 -> red only
    r = await drive(dut, pix, sw=0b00_10)
    assert r == (0xA << 8), f"red-only: got {hex(r)}"

    # sw[3:2] = 01 -> green only
    g = await drive(dut, pix, sw=0b01_10)
    assert g == (0xB << 4), f"green-only: got {hex(g)}"

    # sw[3:2] = 10 -> blue only
    b = await drive(dut, pix, sw=0b10_10)
    assert b == 0xC, f"blue-only: got {hex(b)}"

    # sw[3:2] = 11 -> fallback passthrough
    fb = await drive(dut, pix, sw=0b11_10)
    assert fb == pix, f"fallback: got {hex(fb)}"

    dut._log.info("PASS: color-channel mode isolates R/G/B per sw[3:2]")


@cocotb.test()
async def test_special_invert(dut):
    """sw[1:0]=11, sw[3:2]=00 -> bitwise invert each nibble."""
    pix = rgb444(0xA, 0x5, 0x3)
    result = await drive(dut, pix, sw=0b00_11)
    expected = rgb444(0x5, 0xA, 0xC)
    assert result == expected, f"invert: got {hex(result)}, expected {hex(expected)}"
    dut._log.info(f"PASS: invert result={hex(result)}")


@cocotb.test()
async def test_special_threshold(dut):
    """sw[1:0]=11, sw[3:2]=01 -> threshold by sw[7:4]; gray > thresh -> 0xFFF else 0x000."""
    # Choose a pixel with gray = 0x8 (r=8,g=8,b=8 -> gray8=8*10=80=0x50 -> gray=0x5)
    # Actually: r=0xF,g=0xF,b=0xF -> gray8=15*10=150=0x96 -> gray=0x9
    pix_white = rgb444(0xF, 0xF, 0xF)
    pix_black = rgb444(0x0, 0x0, 0x0)

    # White (gray=9) with thresh=5 -> > thresh -> 0xFFF
    sw_high = (0x5 << 4) | 0b01_11
    out_white = await drive(dut, pix_white, sw=sw_high)
    assert out_white == 0xFFF, f"thresh white: got {hex(out_white)}"

    # Black (gray=0) with thresh=5 -> not > thresh -> 0x000
    out_black = await drive(dut, pix_black, sw=sw_high)
    assert out_black == 0x000, f"thresh black: got {hex(out_black)}"

    # White with thresh=0xF -> not > thresh -> 0x000
    sw_max = (0xF << 4) | 0b01_11
    out_white2 = await drive(dut, pix_white, sw=sw_max)
    assert out_white2 == 0x000, f"thresh white@max: got {hex(out_white2)}"

    dut._log.info("PASS: threshold mode binarizes correctly")


def runner():
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent
    sources = [proj_path / "../src/project_1.srcs/sources_1/new/pixel_filter.v"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="pixel_filter",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
    )
    runner.test(
        hdl_toplevel="pixel_filter",
        test_module="pixel_filter_tb",
        waves=True,
    )


if __name__ == "__main__":
    runner()
