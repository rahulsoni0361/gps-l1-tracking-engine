# GPS L1 C/A Baseband Tracking Engine (FPGA)

![FPGA Hardware Validation](v1/src/m2_tracker_vhdl/multichannel_tracking_plot.png) *(Note: Hardware tracking output plot)*

## 🚀 Project Overview

This repository contains a high-performance, real-time **GPS L1 C/A Baseband Tracking Engine** deployed directly onto a Xilinx Zynq-7000 FPGA (PYNQ-Z2). It is capable of tracking multiple GPS satellites simultaneously using a mathematically proven, hardware-in-the-loop validated **Native VHDL** DSP architecture.

Originally prototyped in High-Level Synthesis (HLS), the entire Digital Signal Processing (DSP) datapath was completely reverse-engineered and rewritten into highly optimized, modular, and cycle-accurate structural VHDL. This migration drastically reduced latency, eliminated black-box state machines, and provided true deterministic, single-cycle integration throughput.

## 🧠 Core Architecture (Native VHDL)

The `v4_final_delivery/src_vhdl` directory contains the production-ready IP core. The hardware architecture features:

- **Carrier NCO (`carrier_nco.vhd`)**: A precision 32-bit Phase Accumulator coupled with a custom Sine/Cosine ROM for local carrier wipeoff.
- **Code NCO (`code_nco.vhd`)**: A 33-bit Phase Accumulator designed to handle high-frequency Doppler shifts without mathematical wrap-around vulnerabilities.
- **Gold Code Generator (`ca_code_rom.vhd`)**: Real-time PRN sequence generation for all GPS satellites.
- **Correlators (`correlator.vhd`)**: Cycle-aligned Early, Prompt, and Late (E/P/L) integrators for both In-phase (I) and Quadrature (Q) arms.
- **AXI Integration (`gps_tracker_config/status.vhd`)**: The core communicates with the Zynq ARM processor (PS) via AXI-Stream for high-bandwidth raw RF I/Q data, and AXI-Lite for configuration and status registers.

## 🔬 Mathematical Hardware Verification

Hardware is only as good as the math it computes. To guarantee bit-accuracy, we developed a rigorous **Hardware-in-the-Loop (HIL)** verification pipeline:

1. **Real-world Data Injection**: 1-second snapshots of raw GPS RF I/Q baseband data are loaded into the FPGA's DDR memory and streamed into the PL via DMA.
2. **Hardware Acceleration**: The Native VHDL pipeline processes 1ms epochs (4,000 samples) in real-time, wiping off the carrier and accumulating the correlation results.
3. **Closed-loop Tracking**: The ARM PS reads the hardware integrators via AXI-Lite, runs the Discriminator algorithms, and updates the NCOs for the next epoch.
4. **Validation against Float64 Model**: The hardware tracking history (Doppler frequency, PLL/DLL errors) is exported and mathematically compared against a theoretical pure-Python float64 reference model.

**Verdict**: The Native FPGA hardware successfully locks onto all available satellites (PRN 16, 26, 29, 31) and matches the float64 tracking model to within the acceptable DSP noise floor margin (<20Hz drift over 500 epochs).

## 📂 Repository Structure

* `v4_final_delivery/`: The polished, final delivery folder containing the Native VHDL source code, the Vivado build script, and the Python hardware validation deployment scripts.
* `v3_hls_to_vhdl/`: The development and staging area where the gap analysis and migration from HLS to VHDL took place. Includes XSim simulation testbenches.
* `v2/` & `v1/`: Earlier iterations of the DSP architecture (HLS pipelines and initial Python software models).

## 🛠️ Tech Stack & Skills Demonstrated

- **Hardware Design**: VHDL, RTL Design, Digital Signal Processing (DSP), Clock Domain Crossing, Fixed-Point Arithmetic.
- **FPGA Toolchain**: Xilinx Vivado, IP Packager, Block Design automation via Tcl, XSim.
- **Embedded Software**: Python, PYNQ framework, Zynq Processing System (PS) to Programmable Logic (PL) communication (AXI4-Lite, AXI4-Stream, DMA).
- **Domain Expertise**: GNSS Baseband Processing, Phase-Locked Loops (PLL), Delay-Locked Loops (DLL), Numerically Controlled Oscillators (NCO).
