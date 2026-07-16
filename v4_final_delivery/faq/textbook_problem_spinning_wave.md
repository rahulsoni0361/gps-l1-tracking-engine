# Textbook Problem: Stopping a Spinning Wave

When we say a radio wave is "spinning," we are talking about **Phase**. A wave that is perfectly stationary sits at a constant phase angle (e.g., $0^\circ$). But if the satellite is moving towards us, the Doppler shift increases the frequency. This means the phase angle is constantly increasing over time—the wave is "spinning" in a circle.

Let's do a concrete numerical problem exactly like you would find in an engineering textbook. 

---

## 📚 The Problem Statement

A satellite is transmitting a constant value of `1`. However, because it is moving towards us, the Doppler shift causes the carrier wave to "spin" at a rate of **1 full rotation per second (1 Hz)**. 

Our ADC is taking samples at a rate of **4 samples per second ($F_s = 4$ Hz)**.

**Your Goal:** Calculate the incoming I/Q samples, generate a local counter-spinning wave, and use complex multiplication to "wipe off" the spin and recover the original constant value of `1`.

---

## Step 1: Observe the Incoming Spinning Wave

If the wave makes 1 full rotation ($360^\circ$) every second, and we take 4 samples per second, the wave will spin $90^\circ$ between each sample.

Remember: 
- **I** is the X-axis (Cosine of the angle)
- **Q** is the Y-axis (Sine of the angle)

| Time ($t$) | Phase Angle | Incoming I ($\cos$) | Incoming Q ($\sin$) | Complex Number representation |
| :--- | :--- | :--- | :--- | :--- |
| $t = 0.00$s | $0^\circ$ | `1` | `0` | **`1 + 0j`** |
| $t = 0.25$s | $90^\circ$ | `0` | `1` | **`0 + 1j`** |
| $t = 0.50$s | $180^\circ$ | `-1` | `0` | **`-1 + 0j`** |
| $t = 0.75$s | $270^\circ$ | `0` | `-1` | **`0 - 1j`** |

> [!CAUTION]
> Notice what is happening to our data? The satellite is trying to send us a constant `1`, but because of the Doppler spin, our data is wildly swinging from `1`, to `1j`, to `-1`, to `-1j`. If we tried to decode this right now, it would look like gibberish.

---

## Step 2: Generate the Local "Counter-Spinning" Wave

To stop the spin, the FPGA generates its own local wave (the NCO). If the incoming wave is spinning forward at +1 Hz, our FPGA must generate a wave spinning **backward at -1 Hz**.

This means our local angle decreases by $90^\circ$ every sample.

| Time ($t$) | Local Angle | Local I ($\cos$) | Local Q ($\sin$) | Complex Number representation |
| :--- | :--- | :--- | :--- | :--- |
| $t = 0.00$s | $0^\circ$ | `1` | `0` | **`1 + 0j`** |
| $t = 0.25$s | $-90^\circ$ | `0` | `-1` | **`0 - 1j`** |
| $t = 0.50$s | $-180^\circ$ | `-1` | `0` | **`-1 + 0j`** |
| $t = 0.75$s | $-270^\circ$ | `0` | `1` | **`0 + 1j`** |

---

## Step 3: Carrier Wipe-Off (The Math)

Now for the magic. We multiply the Incoming Wave by the Local Wave. 
Recall the formula for complex multiplication you learned in algebra: 
$(A + jB) \times (C + jD) = (AC - BD) + j(AD + BC)$

Let's do the math manually for each sample!

#### At $t = 0.00$s:
- Incoming: `1 + 0j`
- Local: `1 + 0j`
- Multiplication: $(1\times1 - 0\times0) + j(1\times0 + 0\times1)$ = **`1 + 0j`**

#### At $t = 0.25$s (The incoming wave has spun $90^\circ$):
- Incoming: `0 + 1j`
- Local: `0 - 1j`
- Multiplication: $(0\times0 - 1\times-1) + j(0\times-1 + 1\times0)$
- Multiplication: $(0 - (-1)) + j(0 + 0)$ = **`1 + 0j`**

#### At $t = 0.50$s (The incoming wave has spun $180^\circ$):
- Incoming: `-1 + 0j`
- Local: `-1 + 0j`
- Multiplication: $(-1\times-1 - 0\times0) + j(-1\times0 + 0\times-1)$ = **`1 + 0j`**

#### At $t = 0.75$s (The incoming wave has spun $270^\circ$):
- Incoming: `0 - 1j`
- Local: `0 + 1j`
- Multiplication: $(0\times0 - -1\times1) + j(0\times1 + -1\times0)$
- Multiplication: $(0 - (-1)) + j(0 + 0)$ = **`1 + 0j`**

---

## 🎯 The Conclusion

Look at the final results! 
Before the math, our data was spinning in circles: `(1) -> (1j) -> (-1) -> (-1j)`.
After multiplying by our local counter-spinning wave, the result is completely flat: `(1) -> (1) -> (1) -> (1)`.

We have successfully **stopped the spin** (Carrier Wipe-Off), and recovered the original, stable data that the satellite transmitted! This is exactly what the Python code `bi = seg.real*ci - seg.imag*cq` is doing millions of times a second.
