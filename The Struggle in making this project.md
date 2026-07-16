# Engineering Process & Debugging Journal: Building the GPS Tracker

When you look at the final VHDL code, it looks incredibly clean and deterministic. But getting there was an absolute battle. Building a custom GPS L1 Baseband Tracking Engine from scratch is not for the faint of heart. Here are some of the major roadblocks I hit during development, the agonizing hours I spent debugging them, and exactly how I eventually fixed them.

## 1. The HLS Illusion: Why I Scrapped It and Rewrote in Native VHDL
When I first transitioned from my Python float64 model, I figured I would take a shortcut. I tried using Xilinx Vitis HLS (High-Level Synthesis) to compile my tracking loops directly from C++. It sounded great on paper.

**The Struggle:**
I spent an entire week fighting with HLS pragmas (`#pragma HLS PIPELINE`, `#pragma HLS UNROLL`). No matter what I did, the latency was completely non-deterministic. Sometimes the loop took 12 clock cycles, sometimes it took 15. In GPS tracking, phase and timing are everything. If my NCO phase jumps because of pipeline stalls, the PLL completely loses lock.

**The Fix:**
I eventually bit the bullet. I realized that if I wanted true, cycle-accurate control over the DSP datapath, I had to do it the hard way. I ripped out the entire HLS pipeline and rewrote the Carrier NCO, Code NCO, and Correlators in pure, structural Native VHDL. It was a massive step backward in time, but the moment I simulated the native VHDL and saw exactly 1-cycle latency between the NCO and the multiplier, I knew it was the right call.

## 2. The NCO Truncation Bug (The "Jumpy" Phase Issue)
Once I had the VHDL written, I fed it some test data I generated in Python. The output of my VHDL correlator was complete garbage.

**The Struggle:**
I stared at Vivado simulation waveforms for two days. The phase accumulator was incrementing correctly, but the actual Sine/Cosine output from my Lookup Table (ROM) looked jittery. I eventually realized that in my Python code, I was using 64-bit floating-point math. But in the FPGA, I was truncating my 32-bit phase accumulator down to the top 10 bits to address my ROM (1024 entries). 

The problem was *how* I was doing the truncation. I wasn't rounding; I was just slicing the bits off. At certain phase boundaries, this introduced a severe quantization error, causing the NCO to output a frequency that essentially vibrated, throwing off the Costas Loop.

**The Fix:**
I went back into MATLAB/Python and modeled the exact bit-width quantization I was doing in hardware. I realized I needed a larger ROM to reduce the quantization noise. I expanded the ROM from 1024 to 4096 entries (12-bit address) and added a phase-dithering technique to smooth out the jumps. The moment I loaded the new bitstream, the correlator peaks snapped perfectly into place.

## 3. The Dreaded DMA Deadlock (Missing the `TLAST` Signal)
Getting the math right was only half the battle. Getting the data in and out of the ARM processor via AXI DMA was another nightmare.

**The Struggle:**
I set up the AXI DMA to stream exactly 4000 samples of RF data into my IP block and read out 1 set of correlation results. I wrote my Python script (`remote_deploy.py`) on the PYNQ board, called `dma.sendchannel.transfer()`, and... it just hung. It froze completely. 

I restarted the board, tried again. Hung again. I finally hooked up an Integrated Logic Analyzer (ILA) core in Vivado and probed the AXI-Stream interface. 
I saw the data streaming in perfectly. But the DMA never acknowledged that the transfer was done. 

Why? Because my IP block was waiting for the `TLAST` signal (which tells the AXI stream that it's the last byte of the packet), but my DMA configuration wasn't asserting `TLAST` correctly on the 4000th sample because my internal VHDL state machine had an off-by-one error. It was consuming 4001 samples!

**The Fix:**
I added a dedicated sample counter inside my `gps_tracker_config_s_axi.vhd` block. When the counter hits `Packet_Size - 1`, I forcefully flush the pipeline and assert the `TLAST` equivalent out. The DMA immediately unlocked, and data started flowing bidirectionally at 100MHz.

## 4. The 2-Cycle Pipeline Smear
Near the end of the project, I was finally tracking real GPS signals on the board. But my Early, Prompt, and Late correlation peaks were smeared. The Prompt peak wasn't as sharp as my Python model predicted.

**The Struggle:**
I exported the raw I/Q samples out of the FPGA and compared them cycle-by-cycle against my Python float64 trace. I noticed something infuriating. The incoming I/Q data was hitting the multiplier exactly two clock cycles *before* the NCO sine wave that corresponded to it. 
Because my NCO used a Block RAM (BRAM) for the lookup table, the BRAM inherently takes 2 clock cycles to output data after you give it an address. My incoming RF data wasn't being delayed, so the signal was effectively being mixed with the *past* state of the oscillator. 

**The Fix:**
I created a simple 2-stage shift register (`delay_line`) for the incoming I/Q data path. This delayed the raw RF data just enough to perfectly align with the 2-cycle latency of the BRAM lookup. 

I hit synthesize, generated the bitstream, and ran the tracker on the hardware. Seeing that perfect, needle-sharp Prompt correlation peak on the plot was one of the most satisfying moments of my engineering career. All the struggle was worth it.
 
