----------------------------------------------------------------------------------
-- Module Name: code_nco (Code Numerically Controlled Oscillator)
-- Description:
--   This module is responsible for stepping through the GPS C/A (Gold) code.
--   Because the GPS satellites are moving, the code rate experiences Doppler shift.
--   This module uses a 32-bit Phase Accumulator to precisely track the fractional
--   chip index (the Q16.16 format phase).
--
--   Crucially, to track the satellite, we need three copies of the C/A code:
--     1. Early  (-0.5 chips)
--     2. Prompt ( 0.0 chips)
--     3. Late   (+0.5 chips)
--   This module calculates those three indices and uses three separate instances 
--   of our ROM to fetch the Early, Prompt, and Late (+1/-1) signals simultaneously!
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity code_nco is
    port (
        clk         : in  std_logic;
        rst_n       : in  std_logic;
        en          : in  std_logic;
        load        : in  std_logic;
        prn         : in  std_logic_vector(4 downto 0);
        step        : in  std_logic_vector(31 downto 0);
        phase_init  : in  std_logic_vector(31 downto 0);
        
        -- Replica outputs (+1 or -1, mapped to signed integers)
        code_e      : out signed(7 downto 0);
        code_p      : out signed(7 downto 0);
        code_l      : out signed(7 downto 0);
        
        phase_out   : out std_logic_vector(31 downto 0)
    );
end code_nco;

----------------------------------------------------------------------------------
-- THEORY OF OPERATION: Code NCO and Early/Prompt/Late Replicas
--
-- Why do we need an NCO for the Code?
-- The GPS C/A code is transmitted at exactly 1.023 MHz. However, because the 
-- satellite is moving relative to the receiver, the signal is compressed or 
-- stretched (Doppler Shift). To stay synchronized, we cannot just step through 
-- our local code array at exactly 1.023 MHz; we must constantly adjust our speed.
-- We use a 32-bit Phase Accumulator (just like the Carrier NCO) to step through
-- the code indices at the precisely calculated Doppler-shifted rate.
--
-- What is Q16.16 format?
-- The C/A code has 1023 "chips" (bits) per millisecond. We use a 32-bit integer
-- to represent our current position. 
-- - The top 16 bits represent the integer chip index (0, 1, 2... 1022).
-- - The bottom 16 bits represent the fractional phase between chips.
-- This allows us to track our position with sub-chip (1/65536th of a chip) precision!
--
-- Why Early, Prompt, and Late?
-- To track the satellite perfectly, we need a feedback loop (Delay Lock Loop - DLL).
-- - 'Prompt' is where we *think* the satellite currently is.
-- - 'Early' looks half a chip ahead (-0.5).
-- - 'Late' looks half a chip behind (+0.5).
-- By comparing the energy in the Early vs Late correlators, the software DLL can
-- calculate an error and tell this NCO to speed up or slow down!
----------------------------------------------------------------------------------
architecture rtl of code_nco is
    constant HALF_CHIP : integer := 32768; -- 1 << 15 (0.5 in Q16.16)
    constant CODE_MAX  : integer := 1023 * 65536;
    
    signal phase_reg : unsigned(31 downto 0);
    
    signal phase_e   : unsigned(31 downto 0);
    signal phase_p   : unsigned(31 downto 0);
    signal phase_l   : unsigned(31 downto 0);
    
    signal idx_e     : std_logic_vector(9 downto 0);
    signal idx_p     : std_logic_vector(9 downto 0);
    signal idx_l     : std_logic_vector(9 downto 0);
    
    signal bit_e     : std_logic;
    signal bit_p     : std_logic;
    signal bit_l     : std_logic;
    
    component ca_code_rom is
        port (
            clk      : in  std_logic;
            prn      : in  std_logic_vector(4 downto 0);
            chip_idx : in  std_logic_vector(9 downto 0);
            code_out : out std_logic
        );
    end component;
    
