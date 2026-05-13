import os
import random
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from cocotb_tools.runner import get_runner
from cocotbext.uart import UartSink


@cocotb.test()
async def test_uart_tx_alphabet_stress(dut):
    """
    Stress Test: Continuously send 0-9, A-Z from the board to the Laptop
    to test State Machine stability and Handshake timing.
    """

    # 1. Start 100MHz Clock (10ns period)
    cocotb.start_soon(Clock(dut.Clk, 10, unit="ns").start())

    # 2. Create UART Sink (Laptop emulation)
    # Set Baud rate to 115200 as designed
    uart_sink = UartSink(dut.Tx, baud=115200, bits=8, stop_bits=1)

    # 3. System Reset
    dut.Reset.value = 1
    dut.DataValid.value = 0
    dut.fifo_empty.value = 1
    dut.DataIn.value = 0
    await Timer(50, unit="ns")
    dut.Reset.value = 0
    await RisingEdge(dut.Clk)

    # 4. Prepare 0-9, A-Z data
    test_string = b"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"

    dut._log.info("Starting TX 0-9, A-Z Stress Test...")

    for char_code in test_string:
        # --- Step 1: Input data to Interface (Simulate FIFO having data) ---
        dut.DataIn.value = char_code
        dut.fifo_empty.value = 0
        dut.DataValid.value = 1  # TVALID: Inform UART that data is ready to be sent

        # --- Step 2: Wait for acknowledgment (Handshake) ---
        # Wait until UARTTx asserts DataReady (TREADY/ReadEnable) to request data
        while str(dut.DataReady.value) != "1":
            await RisingEdge(dut.Clk)

        # Once UART acknowledges (Ready is High), the FIFO removes the data
        await RisingEdge(dut.Clk)
        dut.DataValid.value = 0
        dut.fifo_empty.value = (
            1  # Simulate FIFO being temporarily empty after data is pulled
        )

        # --- Step 3: Verify the transmitted data frame ---
        # One character takes approximately 10 bits to transmit (Start + 8 Data + Stop)
        # The Sink will wait for the complete frame and return the value for verification
        received_val = await uart_sink.read(1)

        assert received_val[0] == char_code, (
            f"TX Error: Expected {chr(char_code)}({hex(char_code)}), got {hex(received_val[0])}"
        )

        # --- Step 4: Random delay before sending the next character ---
        # To test if UARTTx returns to IDLE and restarts correctly
        idle_wait = random.randint(1, 20)
        await Timer(idle_wait * 10, unit="ns")

        dut._log.info(f"Sent '{chr(char_code)}' successfully (Baud Check Passed)")

    dut._log.info("All characters A-Z transmitted and verified correctly!")
    await Timer(500, unit="ns")


def runner():
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent
    # Specify the path to the source code file in the /src folder
    sources = [proj_path / "../src/UARTTx.v"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="UARTTx",
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
    )
    runner.test(
        hdl_toplevel="UARTTx",
        test_module="uart_tx_tb",  # This Python file name
        waves=True,
    )


if __name__ == "__main__":
    runner()
