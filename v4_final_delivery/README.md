# GPS Tracker (Native VHDL Implementation)

This repository contains the final Native VHDL implementation of the GPS Baseband Tracking Core. It replaces the previous HLS (C++) design with a clean, modular, and fully hand-written VHDL architecture, significantly improving code readability, maintainability, and resource optimization.

## Delivery Contents

This package contains the following structure:

* **`src_vhdl/`**: The core VHDL design files. This is the hand-written IP logic.
* **`vivado/`**: Contains the `build_vivado.tcl` script to automatically generate the Vivado project, block design, and synthesize the bitstream.
* **`deploy/`**: Contains the final compiled bitstream (`tracker_hw.bit`), hardware handoff (`.hwh`), and Python scripts used for running and validating the hardware on the PYNQ-Z2 board.
* **`instructions/`**: Contains specific documentation, including the hardware verification methodology used to prove bit-accuracy against the Python reference model.

## Features & Improvements

1. **Native VHDL**: The entire DSP datapath (Carrier NCO, Code NCO, Gold Code Generators, and Correlators) was rewritten from the ground up in structural VHDL.
2. **Fixed-Point Precision**: Mathematical operations utilize explicitly defined fixed-point arithmetic (`signed`/`unsigned`) preventing implicit wrap-around errors.
3. **Pipeline Optimization**: Features precise, hand-tuned latency matching (e.g. 2-cycle I/Q data shift registers to align perfectly with the 2-cycle Carrier/Code NCO delays).
4. **No "Black Box" State Machines**: Auto-generated nested state machines from HLS have been completely eliminated. Data flow is controlled explicitly by AXI-Stream `TVALID` enabling deterministic, single-cycle integration throughput.
5. **AXI-Lite Compatibility**: The VHDL wrappers match the exact AXI-Lite register mapping of the original design, allowing software to seamlessly transition from HLS to VHDL without any modifications to the Host CPU tracking scripts.

## Quick Start (Hardware Deployment)

If you have a PYNQ-Z2 board available, you can immediately test the pre-compiled bitstream:

1. Copy the contents of the `deploy/` folder to the PYNQ board.
2. Ensure you have your `L1_20211202_084700_4MHz_IQ.bin` raw GPS data file available.
3. Run the tracking script on the PS (ARM processor) via SSH:
   ```bash
   sudo python3 track_on_hw.py
   ```
4. The output `hardware_tracking_v3.json` will contain the tracking history for PRNs 16, 26, 29, and 31.
