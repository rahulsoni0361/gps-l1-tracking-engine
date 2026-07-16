# Dealing with Unaligned Samples: Code Phase

### The Problem
*“But I don't start sampling it just at the beginning of the packet. So once again 1 ms might contain data from the previous packet and the current packet.”*

This is an incredibly sharp observation. You have just identified the exact reason why GPS receivers must perform **Acquisition** and **Code Tracking**!

When you turn on your ADC (like the MAX2771) and grab a random 1-millisecond chunk of data (16,368 samples), you are blindly grabbing a slice of time. The satellite did not wait for you. 
Therefore, your random 1ms slice will almost certainly contain the *tail end* of one PRN barcode, and the *beginning* of the next PRN barcode.

### Why is this a problem?
If you take this misaligned 1ms chunk of live data, and multiply it by your perfectly aligned internal PRN barcode, the math fails. 
* The first half of your math is multiplying against the end of the previous PRN code.
* The second half of your math is multiplying against the beginning of the new PRN code.
Because the codes are misaligned, the multiplication looks like random noise, and the "Integrate and Dump" sum will equal `0`. You will see nothing.

### The Solution: Finding the Code Phase

To solve this, we don't try to change when the antenna samples the data. The antenna just streams data constantly. Instead, we **shift our internal PRN barcode** to match the live data!

#### 1. The Acquisition Phase (The Brute Force Search)
During startup, the receiver does a brute-force search. 
It takes that random 1ms chunk of live data, and it tests it against every possible shift of the internal PRN barcode.
If your ADC samples at 16 MHz, there are 16,368 possible ways the barcode could be shifted. The receiver shifts its internal barcode by 1 sample, multiplies, and checks the sum. Then it shifts by 2 samples, multiplies, and checks the sum. 

Eventually, it shifts its internal barcode to the exact nanosecond where the live data's PRN code begins. **BOOM.** The math perfectly aligns, the "Integrate and Dump" outputs a massive positive spike, and the receiver now knows the exact **Code Phase** (the exact starting sample of the satellite's packet).

#### 2. The Tracking Phase (The Delay Lock Loop)
Once you find the start of the packet, you lock onto it.
Because the satellite is moving, the start of the next packet might arrive slightly sooner or slightly later than exactly 1 millisecond.
The **Delay Lock Loop (DLL)** uses the Early and Late correlators to constantly monitor the edges of the packet. If it sees the packet shifting slightly to the left, it tells the FPGA to shift your internal barcode slightly to the left to keep them perfectly locked together.

### Summary
You are exactly right: a random 1ms block of samples will contain pieces of two different packets. The entire point of the GPS baseband engine is to digitally slide our internal reference backwards and forwards in time until it perfectly overlays the invisible boundaries of the live packets falling from space.
