# How much is this data?

The GPS L1 C/A code transmits at exactly **1.023 MHz** (1.023 million "chips" or bits per second).

To successfully capture this without losing data, the Nyquist theorem states you MUST sample at a bare minimum of **2x** the signal rate (so > 2.046 MHz). However, 2x can be very "blurry" in practice. Professional GPS receivers (and the MAX2771 chip you are using) typically sample at **4x** (around 4.092 MHz) or even **16x** (16.368 MHz).

If you are sampling at 4x (4 million samples per second), and each sample is a packed 2-bit I/Q word, you are generating about **2 Megabytes of raw data every single second**.

If you sample at 16x, you are taking 16,368,000 samples *every single second* just to look at the sky! This is why normal computer CPUs choke and you need an FPGA to chew through the massive firehose of data instantly.
