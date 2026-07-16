# Python vs FPGA: Tracking Multiplications Explained

## 1. Did we do this in Python already?
Yes! In Milestone 1, we built a pure software prototype. The "thousands of complex multiplications" were handled by Python using the `NumPy` library. 

### Where is the Python Code?
You can find the exact location of these multiplications in the Python dispatch version here:
[02_track.py](file:///d:/GPS_M1/m1_python/02_track.py#L140-L159)

Here is the full tracking loop snippet, using a `diff` block to highlight the architectural split in different colors for your Obsidian note:
- **Green (`+`)** represents the high-speed math now offloaded to the **FPGA (PL)**.
- **Red (`-`)** represents the low-speed control logic that remains on the **ARM CPU (PS)**.

```diff
+ # ==========================================
+ #  [RUNS ON FPGA - PL / PROGRAMMABLE LOGIC]
+ #  High-speed Math (4,000,000 times a sec)
+ # ==========================================
+ # 1. CARRIER WIPE-OFF
+ ci = np.cos(2*np.pi*(fc*t + phi)).astype(np.float32)
+ cq = -np.sin(2*np.pi*(fc*t + phi)).astype(np.float32)
+ 
+ bi = seg.real*ci - seg.imag*cq
+ bq = seg.real*cq + seg.imag*ci
+ 
+ # 2. CODE GENERATION
+ dp_frac = j * CPS
+ ce = rep(self.code, dp_frac, -0.5, n)
+ cpp = rep(self.code, dp_frac, 0.0, n)
+ cl = rep(self.code, dp_frac, +0.5, n)
+ 
+ # 3. CORRELATION (Multiply and Accumulate)
+ Ip = float(bi@cpp)/n
+ Qp = float(bq@cpp)/n
+ Ie = float(bi@ce)/n
+ Qe = float(bq@ce)/n
+ Il = float(bi@cl)/n
+ Ql = float(bq@cl)/n
+ 
+ E = float(np.sqrt(Ie*Ie+Qe*Qe))
+ L = float(np.sqrt(Il*Il+Ql*Ql))
+ 
- # ==========================================
- #  [RUNS ON ARM CPU - PS / PROCESSING SYSTEM]
- #  Low-speed Control Loops (1,000 times a sec)
- # ==========================================
- self.ch_lock += 1
- 
- # 4. FLL / PLL LOOP FILTER (Adjusting frequency)
- if self.ch_lock < FLL_EPOCHS:
-     if self.ch_lock >= 2:
-         dot = Ip * self.prev_Ip + Qp * self.prev_Qp
-         cross = Ip * self.prev_Qp - Qp * self.prev_Ip
-         if dot != 0.0:
-             err_freq = np.arctan(cross / dot) / (2.0 * np.pi)
-             self.fd -= B_FLL / 0.25 * err_freq
-     pe = float(np.arctan2(Qp, Ip))
- else:
-     if Ip != 0.0:
-         err_phas = np.arctan(Qp / Ip) / (2.0 * np.pi)
-         W = B_PLL / 0.53
-         self.fd += 1.4 * W * (err_phas - self.err_phas_prev) + W * W * err_phas * T
-         self.err_phas_prev = err_phas
-     pe = float(np.arctan2(Qp, Ip))
-     
- # 5. DLL LOOP FILTER (Adjusting code alignment)
- de = 0.0
- if E + L > 0.0:
-     err_code = (E - L) / (E + L) / 2.0 * T / N_CHIPS
-     self.coff -= B_DLL / 0.25 * err_code * T
-     de = (E - L) / (E + L) / 2.0
-     
- self.prev_Ip = Ip
- self.prev_Qp = Qp
```

## 2. Are we doing this in the FPGA now?
Yes! In the current milestones, we are migrating the **Green** calculations to the FPGA's Programmable Logic (PL), and keeping the **Red** calculations in Python/C on the ARM CPU (PS).

### Why the FPGA?
The green calculations above look like just a few lines of Python, but they are hiding a massive amount of math:
- The variable `n` is usually 4,000 samples (for 1 millisecond of data).
- To track **one** satellite, Python has to perform thousands of multiplications to wipe off the carrier (`ci`, `cq`), and then thousands more to do the dot products for Early, Prompt, and Late codes.
- To get a 3D position fix, we need to track **at least 4 satellites** simultaneously, and ideally 8-12.
- A standard CPU processing these NumPy arrays sequentially struggles to keep up with the 4 Million Samples Per Second data rate in real-time. Power consumption is also very high.

**The FPGA Advantage:**
Instead of a CPU executing instructions one by one, an FPGA creates dedicated hardware circuits for these math operations. The FPGA can multiply all the samples for Carrier Wipe-off and Code Correlation simultaneously using massive parallelism. It can run multiple satellite tracking "channels" independently, taking only a fraction of the power and time, while the ARM processor (PS) is left free to handle the lightweight high-level loop filters and navigation math (the **Red** part).

## 3. Step-by-Step Code Explanation

Let's break down exactly what the math is doing in physical terms.

### The FPGA Part (High-Speed Data Processing)
The FPGA receives the raw, noisy digital signal from the antenna at 4 Million Samples Per Second. 

```python
# 1. CARRIER WIPE-OFF
# The satellite is moving rapidly, which creates a Doppler Shift in the radio frequency.
# We generate a local 'sine' and 'cosine' wave at that exact shifted frequency (fc).
ci = np.cos(2*np.pi*(fc*t + phi)).astype(np.float32)
cq = -np.sin(2*np.pi*(fc*t + phi)).astype(np.float32)

# We multiply the incoming raw signal (seg) by our local waves.
# This "wipes off" the radio carrier wave, leaving behind only the baseband data.
bi = seg.real*ci - seg.imag*cq
bq = seg.real*cq + seg.imag*ci

# 2. CODE GENERATION
# GPS satellites transmit a unique repeating pattern called a C/A Code (PRN).
# We generate three perfectly timed local replicas of this code:
ce = rep(self.code, dp_frac, -0.5, n)  # Early: shifted half a chip backward
cpp = rep(self.code, dp_frac, 0.0, n)  # Prompt: perfectly aligned
cl = rep(self.code, dp_frac, +0.5, n)  # Late: shifted half a chip forward

# 3. CORRELATION
# The GPS signal is buried under thermal noise. To "pull" it out of the noise, 
# we multiply the wiped-off signal by our local code and sum all 4,000 samples.
# If they match, the sum grows into a huge spike. If they don't, it sums to zero.
Ip = float(bi@cpp)/n   # In-phase Prompt  (contains the actual Navigation Data)
Qp = float(bq@cpp)/n   # Quadrature Prompt (used to measure phase error)
Ie = float(bi@ce)/n    # Early energy 
Qe = float(bq@ce)/n
Il = float(bi@cl)/n    # Late energy
Ql = float(bq@cl)/n

# Calculate the total magnitude of the Early and Late signals.
E = float(np.sqrt(Ie*Ie+Qe*Qe))
L = float(np.sqrt(Il*Il+Ql*Ql))
```

### The ARM PS Part (Low-Speed Loop Filters)
Once the FPGA boils down 4,000 samples into just 6 correlation numbers (`Ip, Qp, Ie, Qe, Il, Ql`), it hands them to the ARM processor. The ARM uses these numbers to figure out if our local replicas are drifting away from the true satellite signal, and adjusts them for the next millisecond.

```python
# 4. PHASE LOCKED LOOP (PLL) / FREQUENCY LOCKED LOOP (FLL)
# Qp should theoretically be zero if we perfectly wiped off the carrier wave.
# If Qp is not zero, `np.arctan(Qp / Ip)` tells us exactly how many degrees off we are.
err_phas = np.arctan(Qp / Ip) / (2.0 * np.pi)

# We use this error to mathematically update our carrier frequency (self.fd)
# so the FPGA's sine wave is more accurate in the next millisecond.
self.fd += 1.4 * W * (err_phas - self.err_phas_prev) + W * W * err_phas * T

# 5. DELAY LOCKED LOOP (DLL)
# If the Early energy (E) equals the Late energy (L), our Prompt code is perfectly centered.
# If E > L, we are too early. If L > E, we are too late.
err_code = (E - L) / (E + L) / 2.0 * T / N_CHIPS

# We use this error to shift the code phase (self.coff) backward or forward
# so the FPGA's Code Generator stays perfectly aligned.
self.coff -= B_DLL / 0.25 * err_code * T
```


[[once again the same code with comments and explanation what are we doin there ]]