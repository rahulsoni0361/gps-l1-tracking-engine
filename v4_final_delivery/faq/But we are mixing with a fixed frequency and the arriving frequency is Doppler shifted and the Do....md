# Tracking Multiple Satellites with Different Doppler Shifts

### The Core Problem
*We are mixing with a fixed frequency (like 1.575 GHz) at the antenna. But the arriving frequency is Doppler shifted, and every satellite has a completely different Doppler shift because they are moving in different directions! How can we track them all at once?*

This is an incredibly smart engineering observation. 

### Step 1: The Dumb Analog Hardware
The analog hardware mixer (like the MAX2771 chip) is "dumb" and strips away a single, fixed 1.575 GHz frequency for the entire sky. 

Because it applies one fixed subtraction to everything, the data coming out of the chip is **NOT** perfectly at 0 Hz for every satellite! 
* Satellite 1 is moving towards us: It might still be spinning at **+3 kHz**.
* Satellite 4 is moving away from us: It might be spinning at **-2 kHz**.

They are all piled on top of each other in the exact same 16 MHz data stream.

### Step 2: The Digital FPGA Solution (NCOs)
This is exactly why your FPGA design has a **Digital Local Oscillator (NCO - Numerically Controlled Oscillator)** built into *every single channel*. 

The FPGA performs a **second downconversion, entirely in digital math!**
* Inside the FPGA, **Channel 1**'s NCO generates a digital sine wave spinning at exactly +3 kHz to wipe off Satellite 1's remaining Doppler.
* Meanwhile, **Channel 4**'s NCO generates a wave spinning at -2 kHz to wipe off Satellite 4's Doppler.

The analog hardware does the heavy lifting (wiping off the massive 1.5 GHz carrier), and the FPGA channels do the per-satellite fine-tuning to perfectly stop their unique Doppler spins!
