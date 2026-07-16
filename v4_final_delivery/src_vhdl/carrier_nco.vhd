----------------------------------------------------------------------------------
-- Module Name: carrier_nco (Numerically Controlled Oscillator)
-- Description:
--   This module is responsible for generating the local Sine and Cosine waves used
--   to "wipe off" the carrier frequency from the incoming GPS signal. 
--   
--   It uses a "Phase Accumulator" architecture. Every clock cycle, it adds a 
--   frequency 'step' to a running phase total. The top 8 bits of this phase 
--   are then used as an index (0 to 255) to look up the Sine and Cosine values 
--   in a pre-computed ROM table.
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity carrier_nco is
    port (
        clk         : in  std_logic;
        rst_n       : in  std_logic;
        en          : in  std_logic;
        load        : in  std_logic;
        step        : in  std_logic_vector(31 downto 0);
        phase_init  : in  std_logic_vector(31 downto 0);
        sin_out     : out std_logic_vector(15 downto 0);
        cos_out     : out std_logic_vector(15 downto 0);
        phase_out   : out std_logic_vector(31 downto 0)
    );
end carrier_nco;

----------------------------------------------------------------------------------
-- THEORY OF OPERATION: Numerically Controlled Oscillator (NCO)
-- 
-- In digital signal processing (DSP), we cannot generate continuous analog Sine waves.
-- Instead, we generate discrete digital samples. An NCO does this using two main parts:
--
-- 1. The Phase Accumulator (phase_reg)
--    Think of a circle (0 to 360 degrees). Our 32-bit register represents that circle,
--    where 0 is 0 degrees, and 4,294,967,295 (max 32-bit value) is 359.999... degrees.
--    Every clock cycle, we add a "step" value. 
--    - A small step means we travel around the circle slowly (Low Frequency).
--    - A large step means we travel around the circle very fast (High Frequency).
--    - Because it is a 32-bit integer, when it overflows, it naturally wraps back to 
--      0 degrees seamlessly! This is why phase accumulators are so powerful.
--
-- 2. The Look-Up Table (LUT)
--    We need the Sine of our current phase angle. Calculating Sine mathematically in 
--    hardware is slow. Instead, we pre-calculate 256 points of a Sine wave and store
--    them in memory (ROM). We take the top 8 bits of our 32-bit phase register 
--    (because 2^8 = 256) and use it as an address to fetch the pre-calculated Sine value.
--
-- Data Format (Q1.15):
--    Hardware doesn't do floating-point math (like 0.707) easily. Instead, we use
--    Fixed-Point math. A Sine wave goes from -1.0 to +1.0. 
--    We multiply the floating-point Sine wave by 32,767 (the max value of a 16-bit 
--    signed integer). So +1.0 becomes 32767, and -1.0 becomes -32767. This is called
--    Q1.15 format (1 sign bit, 15 fractional bits).
----------------------------------------------------------------------------------
architecture rtl of carrier_nco is
    -- 256-entry SIN LUT (Q1.15 format, scaled by 32768)
    type rom_type is array (0 to 255) of signed(15 downto 0);
    
    constant SIN_LUT : rom_type := (
        to_signed(0, 16), to_signed(804, 16), to_signed(1608, 16), to_signed(2410, 16),
        to_signed(3212, 16), to_signed(4011, 16), to_signed(4808, 16), to_signed(5602, 16),
        to_signed(6393, 16), to_signed(7179, 16), to_signed(7962, 16), to_signed(8739, 16),
        to_signed(9512, 16), to_signed(10278, 16), to_signed(11039, 16), to_signed(11793, 16),
        to_signed(12539, 16), to_signed(13279, 16), to_signed(14010, 16), to_signed(14732, 16),
        to_signed(15446, 16), to_signed(16151, 16), to_signed(16846, 16), to_signed(17530, 16),
        to_signed(18204, 16), to_signed(18868, 16), to_signed(19520, 16), to_signed(20161, 16),
        to_signed(20787, 16), to_signed(21402, 16), to_signed(22005, 16), to_signed(22594, 16),
        to_signed(23170, 16), to_signed(23731, 16), to_signed(24278, 16), to_signed(24811, 16),
        to_signed(25329, 16), to_signed(25832, 16), to_signed(26319, 16), to_signed(26790, 16),
        to_signed(27245, 16), to_signed(27683, 16), to_signed(28105, 16), to_signed(28510, 16),
        to_signed(28898, 16), to_signed(29269, 16), to_signed(29621, 16), to_signed(29956, 16),
        to_signed(30273, 16), to_signed(30571, 16), to_signed(30852, 16), to_signed(31113, 16),
        to_signed(31356, 16), to_signed(31580, 16), to_signed(31785, 16), to_signed(31971, 16),
        to_signed(32137, 16), to_signed(32285, 16), to_signed(32412, 16), to_signed(32521, 16),
        to_signed(32609, 16), to_signed(32678, 16), to_signed(32728, 16), to_signed(32757, 16),
        to_signed(32767, 16), to_signed(32757, 16), to_signed(32728, 16), to_signed(32678, 16),
        to_signed(32609, 16), to_signed(32521, 16), to_signed(32412, 16), to_signed(32285, 16),
        to_signed(32137, 16), to_signed(31971, 16), to_signed(31785, 16), to_signed(31580, 16),
        to_signed(31356, 16), to_signed(31113, 16), to_signed(30852, 16), to_signed(30571, 16),
        to_signed(30273, 16), to_signed(29956, 16), to_signed(29621, 16), to_signed(29269, 16),
        to_signed(28898, 16), to_signed(28510, 16), to_signed(28105, 16), to_signed(27683, 16),
        to_signed(27245, 16), to_signed(26790, 16), to_signed(26319, 16), to_signed(25832, 16),
        to_signed(25329, 16), to_signed(24811, 16), to_signed(24278, 16), to_signed(23731, 16),
        to_signed(23170, 16), to_signed(22594, 16), to_signed(22005, 16), to_signed(21402, 16),
        to_signed(20787, 16), to_signed(20161, 16), to_signed(19520, 16), to_signed(18868, 16),
        to_signed(18204, 16), to_signed(17530, 16), to_signed(16846, 16), to_signed(16151, 16),
        to_signed(15446, 16), to_signed(14732, 16), to_signed(14010, 16), to_signed(13279, 16),
        to_signed(12539, 16), to_signed(11793, 16), to_signed(11039, 16), to_signed(10278, 16),
        to_signed(9512, 16), to_signed(8739, 16), to_signed(7962, 16), to_signed(7179, 16),
        to_signed(6393, 16), to_signed(5602, 16), to_signed(4808, 16), to_signed(4011, 16),
        to_signed(3212, 16), to_signed(2410, 16), to_signed(1608, 16), to_signed(804, 16),
        to_signed(0, 16), to_signed(-804, 16), to_signed(-1608, 16), to_signed(-2410, 16),
        to_signed(-3212, 16), to_signed(-4011, 16), to_signed(-4808, 16), to_signed(-5602, 16),
        to_signed(-6393, 16), to_signed(-7179, 16), to_signed(-7962, 16), to_signed(-8739, 16),
        to_signed(-9512, 16), to_signed(-10278, 16), to_signed(-11039, 16), to_signed(-11793, 16),
        to_signed(-12539, 16), to_signed(-13279, 16), to_signed(-14010, 16), to_signed(-14732, 16),
        to_signed(-15446, 16), to_signed(-16151, 16), to_signed(-16846, 16), to_signed(-17530, 16),
        to_signed(-18204, 16), to_signed(-18868, 16), to_signed(-19520, 16), to_signed(-20161, 16),
        to_signed(-20787, 16), to_signed(-21402, 16), to_signed(-22005, 16), to_signed(-22594, 16),
        to_signed(-23170, 16), to_signed(-23731, 16), to_signed(-24278, 16), to_signed(-24811, 16),
        to_signed(-25329, 16), to_signed(-25832, 16), to_signed(-26319, 16), to_signed(-26790, 16),
        to_signed(-27245, 16), to_signed(-27683, 16), to_signed(-28105, 16), to_signed(-28510, 16),
        to_signed(-28898, 16), to_signed(-29269, 16), to_signed(-29621, 16), to_signed(-29956, 16),
        to_signed(-30273, 16), to_signed(-30571, 16), to_signed(-30852, 16), to_signed(-31113, 16),
        to_signed(-31356, 16), to_signed(-31580, 16), to_signed(-31785, 16), to_signed(-31971, 16),
        to_signed(-32137, 16), to_signed(-32285, 16), to_signed(-32412, 16), to_signed(-32521, 16),
        to_signed(-32609, 16), to_signed(-32678, 16), to_signed(-32728, 16), to_signed(-32757, 16),
        to_signed(-32767, 16), to_signed(-32757, 16), to_signed(-32728, 16), to_signed(-32678, 16),
        to_signed(-32609, 16), to_signed(-32521, 16), to_signed(-32412, 16), to_signed(-32285, 16),
        to_signed(-32137, 16), to_signed(-31971, 16), to_signed(-31785, 16), to_signed(-31580, 16),
        to_signed(-31356, 16), to_signed(-31113, 16), to_signed(-30852, 16), to_signed(-30571, 16),
        to_signed(-30273, 16), to_signed(-29956, 16), to_signed(-29621, 16), to_signed(-29269, 16),
        to_signed(-28898, 16), to_signed(-28510, 16), to_signed(-28105, 16), to_signed(-27683, 16),
        to_signed(-27245, 16), to_signed(-26790, 16), to_signed(-26319, 16), to_signed(-25832, 16),
        to_signed(-25329, 16), to_signed(-24811, 16), to_signed(-24278, 16), to_signed(-23731, 16),
        to_signed(-23170, 16), to_signed(-22594, 16), to_signed(-22005, 16), to_signed(-21402, 16),
        to_signed(-20787, 16), to_signed(-20161, 16), to_signed(-19520, 16), to_signed(-18868, 16),
        to_signed(-18204, 16), to_signed(-17530, 16), to_signed(-16846, 16), to_signed(-16151, 16),
        to_signed(-15446, 16), to_signed(-14732, 16), to_signed(-14010, 16), to_signed(-13279, 16),
        to_signed(-12539, 16), to_signed(-11793, 16), to_signed(-11039, 16), to_signed(-10278, 16),
        to_signed(-9512, 16), to_signed(-8739, 16), to_signed(-7962, 16), to_signed(-7179, 16),
        to_signed(-6393, 16), to_signed(-5602, 16), to_signed(-4808, 16), to_signed(-4011, 16),
        to_signed(-3212, 16), to_signed(-2410, 16), to_signed(-1608, 16), to_signed(-804, 16)
    );
    
    constant COS_LUT : rom_type := (
        to_signed(32767, 16), to_signed(32757, 16), to_signed(32728, 16), to_signed(32678, 16),
        to_signed(32609, 16), to_signed(32521, 16), to_signed(32412, 16), to_signed(32285, 16),
        to_signed(32137, 16), to_signed(31971, 16), to_signed(31785, 16), to_signed(31580, 16),
        to_signed(31356, 16), to_signed(31113, 16), to_signed(30852, 16), to_signed(30571, 16),
        to_signed(30273, 16), to_signed(29956, 16), to_signed(29621, 16), to_signed(29269, 16),
        to_signed(28898, 16), to_signed(28510, 16), to_signed(28105, 16), to_signed(27683, 16),
        to_signed(27245, 16), to_signed(26790, 16), to_signed(26319, 16), to_signed(25832, 16),
        to_signed(25329, 16), to_signed(24811, 16), to_signed(24278, 16), to_signed(23731, 16),
        to_signed(23170, 16), to_signed(22594, 16), to_signed(22005, 16), to_signed(21402, 16),
        to_signed(20787, 16), to_signed(20161, 16), to_signed(19520, 16), to_signed(18868, 16),
        to_signed(18204, 16), to_signed(17530, 16), to_signed(16846, 16), to_signed(16151, 16),
        to_signed(15446, 16), to_signed(14732, 16), to_signed(14010, 16), to_signed(13279, 16),
        to_signed(12539, 16), to_signed(11793, 16), to_signed(11039, 16), to_signed(10278, 16),
        to_signed(9512, 16), to_signed(8739, 16), to_signed(7962, 16), to_signed(7179, 16),
        to_signed(6393, 16), to_signed(5602, 16), to_signed(4808, 16), to_signed(4011, 16),
        to_signed(3212, 16), to_signed(2410, 16), to_signed(1608, 16), to_signed(804, 16),
        to_signed(0, 16), to_signed(-804, 16), to_signed(-1608, 16), to_signed(-2410, 16),
        to_signed(-3212, 16), to_signed(-4011, 16), to_signed(-4808, 16), to_signed(-5602, 16),
        to_signed(-6393, 16), to_signed(-7179, 16), to_signed(-7962, 16), to_signed(-8739, 16),
        to_signed(-9512, 16), to_signed(-10278, 16), to_signed(-11039, 16), to_signed(-11793, 16),
        to_signed(-12539, 16), to_signed(-13279, 16), to_signed(-14010, 16), to_signed(-14732, 16),
        to_signed(-15446, 16), to_signed(-16151, 16), to_signed(-16846, 16), to_signed(-17530, 16),
        to_signed(-18204, 16), to_signed(-18868, 16), to_signed(-19520, 16), to_signed(-20161, 16),
        to_signed(-20787, 16), to_signed(-21402, 16), to_signed(-22005, 16), to_signed(-22594, 16),
        to_signed(-23170, 16), to_signed(-23731, 16), to_signed(-24278, 16), to_signed(-24811, 16),
        to_signed(-25329, 16), to_signed(-25832, 16), to_signed(-26319, 16), to_signed(-26790, 16),
        to_signed(-27245, 16), to_signed(-27683, 16), to_signed(-28105, 16), to_signed(-28510, 16),
        to_signed(-28898, 16), to_signed(-29269, 16), to_signed(-29621, 16), to_signed(-29956, 16),
        to_signed(-30273, 16), to_signed(-30571, 16), to_signed(-30852, 16), to_signed(-31113, 16),
        to_signed(-31356, 16), to_signed(-31580, 16), to_signed(-31785, 16), to_signed(-31971, 16),
        to_signed(-32137, 16), to_signed(-32285, 16), to_signed(-32412, 16), to_signed(-32521, 16),
        to_signed(-32609, 16), to_signed(-32678, 16), to_signed(-32728, 16), to_signed(-32757, 16),
        to_signed(-32767, 16), to_signed(-32757, 16), to_signed(-32728, 16), to_signed(-32678, 16),
        to_signed(-32609, 16), to_signed(-32521, 16), to_signed(-32412, 16), to_signed(-32285, 16),
        to_signed(-32137, 16), to_signed(-31971, 16), to_signed(-31785, 16), to_signed(-31580, 16),
        to_signed(-31356, 16), to_signed(-31113, 16), to_signed(-30852, 16), to_signed(-30571, 16),
        to_signed(-30273, 16), to_signed(-29956, 16), to_signed(-29621, 16), to_signed(-29269, 16),
        to_signed(-28898, 16), to_signed(-28510, 16), to_signed(-28105, 16), to_signed(-27683, 16),
        to_signed(-27245, 16), to_signed(-26790, 16), to_signed(-26319, 16), to_signed(-25832, 16),
        to_signed(-25329, 16), to_signed(-24811, 16), to_signed(-24278, 16), to_signed(-23731, 16),
        to_signed(-23170, 16), to_signed(-22594, 16), to_signed(-22005, 16), to_signed(-21402, 16),
        to_signed(-20787, 16), to_signed(-20161, 16), to_signed(-19520, 16), to_signed(-18868, 16),
        to_signed(-18204, 16), to_signed(-17530, 16), to_signed(-16846, 16), to_signed(-16151, 16),
        to_signed(-15446, 16), to_signed(-14732, 16), to_signed(-14010, 16), to_signed(-13279, 16),
        to_signed(-12539, 16), to_signed(-11793, 16), to_signed(-11039, 16), to_signed(-10278, 16),
        to_signed(-9512, 16), to_signed(-8739, 16), to_signed(-7962, 16), to_signed(-7179, 16),
        to_signed(-6393, 16), to_signed(-5602, 16), to_signed(-4808, 16), to_signed(-4011, 16),
        to_signed(-3212, 16), to_signed(-2410, 16), to_signed(-1608, 16), to_signed(-804, 16),
        to_signed(0, 16), to_signed(804, 16), to_signed(1608, 16), to_signed(2410, 16),
        to_signed(3212, 16), to_signed(4011, 16), to_signed(4808, 16), to_signed(5602, 16),
        to_signed(6393, 16), to_signed(7179, 16), to_signed(7962, 16), to_signed(8739, 16),
        to_signed(9512, 16), to_signed(10278, 16), to_signed(11039, 16), to_signed(11793, 16),
        to_signed(12539, 16), to_signed(13279, 16), to_signed(14010, 16), to_signed(14732, 16),
        to_signed(15446, 16), to_signed(16151, 16), to_signed(16846, 16), to_signed(17530, 16),
        to_signed(18204, 16), to_signed(18868, 16), to_signed(19520, 16), to_signed(20161, 16),
        to_signed(20787, 16), to_signed(21402, 16), to_signed(22005, 16), to_signed(22594, 16),
        to_signed(23170, 16), to_signed(23731, 16), to_signed(24278, 16), to_signed(24811, 16),
        to_signed(25329, 16), to_signed(25832, 16), to_signed(26319, 16), to_signed(26790, 16),
        to_signed(27245, 16), to_signed(27683, 16), to_signed(28105, 16), to_signed(28510, 16),
        to_signed(28898, 16), to_signed(29269, 16), to_signed(29621, 16), to_signed(29956, 16),
        to_signed(30273, 16), to_signed(30571, 16), to_signed(30852, 16), to_signed(31113, 16),
        to_signed(31356, 16), to_signed(31580, 16), to_signed(31785, 16), to_signed(31971, 16),
        to_signed(32137, 16), to_signed(32285, 16), to_signed(32412, 16), to_signed(32521, 16),
        to_signed(32609, 16), to_signed(32678, 16), to_signed(32728, 16), to_signed(32757, 16)
    );

    signal phase_reg : unsigned(31 downto 0); -- The main phase accumulator
    signal lut_idx   : unsigned(7 downto 0);  -- The top 8 bits used for the lookup

