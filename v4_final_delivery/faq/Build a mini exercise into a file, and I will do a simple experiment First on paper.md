# Manual Correlation Experiment (On Paper)

Let's do the math exactly like the FPGA does it, but scaled down so you can do it on a piece of paper.

### The Setup
Imagine our ADC takes exactly 4 samples per millisecond. 
We have a local PRN barcode for our satellite, which is just 4 chips long:
**Local PRN Code:** `[ +1, -1, +1, -1 ]`

### Scenario 1: The Code is Perfectly Aligned
The live data from the antenna comes in. The satellite is transmitting its PRN code, and we are perfectly aligned. (Assume the carrier wave is already wiped off, so we are at baseband).
**Incoming Data:** `[ +1, -1, +1, -1 ]`

**Step 1: Multiply (The Mixer)**
Multiply the incoming data by the local PRN code, sample by sample.
* Sample 1: `(+1) * (+1) = +1`
* Sample 2: `(-1) * (-1) = +1`
* Sample 3: `(+1) * (+1) = +1`
* Sample 4: `(-1) * (-1) = +1`

**Step 2: Accumulate (Integrate and Dump)**
Add all the results together.
`Sum = (+1) + (+1) + (+1) + (+1) = +4`

**Result:** You get a massive correlation spike of `+4`. You are locked on!

---

### Scenario 2: The Code is Misaligned
Now let's pretend the satellite signal was delayed by 1 sample. The incoming data is shifted to the right. 
**Incoming Data:** `[ -1, +1, -1, +1 ]` (Shifted by 1)

**Step 1: Multiply**
Multiply this shifted incoming data by our local PRN code `[ +1, -1, +1, -1 ]`.
* Sample 1: `(-1) * (+1) = -1`
* Sample 2: `(+1) * (-1) = -1`
* Sample 3: `(-1) * (+1) = -1`
* Sample 4: `(+1) * (-1) = -1`

**Step 2: Accumulate**
Add all the results together.
`Sum = (-1) + (-1) + (-1) + (-1) = -4`

**Result:** In a real PRN code (which is pseudo-random), a shifted code will have a mix of +1s and -1s that perfectly cancel each other out to `0`. (In this highly simplified 4-bit example, it went negative, but for a 1023-bit Gold Code, it will strictly evaluate to nearly 0).

### The "Paper" Exercise for You:
1. Write down a random incoming signal with heavy noise: `[ 2.1, -1.9, 3.0, -2.5 ]`
2. Multiply it by the local PRN: `[ 1, -1, 1, -1 ]`
3. Add it up. 
Notice how the noise is completely ignored, and the positive signal builds up to a large sum! This is Processing Gain in action.
