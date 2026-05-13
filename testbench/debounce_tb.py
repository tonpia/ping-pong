import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from cocotb_tools.runner import get_runner


@cocotb.test()
async def test_debounce_glitch_rejected(dut):
    """Short glitch pulses shorter than counter threshold must not assert output."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    dut.i.value = 0
    await Timer(50, unit="ns")

    # Apply a short burst (100 cycles — far less than 0xFFFFFF)
    dut.i.value = 1
    for _ in range(100):
        await RisingEdge(dut.clk)
    dut.i.value = 0
    await Timer(20, unit="ns")

    assert dut.o.value == 0, f"Glitch passed debounce: o={dut.o.value}"
    dut._log.info("PASS: short glitch correctly rejected")


def runner():
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent
    sources = [proj_path / "../src/project_1.srcs/sources_1/new/debounce.v"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="debounce",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
    )
    runner.test(
        hdl_toplevel="debounce",
        test_module="debounce_tb",
        waves=True,
    )


if __name__ == "__main__":
    runner()
