# How to run the testbenches

All testbenches use [cocotb](https://docs.cocotb.org/) with [Icarus Verilog](http://iverilog.icarus.com/) as the simulator. They live in this directory and are self-contained — each `*_tb.py` builds its DUT, runs its tests, and writes an FST waveform under `sim_build/`.

## Prerequisites

- Icarus Verilog on `PATH` (`iverilog --version` should work).
- Python environment named `cocotb` with `cocotb` and `cocotb_tools` installed.

## Running

```powershell
conda activate cocotb
cd testbench
python <name>_tb.py
```

Each script builds + runs. Waveforms land in `sim_build/<top>.fst` and the test report in `sim_build/results.xml`.

## Testbench summary

| Testbench | Tests | Time | Coverage |
|---|---|---|---|
| [debounce_tb.py](debounce_tb.py) | 1/1 | ~1s | Short-glitch rejection (100-cycle burst, output stays 0) |
| [con3x3_tb.py](con3x3_tb.py) | 1/1 | ~1s | First-pixel 3x3 convolution result vs Python reference |
| [camera_capture_tb.py](camera_capture_tb.py) | 4/4 | ~1s | vsync resets x/y/we, single RGB565 pixel write, x increments per pixel, addr = y*320 + x |
| [sccb_sender_tb.py](sccb_sender_tb.py) | 2/2 | ~1s | Full 3-byte I2C write with ACK, reset mid-transaction |
| [pixel_filter_tb.py](pixel_filter_tb.py) | 5/5 | ~1s | Normal passthrough, weighted grayscale, R/G/B channel isolate, bitwise invert, threshold binarize |
| [classifier_tb.py](classifier_tb.py) | 3/3 | ~1s | 900-sample accumulator below/above THRESHOLD, score_out tracks running sum |
| [downscale_32x32_tb.py](downscale_32x32_tb.py) | 4/4 | ~1s | Weighted grayscale (no-clip + max-nibble), sample gating (we, x%10, y%7), frame_done 20-cycle pulse after 1024 samples |

Total: **20/20 PASS, ~7s**.

## Ready-to-paste commands

Run from the repo root in PowerShell. Each line activates the env, cds into `testbench/`, and runs one testbench.

```powershell
# debounce          (~1s)
conda activate cocotb; cd testbench; python debounce_tb.py

# con3x3            (~1s)
conda activate cocotb; cd testbench; python con3x3_tb.py

# camera_capture    (~1s)
conda activate cocotb; cd testbench; python camera_capture_tb.py

# sccb_sender       (~1s)
conda activate cocotb; cd testbench; python sccb_sender_tb.py

# pixel_filter      (~1s)
conda activate cocotb; cd testbench; python pixel_filter_tb.py

# classifier        (~1s)
conda activate cocotb; cd testbench; python classifier_tb.py

# downscale_32x32   (~1s)
conda activate cocotb; cd testbench; python downscale_32x32_tb.py
```

Run all seven sequentially:

```powershell
conda activate cocotb; cd testbench; foreach ($tb in 'debounce_tb','con3x3_tb','camera_capture_tb','sccb_sender_tb','pixel_filter_tb','classifier_tb','downscale_32x32_tb') { Write-Host "=== $tb ==="; python "$tb.py" }
```

## View waveforms (GTKWave)

Each run writes its FST to `testbench/sim_build/<top>.fst`. The FST `<top>` matches the `hdl_toplevel` set inside each testbench, **not** the testbench filename.

Run these from inside `testbench/` (same directory you ran the testbench from):

```powershell
gtkwave sim_build\debounce.fst
gtkwave sim_build\conv3x3.fst
gtkwave sim_build\ov7670_capture.fst
gtkwave sim_build\I2C_Controller.fst
gtkwave sim_build\pixel_filter.fst
gtkwave sim_build\classifier.fst
gtkwave sim_build\downscale_32x32.fst
```

From the repo root, prefix with `testbench\` (e.g. `gtkwave testbench\sim_build\debounce.fst`).
