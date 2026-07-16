----------------------------------------------------------------------------------
-- Module Name: gps_tracker (Top-Level Wrapper)
-- Description:
--   This is the top-level VHDL module. It serves two critical purposes:
--   1. It exactly mimics the AXI-Lite memory map of the old HLS version so the 
--      Python deployment scripts don't have to change at all.
--   2. It instantiates our native, hand-written datapath (NCOs and Correlator)
--      and manages the AXI-Stream interface to feed data into the pipeline.
--
--   The State Machine counts 4,000 samples (1ms of data). When it hits 4,000, 
--   it triggers a 'dump' to save the accumulators, pulses 'ap_done' for the 
--   Zynq processor, and stops until the processor clears it.
----------------------------------------------------------------------------------
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity gps_tracker is
generic (
    C_S_AXI_CONFIG_ADDR_WIDTH : INTEGER := 6;
    C_S_AXI_CONFIG_DATA_WIDTH : INTEGER := 32;
    C_S_AXI_STATUS_ADDR_WIDTH : INTEGER := 8;
    C_S_AXI_STATUS_DATA_WIDTH : INTEGER := 32 );
port (
    ap_clk : IN STD_LOGIC;
    ap_rst_n : IN STD_LOGIC;
    sample_in_TDATA : IN STD_LOGIC_VECTOR (31 downto 0);
    sample_in_TVALID : IN STD_LOGIC;
    sample_in_TREADY : OUT STD_LOGIC;
    
    -- AXI Config Interface
    s_axi_config_AWVALID : IN STD_LOGIC;
    s_axi_config_AWREADY : OUT STD_LOGIC;
    s_axi_config_AWADDR : IN STD_LOGIC_VECTOR (C_S_AXI_CONFIG_ADDR_WIDTH-1 downto 0);
    s_axi_config_WVALID : IN STD_LOGIC;
    s_axi_config_WREADY : OUT STD_LOGIC;
    s_axi_config_WDATA : IN STD_LOGIC_VECTOR (C_S_AXI_CONFIG_DATA_WIDTH-1 downto 0);
    s_axi_config_WSTRB : IN STD_LOGIC_VECTOR (C_S_AXI_CONFIG_DATA_WIDTH/8-1 downto 0);
    s_axi_config_ARVALID : IN STD_LOGIC;
    s_axi_config_ARREADY : OUT STD_LOGIC;
    s_axi_config_ARADDR : IN STD_LOGIC_VECTOR (C_S_AXI_CONFIG_ADDR_WIDTH-1 downto 0);
    s_axi_config_RVALID : OUT STD_LOGIC;
    s_axi_config_RREADY : IN STD_LOGIC;
    s_axi_config_RDATA : OUT STD_LOGIC_VECTOR (C_S_AXI_CONFIG_DATA_WIDTH-1 downto 0);
    s_axi_config_RRESP : OUT STD_LOGIC_VECTOR (1 downto 0);
    s_axi_config_BVALID : OUT STD_LOGIC;
    s_axi_config_BREADY : IN STD_LOGIC;
    s_axi_config_BRESP : OUT STD_LOGIC_VECTOR (1 downto 0);
    interrupt : OUT STD_LOGIC;
    
    -- AXI Status Interface
    s_axi_status_AWVALID : IN STD_LOGIC;
    s_axi_status_AWREADY : OUT STD_LOGIC;
    s_axi_status_AWADDR : IN STD_LOGIC_VECTOR (C_S_AXI_STATUS_ADDR_WIDTH-1 downto 0);
    s_axi_status_WVALID : IN STD_LOGIC;
    s_axi_status_WREADY : OUT STD_LOGIC;
    s_axi_status_WDATA : IN STD_LOGIC_VECTOR (C_S_AXI_STATUS_DATA_WIDTH-1 downto 0);
    s_axi_status_WSTRB : IN STD_LOGIC_VECTOR (C_S_AXI_STATUS_DATA_WIDTH/8-1 downto 0);
    s_axi_status_ARVALID : IN STD_LOGIC;
    s_axi_status_ARREADY : OUT STD_LOGIC;
    s_axi_status_ARADDR : IN STD_LOGIC_VECTOR (C_S_AXI_STATUS_ADDR_WIDTH-1 downto 0);
    s_axi_status_RVALID : OUT STD_LOGIC;
    s_axi_status_RREADY : IN STD_LOGIC;
    s_axi_status_RDATA : OUT STD_LOGIC_VECTOR (C_S_AXI_STATUS_DATA_WIDTH-1 downto 0);
    s_axi_status_RRESP : OUT STD_LOGIC_VECTOR (1 downto 0);
    s_axi_status_BVALID : OUT STD_LOGIC;
    s_axi_status_BREADY : IN STD_LOGIC;
    s_axi_status_BRESP : OUT STD_LOGIC_VECTOR (1 downto 0) 
);
end gps_tracker;

