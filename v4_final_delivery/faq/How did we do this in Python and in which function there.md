# How did we Wipe Doppler and NCOs in Python?

In Milestone 1 (your Python implementation), we implemented exactly what the FPGA does, but using software arrays.

### Where did this happen?
This happens inside the **Tracking Loop** (typically a function named `track()` or inside a `PLL/DLL` loop). 

### How did we do it?
In Python, we mathematically generated a spinning complex sine wave (the digital NCO) that matches the exact Doppler frequency we found during the Acquisition phase.

```python
# 't' is our time array for the current millisecond chunk
# 'carrier_freq' is the remaining Doppler frequency (e.g., +3000 Hz)

# 1. Generate the local NCO (Numerically Controlled Oscillator) in Python
# We use Euler's formula to create a spinning complex wave
local_carrier = np.exp(-1j * 2 * np.pi * carrier_freq * t)

# 2. Wipe off the Doppler Shift
# We take the raw incoming samples (which have the Doppler spin) 
# and multiply them by our locally generated spinning wave.
# This mathematically stops the signal from spinning!
baseband_signal = incoming_samples * local_carrier
```

Once the `baseband_signal` is created, the Doppler is completely wiped out, leaving the signal perfectly at 0 Hz (Zero-IF) so we can multiply it by the PRN code and integrate!

In the FPGA, you don't use `np.exp()`. Instead, you use a hardware **LUT (Look-Up Table)** inside the NCO block, which outputs pre-calculated sine and cosine values at a very fast hardware clock speed.
