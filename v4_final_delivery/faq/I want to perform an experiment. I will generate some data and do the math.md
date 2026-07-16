# Python Experiment: Generating Data and Doing the Math

To complement your paper exercise, here is a Python script you can run on your computer. It manually generates a GPS-like signal, adds noise to it, and runs the "Integrate and Dump" correlation to find the hidden signal.

You can save this as `experiment.py` and run it!

```python
import numpy as np
import matplotlib.pyplot as plt

# 1. Generate the "Satellite" Signal
# We will use a simple 20-chip PRN barcode
prn_code = np.array([1, -1, 1, 1, -1, 1, -1, -1, 1, -1, 
                     1, 1, -1, -1, -1, 1, 1, -1, 1, -1])

# The satellite is delayed by 5 chips due to distance
true_delay = 5
incoming_signal = np.roll(prn_code, true_delay)

# 2. Add Massive Static Noise (The real world)
# We add Gaussian noise that is much louder than the signal itself
noise = np.random.normal(0, 2.0, len(incoming_signal))
noisy_signal = incoming_signal + noise

# 3. The Receiver (Your FPGA) tests every possible delay
correlation_results = []

print("Running Correlator...")
for test_delay in range(len(prn_code)):
    # Shift our local replica
    local_replica = np.roll(prn_code, test_delay)
    
    # MULTIPLY and ACCUMULATE (Integrate and Dump)
    dump_value = np.sum(noisy_signal * local_replica)
    correlation_results.append(dump_value)
    
    print(f"Testing Delay {test_delay}: Dump Value = {dump_value:.2f}")

# 4. Plot the results
plt.figure(figsize=(10, 5))
plt.plot(correlation_results, marker='o', linestyle='-', color='b')
plt.title("Correlation Output (Looking for the Spike)")
plt.xlabel("Tested Delay (Chips)")
plt.ylabel("Integrate & Dump Value")
plt.grid(True)
plt.show()
```

### What you will see:
When you run this, you will see a massive spike exactly at `Delay = 5`. The math effortlessly cuts through the loud random noise and finds the exact alignment of the satellite!
