# Synchronizing with the NCO: Time and Frequency

### *Are we synchronizing with the exact frequency of the satellite using the NCO?*
**Yes, absolutely.** The satellite transmits at 1575.42 MHz, but because it is moving, the Doppler effect changes this frequency (e.g., to 1575.423 MHz). The NCO must spin at the exact opposite frequency to cancel out this Doppler shift so the result is perfectly 0 Hz.

### *What do we have to do every millisecond, every time?*
The tracking loop operates on a strict 1-millisecond heartbeat. Here is the exact sequence of events that happens 1,000 times every single second:

1. **The Dump:** At the end of the millisecond, the FPGA dumps the 6 Correlator values (I_Early, Q_Early, I_Prompt, Q_Prompt, I_Late, Q_Late).
2. **The Discriminator:** The CPU takes the `I_Prompt` and `Q_Prompt` and runs them through a math function (like `atan(Q/I)`). This function calculates the **Phase Error** (e.g., "The NCO is 2 degrees ahead of the satellite").
3. **The Loop Filter:** The CPU passes that error into a Loop Filter (a digital PID controller). The filter smooths out the noisy error and converts it into a velocity command.
4. **The Update:** The CPU calculates a new "Tuning Word" and writes it to the FPGA. This tells the NCO: *"Slow down your frequency by 0.5 Hz for the next millisecond to let the satellite catch up."*
5. **Repeat:** The FPGA integrates for another millisecond using the new, corrected NCO frequency.

### *How much time does it take to get in sync?*
When the tracking loop first turns on (right after Acquisition), the NCO is close to the right frequency, but the phase is messy. 

* **Pull-in Time:** It typically takes the PLL **10 to 50 milliseconds** (10 to 50 loops) to adjust the NCO and pull the phase error down to zero.
* **Steady State:** Once it is locked, it stays locked indefinitely, constantly making micro-adjustments every millisecond to fight the satellite's continuous movement.