begin

    --------------------------------------------------------------------------------
    -- Phase Accumulator Process
    -- This is a sequential logic block (triggered by the rising edge of the clock).
    -- It handles resetting, loading a starting phase, and stepping the phase forward.
    --------------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                -- Asynchronous reset (active low)
                phase_reg <= (others => '0');
            else
                if load = '1' then
                    -- Load the initial phase given by the software/Python
                    phase_reg <= unsigned(phase_init);
                elsif en = '1' then
                    -- Add the Doppler-shifted step value to the current phase
                    -- This automatically wraps around when it overflows 32 bits!
                    phase_reg <= phase_reg + unsigned(step);
                end if;
            end if;
        end if;
    end process;
    
    -- Extract the top 8 bits of the 32-bit phase for the ROM lookup
    -- 32 bits gives incredible frequency precision, but we only need 256 points for the sine wave.
    lut_idx <= phase_reg(31 downto 24);
    
    --------------------------------------------------------------------------------
    -- ROM Lookup and Output Register Process
    -- We register the outputs to ensure clean timing (pipelining).
    --------------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            -- Fetch the Sine and Cosine values from the ROM using the index
            sin_out <= std_logic_vector(SIN_LUT(to_integer(lut_idx)));
            cos_out <= std_logic_vector(COS_LUT(to_integer(lut_idx)));
            
            -- Also output the current phase so the software can read it back via AXI
            phase_out <= std_logic_vector(phase_reg);
        end if;
    end process;

end rtl;
