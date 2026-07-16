----------------------------------------------------------------------------------
-- Module Name: correlator (Correlator Datapath)
-- Description:
--   This is the heavy-lifting DSP engine of the GPS tracker. It takes the incoming
--   raw I/Q samples from the antenna (via AXI-Stream) and mixes them with the 
--   locally generated Carrier Sine/Cosine and C/A Code replicas.
--
--   It uses a highly optimized 4-Stage Pipelined architecture to allow for 
--   single-cycle processing at high clock speeds:
--     Stage 1: Baseband Multiplication (I/Q * Carrier)
--     Stage 2: Baseband Addition (Generates wiped-off bI and bQ)
--     Stage 3: Code Multiplication (bI/bQ * Early/Prompt/Late Code)
--     Stage 4: Accumulation (Adds the result to the running 1ms total)
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity correlator is
    port (
        clk         : in  std_logic;
        rst_n       : in  std_logic;
        en          : in  std_logic;
        dump        : in  std_logic; -- When high, latches outputs and resets accumulators
        
        -- Inputs
        I_raw       : in  signed(7 downto 0);
        Q_raw       : in  signed(7 downto 0);
        sin_val     : in  signed(15 downto 0);
        cos_val     : in  signed(15 downto 0);
        code_e      : in  signed(7 downto 0);
        code_p      : in  signed(7 downto 0);
        code_l      : in  signed(7 downto 0);
        
        -- Outputs (latched when dump = '1')
        Ie_acc      : out signed(31 downto 0);
        Qe_acc      : out signed(31 downto 0);
        Ip_acc      : out signed(31 downto 0);
        Qp_acc      : out signed(31 downto 0);
        Il_acc      : out signed(31 downto 0);
        Ql_acc      : out signed(31 downto 0)
    );
end correlator;

----------------------------------------------------------------------------------
-- THEORY OF OPERATION: The Correlator (Integrate & Dump)
--
-- What does a Correlator do?
-- A correlator measures how similar two signals are. In GPS, the incoming signal 
-- is buried deep beneath the thermal noise floor (SNR is negative!). To find the 
-- signal, we multiply the noisy incoming signal by our perfectly clean, locally 
-- generated sine waves and C/A code (this multiplication is called "Wipeoff").
-- 
-- Why "Integrate and Dump"?
-- After wiping off the carrier and code, the signal is still mostly noise. 
-- However, noise is random (it averages to zero over time), while the true GPS 
-- signal is not. We use an Accumulator to add up (Integrate) all the samples 
-- over a 1ms period (4000 samples). 
-- - The random noise cancels itself out over the 4000 additions.
-- - The actual GPS signal builds up to a massive peak!
-- After 1ms, we "Dump" the result into the output registers for the Zynq 
-- processor to read, and we reset the accumulators back to zero for the next 1ms.
--
-- Why pipelining?
-- Doing 6 massive multiplications and additions in a single clock cycle would 
-- cause severe timing violations on the FPGA (the path from registers to logic 
-- would be too long). By breaking the math into 4 stages separated by flip-flops
-- (registers), we can run the FPGA at extremely high clock speeds (100MHz+). 
-- It takes 4 clock cycles for a sample to reach the accumulator, but a new sample 
-- enters the pipeline every single clock cycle!
----------------------------------------------------------------------------------
architecture rtl of correlator is

    -- Pipeline Stage 1: Baseband wipeoff multiplication
    -- GAP 3 FIX: Add 2-cycle pipeline delay to incoming raw samples.
    -- The Carrier and Code NCOs both have a 2-cycle latency. We must delay the 
    -- incoming samples by 2 cycles so they align with the correct NCO outputs!
    signal I_raw_d1, I_raw_d2 : signed(7 downto 0);
    signal Q_raw_d1, Q_raw_d2 : signed(7 downto 0);
    
    signal I_cos, Q_sin, I_sin, Q_cos : signed(23 downto 0);
    
    -- Pipeline Stage 2: Baseband addition (I/Q generation)
    signal bI, bQ : signed(24 downto 0);
    
    -- Pipeline delays for code replicas to match baseband delay
    signal code_e_d1, code_p_d1, code_l_d1 : signed(7 downto 0);
    signal code_e_d2, code_p_d2, code_l_d2 : signed(7 downto 0);
    
    -- Pipeline Stage 3: Code wipeoff (multiplication)
    signal Ie_mult, Qe_mult : signed(32 downto 0);
    signal Ip_mult, Qp_mult : signed(32 downto 0);
    signal Il_mult, Ql_mult : signed(32 downto 0);
    
    -- Accumulators
    signal Ie_sum, Qe_sum : signed(31 downto 0);
    signal Ip_sum, Qp_sum : signed(31 downto 0);
    signal Il_sum, Ql_sum : signed(31 downto 0);
    
    -- Control signals pipeline
    signal en_d1, en_d2, en_d3 : std_logic;
    signal dump_d1, dump_d2, dump_d3 : std_logic;