----------------------------------------------------------------------------------
-- THEORY OF OPERATION: System Integration & Memory Maps
--
-- What is AXI?
-- AXI (Advanced eXtensible Interface) is the standard bus protocol used by ARM
-- processors (like the Cortex-A9 inside the Zynq chip) to talk to the FPGA fabric.
-- 
-- 1. AXI-Lite (Memory Mapped):
--    This is used for configuration and status. The processor sees the FPGA as 
--    a block of RAM. 
--    - When the Python script says `tracker.write(0x10, prn)`, the AXI bus routes
--      that data to the exact register inside the `gps_tracker_config_s_axi` module.
--    - When the Python script says `tracker.read(0x30)`, the AXI bus retrieves
--      the `Ip_acc` value from the `gps_tracker_status_s_axi` module.
-- 
-- 2. AXI-Stream (Streaming Data):
--    This is used for high-speed, continuous data (like our antenna samples).
--    There are no addresses. Data flows from a DMA controller directly into 
--    `sample_in_TDATA` whenever `TVALID` is high. 
--
-- Why do we reuse the HLS AXI wrappers?
-- The HLS compiler automatically generated hundreds of lines of VHDL to handle the 
-- complex AXI-Lite handshaking protocol (AWVALID, WREADY, BRESP, etc.). Instead of 
-- re-writing that tedious logic by hand, we instantiate the exact same wrappers 
-- HLS generated. This guarantees that our hand-written DSP pipeline is 100% 
-- plug-and-play compatible with the existing Python deployment scripts!
----------------------------------------------------------------------------------
architecture rtl of gps_tracker is

    -- AXI Config Signals
    signal ap_start : std_logic;
    signal ap_done  : std_logic;
    signal ap_idle  : std_logic;
    signal ap_ready : std_logic;
    
    signal prn                : std_logic_vector(7 downto 0);
    signal carrier_step       : std_logic_vector(31 downto 0);
    signal carrier_phase_init : std_logic_vector(31 downto 0);
    signal code_phase_init    : std_logic_vector(31 downto 0);
    signal code_step          : std_logic_vector(31 downto 0);
    
    -- AXI Status Signals
    signal Ie_acc, Qe_acc : std_logic_vector(31 downto 0);
    signal Ip_acc, Qp_acc : std_logic_vector(31 downto 0);
    signal Il_acc, Ql_acc : std_logic_vector(31 downto 0);
    signal final_carrier_phase : std_logic_vector(31 downto 0);
    signal final_code_phase    : std_logic_vector(31 downto 0);
    
    -- Datapath Signals
    signal I_raw, Q_raw : signed(7 downto 0);
    signal sin_val_slv, cos_val_slv : std_logic_vector(15 downto 0);
    signal sin_val, cos_val : signed(15 downto 0);
    signal code_e, code_p, code_l : signed(7 downto 0);
    
    signal Ie_acc_s, Qe_acc_s : signed(31 downto 0);
    signal Ip_acc_s, Qp_acc_s : signed(31 downto 0);
    signal Il_acc_s, Ql_acc_s : signed(31 downto 0);
    
    -- Control Logic
    signal sample_cnt : unsigned(11 downto 0); -- To count 4000
    signal load_phases : std_logic;
    signal process_en : std_logic;
    signal epoch_dump : std_logic;
    signal running : std_logic;

    component gps_tracker_config_s_axi is
    generic (
        C_S_AXI_ADDR_WIDTH : INTEGER;
        C_S_AXI_DATA_WIDTH : INTEGER);
    port (
        AWVALID : IN STD_LOGIC;
        AWREADY : OUT STD_LOGIC;
        AWADDR : IN STD_LOGIC_VECTOR (C_S_AXI_ADDR_WIDTH-1 downto 0);
        WVALID : IN STD_LOGIC;
        WREADY : OUT STD_LOGIC;
        WDATA : IN STD_LOGIC_VECTOR (C_S_AXI_DATA_WIDTH-1 downto 0);
        WSTRB : IN STD_LOGIC_VECTOR (C_S_AXI_DATA_WIDTH/8-1 downto 0);
        ARVALID : IN STD_LOGIC;
        ARREADY : OUT STD_LOGIC;
        ARADDR : IN STD_LOGIC_VECTOR (C_S_AXI_ADDR_WIDTH-1 downto 0);
        RVALID : OUT STD_LOGIC;
        RREADY : IN STD_LOGIC;
        RDATA : OUT STD_LOGIC_VECTOR (C_S_AXI_DATA_WIDTH-1 downto 0);
        RRESP : OUT STD_LOGIC_VECTOR (1 downto 0);
        BVALID : OUT STD_LOGIC;
        BREADY : IN STD_LOGIC;
        BRESP : OUT STD_LOGIC_VECTOR (1 downto 0);
        ACLK : IN STD_LOGIC;
        ARESET : IN STD_LOGIC;
        ACLK_EN : IN STD_LOGIC;
        ap_start : OUT STD_LOGIC;
        interrupt : OUT STD_LOGIC;
        ap_ready : IN STD_LOGIC;
        ap_done : IN STD_LOGIC;
        ap_idle : IN STD_LOGIC;
        prn : OUT STD_LOGIC_VECTOR (7 downto 0);
        carrier_step : OUT STD_LOGIC_VECTOR (31 downto 0);
        carrier_phase_init : OUT STD_LOGIC_VECTOR (31 downto 0);
        code_phase_init : OUT STD_LOGIC_VECTOR (31 downto 0);
        code_step : OUT STD_LOGIC_VECTOR (31 downto 0) );
    end component;

    component gps_tracker_status_s_axi is
    generic (
        C_S_AXI_ADDR_WIDTH : INTEGER;
        C_S_AXI_DATA_WIDTH : INTEGER);
    port (
        AWVALID : IN STD_LOGIC;
        AWREADY : OUT STD_LOGIC;
        AWADDR : IN STD_LOGIC_VECTOR (C_S_AXI_ADDR_WIDTH-1 downto 0);
        WVALID : IN STD_LOGIC;
        WREADY : OUT STD_LOGIC;
        WDATA : IN STD_LOGIC_VECTOR (C_S_AXI_DATA_WIDTH-1 downto 0);
        WSTRB : IN STD_LOGIC_VECTOR (C_S_AXI_DATA_WIDTH/8-1 downto 0);
        ARVALID : IN STD_LOGIC;
        ARREADY : OUT STD_LOGIC;
        ARADDR : IN STD_LOGIC_VECTOR (C_S_AXI_ADDR_WIDTH-1 downto 0);
        RVALID : OUT STD_LOGIC;
        RREADY : IN STD_LOGIC;
        RDATA : OUT STD_LOGIC_VECTOR (C_S_AXI_DATA_WIDTH-1 downto 0);
        RRESP : OUT STD_LOGIC_VECTOR (1 downto 0);
        BVALID : OUT STD_LOGIC;
        BREADY : IN STD_LOGIC;
        BRESP : OUT STD_LOGIC_VECTOR (1 downto 0);
        ACLK : IN STD_LOGIC;
        ARESET : IN STD_LOGIC;
        ACLK_EN : IN STD_LOGIC;
        Ie_acc : IN STD_LOGIC_VECTOR (31 downto 0);
        Ie_acc_ap_vld : IN STD_LOGIC;
        Qe_acc : IN STD_LOGIC_VECTOR (31 downto 0);
        Qe_acc_ap_vld : IN STD_LOGIC;
        Ip_acc : IN STD_LOGIC_VECTOR (31 downto 0);
        Ip_acc_ap_vld : IN STD_LOGIC;
        Qp_acc : IN STD_LOGIC_VECTOR (31 downto 0);
        Qp_acc_ap_vld : IN STD_LOGIC;
        Il_acc : IN STD_LOGIC_VECTOR (31 downto 0);
        Il_acc_ap_vld : IN STD_LOGIC;
        Ql_acc : IN STD_LOGIC_VECTOR (31 downto 0);
        Ql_acc_ap_vld : IN STD_LOGIC;
        final_carrier_phase : IN STD_LOGIC_VECTOR (31 downto 0);
        final_carrier_phase_ap_vld : IN STD_LOGIC;
        final_code_phase : IN STD_LOGIC_VECTOR (31 downto 0);
        final_code_phase_ap_vld : IN STD_LOGIC );
    end component;

    component carrier_nco
        port (
            clk, rst_n, en, load : in std_logic;
            step, phase_init : in std_logic_vector(31 downto 0);
            sin_out, cos_out : out std_logic_vector(15 downto 0);
            phase_out : out std_logic_vector(31 downto 0)
        );
    end component;
    
    component code_nco
        port (
            clk, rst_n, en, load : in std_logic;
            prn : in std_logic_vector(4 downto 0);
            step, phase_init : in std_logic_vector(31 downto 0);
            code_e, code_p, code_l : out signed(7 downto 0);
            phase_out : out std_logic_vector(31 downto 0)
        );
    end component;
    
    component correlator
        port (
            clk, rst_n, en, dump : in std_logic;
            I_raw, Q_raw : in signed(7 downto 0);
            sin_val, cos_val : in signed(15 downto 0);
            code_e, code_p, code_l : in signed(7 downto 0);
            Ie_acc, Qe_acc, Ip_acc, Qp_acc, Il_acc, Ql_acc : out signed(31 downto 0)
        );
    end component;

    signal areset_p : std_logic;
