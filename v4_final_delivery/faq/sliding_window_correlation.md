# The Sliding Window (Correlation Math)

One of the most important concepts in a GPS receiver is **Correlation**. This is how the receiver finds the satellite's signal buried underneath all the background noise, and exactly aligns its internal clock with the satellite's clock.

We can think of this as a **"Sliding Window."**

Let's do the math on paper using a simple 4-chip PRN code: `[1, 1, -1, -1]`.

---

## 📡 The Setup

Imagine the satellite transmits its unique 4-chip code over and over again. 
Because of the time it takes the radio wave to travel from space to your antenna, the code arrives with a **Time Delay**.

- **Incoming Signal (Delayed):** `[ ?, ?, 1, 1, -1, -1, ?, ? ]`
- **Our Local Guess (The Window):** `[ 1, 1, -1, -1 ]`

To find the signal, our FPGA creates a "sliding window." It generates its own local copy of the `[1, 1, -1, -1]` code, and slides it across the incoming data one step at a time. At every step, it multiplies the incoming data by the local code and sums up the result.

---

## 🧮 Doing the Math on Paper

Let's assume our incoming data array looks like this (the satellite code is buried in the middle):
**Incoming:** `[-1, 1, 1, 1, -1, -1, 1, -1]`

Let's slide our Local Code `[1, 1, -1, -1]` across this data from left to right.

### Shift 0 (No Alignment)
```text
Incoming:   [-1,  1,  1,  1, -1, -1,  1, -1]
Local:      [ 1,  1, -1, -1]
--------------------------------------------
Multiply:   (-1) (1) (-1)(-1) 
Sum:        -1 + 1 - 1 - 1  =  -2  (No Match)
```

### Shift 1 (Sliding right by 1)
```text
Incoming:   [-1,  1,  1,  1, -1, -1,  1, -1]
Local:           [1,  1, -1, -1]
--------------------------------------------
Multiply:        (1) (1) (-1)(1) 
Sum:             1 + 1 - 1 + 1  =  +2  (No Match)
```

### Shift 2 (Perfect Alignment!)
```text
Incoming:   [-1,  1,  1,  1, -1, -1,  1, -1]
Local:               [1,  1, -1, -1]
--------------------------------------------
Multiply:            (1) (1) (1) (1)   <-- Notice how all negatives cancelled out! (-1 * -1 = 1)
Sum:                 1 + 1 + 1 + 1  =  +4  (MASSIVE SPIKE!)
```

### Shift 3 (Sliding past it)
```text
Incoming:   [-1,  1,  1,  1, -1, -1,  1, -1]
Local:                   [1,  1, -1, -1]
--------------------------------------------
Multiply:                (1)(-1)(1) (-1) 
Sum:                     1 - 1 + 1 - 1  =  0   (No Match)
```

---

## 🎯 The Conclusion

When you plot the sums from our sliding window (`-2, +2, +4, 0`), you get a massive spike exactly at **Shift 2**. 

This spike tells the receiver two critical things:
1. **The Satellite is Present:** The spike proves we found the signal in the noise.
2. **The Exact Time Delay:** The fact that the spike happened at Shift 2 tells us exactly how long the signal took to reach us. This time delay is the core of how GPS calculates your physical distance to the satellite!

In the real FPGA, instead of a 4-chip code, it uses a 1,023-chip code, and it does this sliding math millions of times a second!