begin

    --------------------------------------------------------------------------------
    -- Phase Accumulator Process (The NCO)
    -- This handles the Q16.16 fractional phase tracking of the Gold code.
    --------------------------------------------------------------------------------
    process(clk)
        variable phase_next : unsigned(32 downto 0);
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                phase_reg <= (others => '0');
            else
                if load = '1' then
                    phase_reg <= unsigned(phase_init);
                elsif en = '1' then
                    -- GAP 4 FIX: Use a 33-bit addition to prevent silent 32-bit overflows
                    -- Add the Doppler-shifted code step.
                    -- If we hit the end of the 1023-chip sequence (CODE_MAX), wrap around.
                    phase_next := ("0" & phase_reg) + ("0" & unsigned(step));
                    if phase_next >= to_unsigned(CODE_MAX, 33) then
                        phase_reg <= phase_next(31 downto 0) - to_unsigned(CODE_MAX, 32);
                    else
                        phase_reg <= phase_next(31 downto 0);
                    end if;
                end if;
            end if;
        end if;
    end process;
    
    phase_out <= std_logic_vector(phase_reg);
    
    --------------------------------------------------------------------------------
    -- Early / Prompt / Late Phase Calculation
    -- Prompt is exactly our current phase. Early and Late are offset by 0.5 chips.
    --------------------------------------------------------------------------------
    phase_p <= phase_reg;
    
    process(phase_reg)
        variable p_e : signed(32 downto 0);
        variable p_l : signed(32 downto 0);
    begin
        -- Early (phase - 0.5 chips)
        p_e := signed("0" & phase_reg) - to_signed(HALF_CHIP, 33);
        if p_e < 0 then
            phase_e <= unsigned(p_e(31 downto 0)) + to_unsigned(CODE_MAX, 32); -- Wrap around negative
        else
            phase_e <= unsigned(p_e(31 downto 0));
        end if;
        
        -- Late (phase + 0.5 chips)
        p_l := signed("0" & phase_reg) + to_signed(HALF_CHIP, 33);
        if p_l >= to_signed(CODE_MAX, 33) then
            phase_l <= unsigned(p_l(31 downto 0)) - to_unsigned(CODE_MAX, 32); -- Wrap around overflow
        else
            phase_l <= unsigned(p_l(31 downto 0));
        end if;
    end process;

    -- Extract integer chip indices (the top 16 bits of the Q16.16 phase)
    -- This provides an index between 0 and 1022 for the ROM lookup.
    idx_p <= std_logic_vector(phase_p(25 downto 16));
    idx_e <= std_logic_vector(phase_e(25 downto 16));
    idx_l <= std_logic_vector(phase_l(25 downto 16));
    
    --------------------------------------------------------------------------------
    -- ROM Instances
    -- We instantiate the Block RAM three times. Since the FPGA has hundreds of BRAMs,
    -- this is a highly efficient way to get three read ports.
    --------------------------------------------------------------------------------
    rom_e : ca_code_rom port map(clk => clk, prn => prn, chip_idx => idx_e, code_out => bit_e);
    rom_p : ca_code_rom port map(clk => clk, prn => prn, chip_idx => idx_p, code_out => bit_p);
    rom_l : ca_code_rom port map(clk => clk, prn => prn, chip_idx => idx_l, code_out => bit_l);
    
    --------------------------------------------------------------------------------
    -- NRZ Mapping (Binary to Bipolar)
    -- In standard DSP, a binary '0' becomes +1, and a binary '1' becomes -1.
    -- This maps the binary sequence to signed numbers for the correlator multiplier.
    --------------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if bit_e = '0' then code_e <= to_signed(1, 8); else code_e <= to_signed(-1, 8); end if;
            if bit_p = '0' then code_p <= to_signed(1, 8); else code_p <= to_signed(-1, 8); end if;
            if bit_l = '0' then code_l <= to_signed(1, 8); else code_l <= to_signed(-1, 8); end if;
        end if;
    end process;

end rtl;