begin

    areset_p <= not ap_rst_n;
    
    -- AXI Config Instance
    config_inst : gps_tracker_config_s_axi
    generic map ( C_S_AXI_ADDR_WIDTH => C_S_AXI_CONFIG_ADDR_WIDTH, C_S_AXI_DATA_WIDTH => C_S_AXI_CONFIG_DATA_WIDTH )
    port map (
        AWVALID => s_axi_config_AWVALID, AWREADY => s_axi_config_AWREADY, AWADDR => s_axi_config_AWADDR,
        WVALID => s_axi_config_WVALID, WREADY => s_axi_config_WREADY, WDATA => s_axi_config_WDATA, WSTRB => s_axi_config_WSTRB,
        ARVALID => s_axi_config_ARVALID, ARREADY => s_axi_config_ARREADY, ARADDR => s_axi_config_ARADDR,
        RVALID => s_axi_config_RVALID, RREADY => s_axi_config_RREADY, RDATA => s_axi_config_RDATA,
        RRESP => s_axi_config_RRESP, BVALID => s_axi_config_BVALID, BREADY => s_axi_config_BREADY, BRESP => s_axi_config_BRESP,
        ACLK => ap_clk, ARESET => areset_p, ACLK_EN => '1',
        ap_start => ap_start, interrupt => interrupt,
        ap_ready => ap_ready, ap_done => ap_done, ap_idle => ap_idle,
        prn => prn, carrier_step => carrier_step, carrier_phase_init => carrier_phase_init,
        code_phase_init => code_phase_init, code_step => code_step
    );

    -- AXI Status Instance
    status_inst : gps_tracker_status_s_axi
    generic map ( C_S_AXI_ADDR_WIDTH => C_S_AXI_STATUS_ADDR_WIDTH, C_S_AXI_DATA_WIDTH => C_S_AXI_STATUS_DATA_WIDTH )
    port map (
        AWVALID => s_axi_status_AWVALID, AWREADY => s_axi_status_AWREADY, AWADDR => s_axi_status_AWADDR,
        WVALID => s_axi_status_WVALID, WREADY => s_axi_status_WREADY, WDATA => s_axi_status_WDATA, WSTRB => s_axi_status_WSTRB,
        ARVALID => s_axi_status_ARVALID, ARREADY => s_axi_status_ARREADY, ARADDR => s_axi_status_ARADDR,
        RVALID => s_axi_status_RVALID, RREADY => s_axi_status_RREADY, RDATA => s_axi_status_RDATA,
        RRESP => s_axi_status_RRESP, BVALID => s_axi_status_BVALID, BREADY => s_axi_status_BREADY, BRESP => s_axi_status_BRESP,
        ACLK => ap_clk, ARESET => areset_p, ACLK_EN => '1',
        Ie_acc => Ie_acc, Ie_acc_ap_vld => ap_done,
        Qe_acc => Qe_acc, Qe_acc_ap_vld => ap_done,
        Ip_acc => Ip_acc, Ip_acc_ap_vld => ap_done,
        Qp_acc => Qp_acc, Qp_acc_ap_vld => ap_done,
        Il_acc => Il_acc, Il_acc_ap_vld => ap_done,
        Ql_acc => Ql_acc, Ql_acc_ap_vld => ap_done,
        final_carrier_phase => final_carrier_phase, final_carrier_phase_ap_vld => ap_done,
        final_code_phase => final_code_phase, final_code_phase_ap_vld => ap_done
    );

    Ie_acc <= std_logic_vector(Ie_acc_s); Qe_acc <= std_logic_vector(Qe_acc_s);
    Ip_acc <= std_logic_vector(Ip_acc_s); Qp_acc <= std_logic_vector(Qp_acc_s);
    Il_acc <= std_logic_vector(Il_acc_s); Ql_acc <= std_logic_vector(Ql_acc_s);

    -- Unpack AXI-Stream IQ Data
    -- The PocketSDR data packs I in the lower byte, Q in the upper byte.
    I_raw <= signed(sample_in_TDATA(7 downto 0));
    Q_raw <= signed(sample_in_TDATA(15 downto 8));
    
    -- Cast carrier NCO outputs
    sin_val <= signed(sin_val_slv);
    cos_val <= signed(cos_val_slv);
    
    --------------------------------------------------------------------------------
    -- Main Processing Control State Machine
    -- This orchestrates the pipeline. It waits for 'ap_start' from the AXI config,
    -- then processes exactly 4,000 valid samples, then pulses 'ap_done'.
    --------------------------------------------------------------------------------
    process(ap_clk)
    begin
        if rising_edge(ap_clk) then
            if ap_rst_n = '0' then
                sample_cnt <= (others => '0');
                running <= '0';
                ap_done <= '0';
                load_phases <= '0';
            else
                ap_done <= '0'; -- default pulse: off
                load_phases <= '0';
                
                if running = '0' and ap_start = '1' then
                    -- The Zynq processor just told us to start a new 1ms epoch!
                    running <= '1';
                    load_phases <= '1'; -- Strobe the NCOs to load their starting phases
                    sample_cnt <= (others => '0');
                elsif running = '1' then
                    -- Only advance if the AXI-Stream has valid data for us
                    if sample_in_TVALID = '1' then
                        if sample_cnt = 3999 then
                            -- We reached 4,000 samples! (1ms epoch is complete)
                            sample_cnt <= (others => '0');
                            ap_done <= '1'; -- Tell the AXI status slave to latch the data
                            running <= '0'; -- Stop and wait for the next ap_start
                        else
                            sample_cnt <= sample_cnt + 1;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;
    
    -- We only enable the pipeline stages when we are running AND we have valid incoming data
    process_en <= running and sample_in_TVALID;
    
    -- The epoch dump signal tells the correlator to latch its accumulators to the outputs
    -- GAP 1 FIX: The correlator has a 3-cycle pipeline latency. If we dump at 3999, we
    -- miss the last 3 samples. By asserting dump at 3996, the dump signal propagates
    -- through the pipeline and latches the accumulator right as the 3999th sample arrives.
    epoch_dump <= '1' when sample_cnt = 3996 and sample_in_TVALID = '1' else '0';
    
    -- AXI handshake signals for the auto-generated HLS wrappers
    ap_ready <= '1' when running = '0' else '0';
    ap_idle  <= '1' when running = '0' else '0';
    
    -- Tell the AXI-Stream master we are ready to accept data
    sample_in_TREADY <= '1' when running = '1' else '0';

    --------------------------------------------------------------------------------
    -- Datapath Instances
    -- Here we wire up all of our hand-written DSP blocks!
    --------------------------------------------------------------------------------
    nco_c : carrier_nco port map(
        clk => ap_clk, rst_n => ap_rst_n, en => process_en, load => load_phases,
        step => carrier_step, phase_init => carrier_phase_init,
        sin_out => sin_val_slv, cos_out => cos_val_slv, phase_out => final_carrier_phase
    );
    
    nco_code : code_nco port map(
        clk => ap_clk, rst_n => ap_rst_n, en => process_en, load => load_phases,
        prn => prn(4 downto 0), step => code_step, phase_init => code_phase_init,
        code_e => code_e, code_p => code_p, code_l => code_l, phase_out => final_code_phase
    );
    
    corr : correlator port map(
        clk => ap_clk, rst_n => ap_rst_n, en => process_en, dump => epoch_dump,
        I_raw => I_raw, Q_raw => Q_raw, sin_val => sin_val, cos_val => cos_val,
        code_e => code_e, code_p => code_p, code_l => code_l,
        Ie_acc => Ie_acc_s, Qe_acc => Qe_acc_s, Ip_acc => Ip_acc_s, Qp_acc => Qp_acc_s, Il_acc => Il_acc_s, Ql_acc => Ql_acc_s
    );

end rtl;
 
