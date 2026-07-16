# What is a "Sample"? (Continuous Waves vs Discrete Actions)

### The Misconception
*What do we mean by a single sample? Does the GPS satellite transmit, wait, and then transmit again?*

### The Reality
The satellite absolutely does **NOT** wait! It transmits a continuous, never-ending, uninterrupted analog radio wave, much like a continuously flowing river or a beam of light.

### So, what is a "Sample"?
A "sample" is an action that *our hardware* takes here on Earth. 

The ADC (Analog-to-Digital Converter) takes a microscopic "snapshot" of that continuous analog wave's voltage level. It is exactly like recording a continuously flowing river by snapping digital photographs very quickly.

If we are sampling at **16.368 MHz**, it means our ADC chip is taking **16,368,000 voltage snapshots every single second**. 
The river never stops flowing; we are just freezing it into millions of tiny, discrete numbers so a digital computer can process it.

We do this for the *entire sky* at once. A single sample contains the overlapping, mashed-together radio energy of every single GPS satellite in view, all frozen at that exact nanosecond in time.
