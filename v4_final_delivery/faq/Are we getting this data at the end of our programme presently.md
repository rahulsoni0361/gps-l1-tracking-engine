# Are we getting Ephemeris Data at the end of our program right now?

### The Short Answer:
**Not yet.** In Milestone 1 (and the current FPGA implementation in Milestone 2/3), we have only built the **Acquisition** and **Tracking Loops**. 

### What are we getting right now?
Right now, your program outputs:
1. **Correlation Peaks:** Proving we can find the satellite in the noise.
2. **Locked NCO Frequencies:** Proving we can track the Doppler shift over time.
3. **Locked PRN Delays:** Proving we can track the Code Phase.
4. **I/Q Prompt Values:** A steady stream of values that occasionally flip from positive to negative.

### What is missing? (The Next Steps)
Those `I_Prompt` values flipping from positive to negative **ARE** the hidden Ephemeris data! 

However, to actually turn those flips into a physical X, Y, Z location on a map, you need to build a **Navigation Decoder** in software (typically on the ARM processor).

Here is what the software must do next:
1. **Bit Synchronization:** The tracking loop dumps data every 1 millisecond. But a GPS data bit lasts 20 milliseconds. The software must figure out exactly which 1ms dump represents the "start" of a new 20ms bit.
2. **Frame Synchronization (Finding the Preamble):** Once you have clean 20ms bits (1s and 0s), you have to find the start of a "Subframe". The software scans the 1s and 0s looking for a specific 8-bit pattern: `10001011` (The Preamble).
3. **Parity Checking:** The satellite sends checksums to ensure the data wasn't corrupted by noise. The software must run the math to verify the bits are perfect.
4. **Decoding the Ephemeris:** Once the frames are verified, the software parses the binary data into actual floating-point numbers: "The satellite's exact orbital trajectory is X, the time is exactly Y."
5. **PVT Calculation (Position, Velocity, Time):** Finally, using the Ephemeris data from 4 different satellites, and the exact nanosecond delay from your Tracking Loops, you run the massive Least-Squares math equation to calculate your location on Earth.

**Conclusion:** 
You have built the Engine. The Engine is perfectly tracking the satellites and pulling the raw binary data out of the noise. The next logical step (often handled in later milestones or higher-level software like RTKLIB) is to write the parser that reads those binary bits and does the geometry math!