begin

    process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                en_d1 <= '0'; en_d2 <= '0'; en_d3 <= '0';
                dump_d1 <= '0'; dump_d2 <= '0'; dump_d3 <= '0';
                Ie_sum <= (others => '0'); Qe_sum <= (others => '0');
                Ip_sum <= (others => '0'); Qp_sum <= (others => '0');
                Il_sum <= (others => '0'); Ql_sum <= (others => '0');
                Ie_acc <= (others => '0'); Qe_acc <= (others => '0');
                Ip_acc <= (others => '0'); Qp_acc <= (others => '0');
                Il_acc <= (others => '0'); Ql_acc <= (others => '0');
                
                I_raw_d1 <= (others => '0'); I_raw_d2 <= (others => '0');
                Q_raw_d1 <= (others => '0'); Q_raw_d2 <= (others => '0');
            else
                --------------------------------------------------------------------------------
                -- Control Signal Pipeline
                -- Because the datapath takes 3 clock cycles to reach the accumulator,
                -- the 'en' and 'dump' signals must be delayed by 3 clock cycles as well 
                -- so they arrive at the exact same time as the data!
                --------------------------------------------------------------------------------
                en_d1 <= en;       en_d2 <= en_d1;       en_d3 <= en_d2;
                dump_d1 <= dump; dump_d2 <= dump_d1; dump_d3 <= dump_d2;
                
                --------------------------------------------------------------------------------
                -- Stage 1: Initial Multiplies (Carrier Wipeoff Part 1)
                -- We multiply the delayed incoming raw I/Q samples by the local Sine/Cosine.
                -- I_cos = I * cos, Q_sin = Q * sin, etc.
                --------------------------------------------------------------------------------
                I_raw_d1 <= I_raw;       I_raw_d2 <= I_raw_d1;
                Q_raw_d1 <= Q_raw;       Q_raw_d2 <= Q_raw_d1;
                
                I_cos <= I_raw_d2 * cos_val;
                Q_sin <= Q_raw_d2 * sin_val;
                I_sin <= I_raw_d2 * sin_val;
                Q_cos <= Q_raw_d2 * cos_val;
                
                -- Delay the code replicas so they stay aligned with the data
                code_e_d1 <= code_e; code_p_d1 <= code_p; code_l_d1 <= code_l;
                
                --------------------------------------------------------------------------------
                -- Stage 2: Baseband sums (Carrier Wipeoff Part 2)
                -- Complex multiplication: (I + jQ) * (cos + j*sin)
                -- bI = I*cos - Q*sin
                -- bQ = -I*sin - Q*cos
                --------------------------------------------------------------------------------
                bI <= resize(I_cos, 25) - resize(Q_sin, 25);
                bQ <= resize(-I_sin, 25) - resize(Q_cos, 25);
                
                -- Delay the code replicas again
                code_e_d2 <= code_e_d1; code_p_d2 <= code_p_d1; code_l_d2 <= code_l_d1;
                
                --------------------------------------------------------------------------------
                -- Stage 3: Code Multiplies (Code Wipeoff)
                -- Multiply the baseband signal (bI/bQ) by the Early, Prompt, and Late codes.
                -- Since code is just +1 or -1, this is effectively just a sign flip!
                --------------------------------------------------------------------------------
                Ie_mult <= bI * code_e_d2; Qe_mult <= bQ * code_e_d2;
                Ip_mult <= bI * code_p_d2; Qp_mult <= bQ * code_p_d2;
                Il_mult <= bI * code_l_d2; Ql_mult <= bQ * code_l_d2;
                
                --------------------------------------------------------------------------------
                -- Stage 4: Accumulation (Integrate and Dump)
                -- This is the final stage. We add the multiplied results to our running totals.
                --------------------------------------------------------------------------------
                if dump_d3 = '1' then
                    -- "Dump" phase: The 1ms epoch is over!
                    -- 1. Latch the final sums into the output registers for the Zynq processor.
                    Ie_acc <= Ie_sum; Qe_acc <= Qe_sum;
                    Ip_acc <= Ip_sum; Qp_acc <= Qp_sum;
                    Il_acc <= Il_sum; Ql_acc <= Ql_sum;
                    
                    -- 2. Reset the running totals for the next 1ms epoch.
                    -- If 'en' is high, we immediately start accumulating the first sample of the new epoch!
                    if en_d3 = '1' then
                        Ie_sum <= resize(Ie_mult, 32); Qe_sum <= resize(Qe_mult, 32);
                        Ip_sum <= resize(Ip_mult, 32); Qp_sum <= resize(Qp_mult, 32);
                        Il_sum <= resize(Il_mult, 32); Ql_sum <= resize(Ql_mult, 32);
                    else
                        Ie_sum <= (others => '0'); Qe_sum <= (others => '0');
                        Ip_sum <= (others => '0'); Qp_sum <= (others => '0');
                        Il_sum <= (others => '0'); Ql_sum <= (others => '0');
                    end if;
                elsif en_d3 = '1' then
                    -- Normal Accumulation: Add the new sample to the running totals.
                    Ie_sum <= Ie_sum + resize(Ie_mult, 32); Qe_sum <= Qe_sum + resize(Qe_mult, 32);
                    Ip_sum <= Ip_sum + resize(Ip_mult, 32); Qp_sum <= Qp_sum + resize(Qp_mult, 32);
                    Il_sum <= Il_sum + resize(Il_mult, 32); Ql_sum <= Ql_sum + resize(Ql_mult, 32);
                end if;
            end if;
        end if;
    end process;

end rtl;
