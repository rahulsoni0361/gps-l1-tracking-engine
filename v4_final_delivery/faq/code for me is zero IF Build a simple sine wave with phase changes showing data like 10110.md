# Understanding Zero IF and Phase Changes (With Code)

When a signal is mixed down to "Zero IF", the high-frequency carrier wave is completely stripped away. What remains is a baseband signal centered exactly at 0 Hz. If it's a sine wave at exactly 0 Hz, it's basically a flat DC line (or a complex vector that doesn't spin).

However, in GPS (which uses BPSK - Binary Phase Shift Keying), the data `1` and `0` are represented by **180-degree phase shifts**. When the phase shifts, the wave flips upside down (positive becomes negative).

Here is a Python script that visually demonstrates what happens when we take a carrier wave, apply BPSK data (`1, 0, 1, 1, 0`), and then mix it down to Zero IF!

```python
import numpy as np
import matplotlib.pyplot as plt

# Parameters
fs = 1000        # Sample rate
t = np.arange(0, 1, 1/fs) # 1 second of time
fc = 10          # Carrier frequency (10 Hz for visualization)

# 1. Create the Data (1, 0, 1, 1, 0)
# We map 1 to +1, and 0 to -1 for phase flipping
data_bits = [1, -1, 1, 1, -1]
# Stretch the bits over the time array (each bit lasts 0.2 seconds)
data_signal = np.repeat(data_bits, len(t) // len(data_bits))

# 2. Create the Carrier Wave
carrier = np.cos(2 * np.pi * fc * t)

# 3. Transmit Signal: Multiply Carrier by Data (BPSK)
# This creates phase shifts where the data flips
transmitted_rf = carrier * data_signal

# 4. Mix down to Zero-IF at the Receiver
# Multiply by the exact same carrier frequency to wipe it off
local_oscillator = np.cos(2 * np.pi * fc * t)
mixed_signal = transmitted_rf * local_oscillator

# 5. Low-Pass Filter (Simple moving average)
# This removes the high-frequency double-carrier component created by mixing
window_size = 20
zero_if_signal = np.convolve(mixed_signal, np.ones(window_size)/window_size, mode='same')

# Plotting
plt.figure(figsize=(10, 8))

plt.subplot(4, 1, 1)
plt.plot(t, data_signal, 'r', drawstyle='steps-pre')
plt.title("Original Data (10110)")
plt.ylim(-1.5, 1.5)

plt.subplot(4, 1, 2)
plt.plot(t, carrier, 'gray')
plt.title("High Frequency Carrier Wave")

plt.subplot(4, 1, 3)
plt.plot(t, transmitted_rf, 'b')
plt.title("Transmitted RF Signal (Notice Phase Flips)")

plt.subplot(4, 1, 4)
plt.plot(t, zero_if_signal, 'g')
plt.title("Zero-IF Output (Recovered Data after Mixing & Filtering)")

plt.tight_layout()
plt.show()
```

### What does "Zero Frequency" look like?
At exactly 0 Hz, the signal stops oscillating up and down over time. It becomes a flat line (DC voltage) representing the amplitude/phase of the data. When the data flips, the DC line flips from positive to negative. 
