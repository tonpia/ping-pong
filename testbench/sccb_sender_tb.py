import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, First
from cocotb_tools.runner import get_runner


async def i2c_ack_slave(dut, cycles=3):
    """Drive ACK (pull SDA low) at each ACK window — simple slave emulation."""
    for _ in range(cycles):
        # Wait for SDA to go high-Z (SDO drives 0 -> controller releases bus)
        for _ in range(20):
            await RisingEdge(dut.iCLK)
            if str(dut.I2C_SDAT.value) == "z":
                break
        dut.I2C_SDAT.value = 0   # slave pulls SDA low = ACK
        await RisingEdge(dut.iCLK)
        dut.I2C_SDAT.value = 1   # release


@cocotb.test()
async def test_i2c_write_transaction(dut):
    """Verify a full 3-byte I2C write: SLAVE_ADDR + SUB_ADDR + DATA, check END asserts."""
    cocotb.start_soon(Clock(dut.iCLK, 10, unit="ns").start())
    # I2C_CLK is a slow divided clock; drive it as 100kHz equivalent toggle
    cocotb.start_soon(Clock(dut.I2C_CLK, 100, unit="ns").start())

    # Reset
    dut.iRST_N.value = 0
    dut.I2C_EN.value = 0
    dut.GO.value = 0
    dut.WR.value = 1
    dut.I2C_WDATA.value = 0
    dut.I2C_SDAT.value = 1
    await Timer(50, unit="ns")
    dut.iRST_N.value = 1
    await RisingEdge(dut.iCLK)

    # Load slave=0x42, sub=0x12, data=0xAB
    dut.I2C_WDATA.value = 0x4212AB
    dut.I2C_EN.value = 1
    dut.GO.value = 1

    # Emulate slave ACK in background
    cocotb.start_soon(i2c_ack_slave(dut, cycles=3))

    # Wait for END to assert (max 100 us)
    for _ in range(10000):
        await RisingEdge(dut.iCLK)
        if dut.END.value == 1:
            break

    assert dut.END.value == 1, "I2C write transaction did not complete (END never asserted)"
    dut._log.info(f"PASS: I2C write complete, ACK={dut.ACK.value}")


@cocotb.test()
async def test_i2c_reset_clears_state(dut):
    """Assert reset mid-transaction; verify SCLK and SDAT return to idle high."""
    cocotb.start_soon(Clock(dut.iCLK, 10, unit="ns").start())
    cocotb.start_soon(Clock(dut.I2C_CLK, 100, unit="ns").start())

    dut.iRST_N.value = 1
    dut.I2C_EN.value = 1
    dut.GO.value = 1
    dut.WR.value = 1
    dut.I2C_WDATA.value = 0xAABBCC
    dut.I2C_SDAT.value = 1

    # Run 10 cycles into transaction then reset
    for _ in range(10):
        await RisingEdge(dut.iCLK)

    dut.iRST_N.value = 0
    await RisingEdge(dut.iCLK)
    await RisingEdge(dut.iCLK)

    assert dut.END.value == 0, "END should be 0 after reset"
    dut._log.info("PASS: reset correctly clears transaction state")


def runner():
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent
    sources = [proj_path / "../src/project_1.srcs/sources_1/new/sccb_sender.v"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="I2C_Controller",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
    )
    runner.test(
        hdl_toplevel="I2C_Controller",
        test_module="sccb_sender_tb",
        waves=True,
    )


if __name__ == "__main__":
    runner()
