-- ==============================================================
-- Vitis HLS - High-Level Synthesis from C, C++ and OpenCL v2023.2 (64-bit)
-- Tool Version Limit: 2023.10
-- Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
-- Copyright 2022-2023 Advanced Micro Devices, Inc. All Rights Reserved.
-- 
-- ==============================================================
library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity gps_tracker_status_s_axi is
generic (
    C_S_AXI_ADDR_WIDTH    : INTEGER := 8;
    C_S_AXI_DATA_WIDTH    : INTEGER := 32);
port (
    ACLK                  :in   STD_LOGIC;
    ARESET                :in   STD_LOGIC;
    ACLK_EN               :in   STD_LOGIC;
    AWADDR                :in   STD_LOGIC_VECTOR(C_S_AXI_ADDR_WIDTH-1 downto 0);
    AWVALID               :in   STD_LOGIC;
    AWREADY               :out  STD_LOGIC;
    WDATA                 :in   STD_LOGIC_VECTOR(C_S_AXI_DATA_WIDTH-1 downto 0);
    WSTRB                 :in   STD_LOGIC_VECTOR(C_S_AXI_DATA_WIDTH/8-1 downto 0);
    WVALID                :in   STD_LOGIC;
    WREADY                :out  STD_LOGIC;
    BRESP                 :out  STD_LOGIC_VECTOR(1 downto 0);
    BVALID                :out  STD_LOGIC;
    BREADY                :in   STD_LOGIC;
    ARADDR                :in   STD_LOGIC_VECTOR(C_S_AXI_ADDR_WIDTH-1 downto 0);
    ARVALID               :in   STD_LOGIC;
    ARREADY               :out  STD_LOGIC;
    RDATA                 :out  STD_LOGIC_VECTOR(C_S_AXI_DATA_WIDTH-1 downto 0);
    RRESP                 :out  STD_LOGIC_VECTOR(1 downto 0);
    RVALID                :out  STD_LOGIC;
    RREADY                :in   STD_LOGIC;
    Ie_acc                :in   STD_LOGIC_VECTOR(31 downto 0);
    Ie_acc_ap_vld         :in   STD_LOGIC;
    Qe_acc                :in   STD_LOGIC_VECTOR(31 downto 0);
    Qe_acc_ap_vld         :in   STD_LOGIC;
    Ip_acc                :in   STD_LOGIC_VECTOR(31 downto 0);
    Ip_acc_ap_vld         :in   STD_LOGIC;
    Qp_acc                :in   STD_LOGIC_VECTOR(31 downto 0);
    Qp_acc_ap_vld         :in   STD_LOGIC;
    Il_acc                :in   STD_LOGIC_VECTOR(31 downto 0);
    Il_acc_ap_vld         :in   STD_LOGIC;
    Ql_acc                :in   STD_LOGIC_VECTOR(31 downto 0);
    Ql_acc_ap_vld         :in   STD_LOGIC;
    final_carrier_phase   :in   STD_LOGIC_VECTOR(31 downto 0);
    final_carrier_phase_ap_vld :in   STD_LOGIC;
    final_code_phase      :in   STD_LOGIC_VECTOR(31 downto 0);
    final_code_phase_ap_vld :in   STD_LOGIC
);
end entity gps_tracker_status_s_axi;

-- ------------------------Address Info-------------------
-- Protocol Used: ap_ctrl_none
--
-- 0x00 : reserved
-- 0x04 : reserved
-- 0x08 : reserved
-- 0x0c : reserved
-- 0x10 : Data signal of Ie_acc
--        bit 31~0 - Ie_acc[31:0] (Read)
-- 0x14 : Control signal of Ie_acc
--        bit 0  - Ie_acc_ap_vld (Read/COR)
--        others - reserved
-- 0x20 : Data signal of Qe_acc
--        bit 31~0 - Qe_acc[31:0] (Read)
-- 0x24 : Control signal of Qe_acc
--        bit 0  - Qe_acc_ap_vld (Read/COR)
--        others - reserved
-- 0x30 : Data signal of Ip_acc
--        bit 31~0 - Ip_acc[31:0] (Read)
-- 0x34 : Control signal of Ip_acc
--        bit 0  - Ip_acc_ap_vld (Read/COR)
--        others - reserved
-- 0x40 : Data signal of Qp_acc
--        bit 31~0 - Qp_acc[31:0] (Read)
-- 0x44 : Control signal of Qp_acc
--        bit 0  - Qp_acc_ap_vld (Read/COR)
--        others - reserved
-- 0x50 : Data signal of Il_acc
--        bit 31~0 - Il_acc[31:0] (Read)
-- 0x54 : Control signal of Il_acc
--        bit 0  - Il_acc_ap_vld (Read/COR)
--        others - reserved
-- 0x60 : Data signal of Ql_acc
--        bit 31~0 - Ql_acc[31:0] (Read)
-- 0x64 : Control signal of Ql_acc
--        bit 0  - Ql_acc_ap_vld (Read/COR)
--        others - reserved
-- 0x70 : Data signal of final_carrier_phase
--        bit 31~0 - final_carrier_phase[31:0] (Read)
-- 0x74 : Control signal of final_carrier_phase
--        bit 0  - final_carrier_phase_ap_vld (Read/COR)
--        others - reserved
-- 0x80 : Data signal of final_code_phase
--        bit 31~0 - final_code_phase[31:0] (Read)
-- 0x84 : Control signal of final_code_phase
--        bit 0  - final_code_phase_ap_vld (Read/COR)
--        others - reserved
-- (SC = Self Clear, COR = Clear on Read, TOW = Toggle on Write, COH = Clear on Handshake)

architecture behave of gps_tracker_status_s_axi is
    type states is (wridle, wrdata, wrresp, wrreset, rdidle, rddata, rdreset);  -- read and write fsm states
    signal wstate  : states := wrreset;
    signal rstate  : states := rdreset;
    signal wnext, rnext: states;
    constant ADDR_IE_ACC_DATA_0              : INTEGER := 16#10#;
    constant ADDR_IE_ACC_CTRL                : INTEGER := 16#14#;
    constant ADDR_QE_ACC_DATA_0              : INTEGER := 16#20#;
    constant ADDR_QE_ACC_CTRL                : INTEGER := 16#24#;
    constant ADDR_IP_ACC_DATA_0              : INTEGER := 16#30#;
    constant ADDR_IP_ACC_CTRL                : INTEGER := 16#34#;
    constant ADDR_QP_ACC_DATA_0              : INTEGER := 16#40#;
    constant ADDR_QP_ACC_CTRL                : INTEGER := 16#44#;
    constant ADDR_IL_ACC_DATA_0              : INTEGER := 16#50#;
    constant ADDR_IL_ACC_CTRL                : INTEGER := 16#54#;
    constant ADDR_QL_ACC_DATA_0              : INTEGER := 16#60#;
    constant ADDR_QL_ACC_CTRL                : INTEGER := 16#64#;
    constant ADDR_FINAL_CARRIER_PHASE_DATA_0 : INTEGER := 16#70#;
    constant ADDR_FINAL_CARRIER_PHASE_CTRL   : INTEGER := 16#74#;
    constant ADDR_FINAL_CODE_PHASE_DATA_0    : INTEGER := 16#80#;
    constant ADDR_FINAL_CODE_PHASE_CTRL      : INTEGER := 16#84#;
    constant ADDR_BITS         : INTEGER := 8;

    signal waddr               : UNSIGNED(ADDR_BITS-1 downto 0);
    signal wmask               : UNSIGNED(C_S_AXI_DATA_WIDTH-1 downto 0);
    signal aw_hs               : STD_LOGIC;
    signal w_hs                : STD_LOGIC;
    signal rdata_data          : UNSIGNED(C_S_AXI_DATA_WIDTH-1 downto 0);
    signal ar_hs               : STD_LOGIC;
    signal raddr               : UNSIGNED(ADDR_BITS-1 downto 0);
    signal AWREADY_t           : STD_LOGIC;
    signal WREADY_t            : STD_LOGIC;
    signal ARREADY_t           : STD_LOGIC;
    signal RVALID_t            : STD_LOGIC;
    -- internal registers
    signal int_Ie_acc_ap_vld   : STD_LOGIC;
    signal int_Ie_acc          : UNSIGNED(31 downto 0) := (others => '0');
    signal int_Qe_acc_ap_vld   : STD_LOGIC;
    signal int_Qe_acc          : UNSIGNED(31 downto 0) := (others => '0');
    signal int_Ip_acc_ap_vld   : STD_LOGIC;
    signal int_Ip_acc          : UNSIGNED(31 downto 0) := (others => '0');
    signal int_Qp_acc_ap_vld   : STD_LOGIC;
    signal int_Qp_acc          : UNSIGNED(31 downto 0) := (others => '0');
    signal int_Il_acc_ap_vld   : STD_LOGIC;
    signal int_Il_acc          : UNSIGNED(31 downto 0) := (others => '0');
    signal int_Ql_acc_ap_vld   : STD_LOGIC;
    signal int_Ql_acc          : UNSIGNED(31 downto 0) := (others => '0');
    signal int_final_carrier_phase_ap_vld : STD_LOGIC;
    signal int_final_carrier_phase : UNSIGNED(31 downto 0) := (others => '0');
    signal int_final_code_phase_ap_vld : STD_LOGIC;
    signal int_final_code_phase : UNSIGNED(31 downto 0) := (others => '0');


begin
-- ----------------------- Instantiation------------------


-- ----------------------- AXI WRITE ---------------------
    AWREADY_t <=  '1' when wstate = wridle else '0';
    AWREADY   <=  AWREADY_t;
    WREADY_t  <=  '1' when wstate = wrdata else '0';
    WREADY    <=  WREADY_t;
    BRESP     <=  "00";  -- OKAY
    BVALID    <=  '1' when wstate = wrresp else '0';
    wmask     <=  (31 downto 24 => WSTRB(3), 23 downto 16 => WSTRB(2), 15 downto 8 => WSTRB(1), 7 downto 0 => WSTRB(0));
    aw_hs     <=  AWVALID and AWREADY_t;
    w_hs      <=  WVALID and WREADY_t;

    -- write FSM
    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                wstate <= wrreset;
            elsif (ACLK_EN = '1') then
                wstate <= wnext;
            end if;
        end if;
    end process;

    process (wstate, AWVALID, WVALID, BREADY)
    begin
        case (wstate) is
        when wridle =>
            if (AWVALID = '1') then
                wnext <= wrdata;
            else
                wnext <= wridle;
            end if;
        when wrdata =>
            if (WVALID = '1') then
                wnext <= wrresp;
            else
                wnext <= wrdata;
            end if;
        when wrresp =>
            if (BREADY = '1') then
                wnext <= wridle;
            else
                wnext <= wrresp;
            end if;
        when others =>
            wnext <= wridle;
        end case;
    end process;

    waddr_proc : process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ACLK_EN = '1') then
                if (aw_hs = '1') then
                    waddr <= UNSIGNED(AWADDR(ADDR_BITS-1 downto 0));
                end if;
            end if;
        end if;
    end process;

-- ----------------------- AXI READ ----------------------
    ARREADY_t <= '1' when (rstate = rdidle) else '0';
    ARREADY <= ARREADY_t;
    RDATA   <= STD_LOGIC_VECTOR(rdata_data);
    RRESP   <= "00";  -- OKAY
    RVALID_t  <= '1' when (rstate = rddata) else '0';
    RVALID    <= RVALID_t;
    ar_hs   <= ARVALID and ARREADY_t;
    raddr   <= UNSIGNED(ARADDR(ADDR_BITS-1 downto 0));

    -- read FSM
    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                rstate <= rdreset;
            elsif (ACLK_EN = '1') then
                rstate <= rnext;
            end if;
        end if;
    end process;

    process (rstate, ARVALID, RREADY, RVALID_t)
    begin
        case (rstate) is
        when rdidle =>
            if (ARVALID = '1') then
                rnext <= rddata;
            else
                rnext <= rdidle;
            end if;
        when rddata =>
            if (RREADY = '1' and RVALID_t = '1') then
                rnext <= rdidle;
            else
                rnext <= rddata;
            end if;
        when others =>
            rnext <= rdidle;
        end case;
    end process;

    rdata_proc : process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ACLK_EN = '1') then
                if (ar_hs = '1') then
                    rdata_data <= (others => '0');
                    case (TO_INTEGER(raddr)) is
                    when ADDR_IE_ACC_DATA_0 =>
                        rdata_data <= RESIZE(int_Ie_acc(31 downto 0), 32);
                    when ADDR_IE_ACC_CTRL =>
                        rdata_data(0) <= int_Ie_acc_ap_vld;
                    when ADDR_QE_ACC_DATA_0 =>
                        rdata_data <= RESIZE(int_Qe_acc(31 downto 0), 32);
                    when ADDR_QE_ACC_CTRL =>
                        rdata_data(0) <= int_Qe_acc_ap_vld;
                    when ADDR_IP_ACC_DATA_0 =>
                        rdata_data <= RESIZE(int_Ip_acc(31 downto 0), 32);
                    when ADDR_IP_ACC_CTRL =>
                        rdata_data(0) <= int_Ip_acc_ap_vld;
                    when ADDR_QP_ACC_DATA_0 =>
                        rdata_data <= RESIZE(int_Qp_acc(31 downto 0), 32);
                    when ADDR_QP_ACC_CTRL =>
                        rdata_data(0) <= int_Qp_acc_ap_vld;
                    when ADDR_IL_ACC_DATA_0 =>
                        rdata_data <= RESIZE(int_Il_acc(31 downto 0), 32);
                    when ADDR_IL_ACC_CTRL =>
                        rdata_data(0) <= int_Il_acc_ap_vld;
                    when ADDR_QL_ACC_DATA_0 =>
                        rdata_data <= RESIZE(int_Ql_acc(31 downto 0), 32);
                    when ADDR_QL_ACC_CTRL =>
                        rdata_data(0) <= int_Ql_acc_ap_vld;
                    when ADDR_FINAL_CARRIER_PHASE_DATA_0 =>
                        rdata_data <= RESIZE(int_final_carrier_phase(31 downto 0), 32);
                    when ADDR_FINAL_CARRIER_PHASE_CTRL =>
                        rdata_data(0) <= int_final_carrier_phase_ap_vld;
                    when ADDR_FINAL_CODE_PHASE_DATA_0 =>
                        rdata_data <= RESIZE(int_final_code_phase(31 downto 0), 32);
                    when ADDR_FINAL_CODE_PHASE_CTRL =>
                        rdata_data(0) <= int_final_code_phase_ap_vld;
                    when others =>
                        NULL;
                    end case;
                end if;
            end if;
        end if;
    end process;

-- ----------------------- Register logic ----------------

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_Ie_acc <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (Ie_acc_ap_vld = '1') then
                    int_Ie_acc <= UNSIGNED(Ie_acc);
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_Ie_acc_ap_vld <= '0';
            elsif (ACLK_EN = '1') then
                if (Ie_acc_ap_vld = '1') then
                    int_Ie_acc_ap_vld <= '1';
                elsif (ar_hs = '1' and raddr = ADDR_IE_ACC_CTRL) then
                    int_Ie_acc_ap_vld <= '0'; -- clear on read
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_Qe_acc <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (Qe_acc_ap_vld = '1') then
                    int_Qe_acc <= UNSIGNED(Qe_acc);
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_Qe_acc_ap_vld <= '0';
            elsif (ACLK_EN = '1') then
                if (Qe_acc_ap_vld = '1') then
                    int_Qe_acc_ap_vld <= '1';
                elsif (ar_hs = '1' and raddr = ADDR_QE_ACC_CTRL) then
                    int_Qe_acc_ap_vld <= '0'; -- clear on read
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_Ip_acc <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (Ip_acc_ap_vld = '1') then
                    int_Ip_acc <= UNSIGNED(Ip_acc);
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_Ip_acc_ap_vld <= '0';
            elsif (ACLK_EN = '1') then
                if (Ip_acc_ap_vld = '1') then
                    int_Ip_acc_ap_vld <= '1';
                elsif (ar_hs = '1' and raddr = ADDR_IP_ACC_CTRL) then
                    int_Ip_acc_ap_vld <= '0'; -- clear on read
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_Qp_acc <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (Qp_acc_ap_vld = '1') then
                    int_Qp_acc <= UNSIGNED(Qp_acc);
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_Qp_acc_ap_vld <= '0';
            elsif (ACLK_EN = '1') then
                if (Qp_acc_ap_vld = '1') then
                    int_Qp_acc_ap_vld <= '1';
                elsif (ar_hs = '1' and raddr = ADDR_QP_ACC_CTRL) then
                    int_Qp_acc_ap_vld <= '0'; -- clear on read
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_Il_acc <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (Il_acc_ap_vld = '1') then
                    int_Il_acc <= UNSIGNED(Il_acc);
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_Il_acc_ap_vld <= '0';
            elsif (ACLK_EN = '1') then
                if (Il_acc_ap_vld = '1') then
                    int_Il_acc_ap_vld <= '1';
                elsif (ar_hs = '1' and raddr = ADDR_IL_ACC_CTRL) then
                    int_Il_acc_ap_vld <= '0'; -- clear on read
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_Ql_acc <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (Ql_acc_ap_vld = '1') then
                    int_Ql_acc <= UNSIGNED(Ql_acc);
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_Ql_acc_ap_vld <= '0';
            elsif (ACLK_EN = '1') then
                if (Ql_acc_ap_vld = '1') then
                    int_Ql_acc_ap_vld <= '1';
                elsif (ar_hs = '1' and raddr = ADDR_QL_ACC_CTRL) then
                    int_Ql_acc_ap_vld <= '0'; -- clear on read
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_final_carrier_phase <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (final_carrier_phase_ap_vld = '1') then
                    int_final_carrier_phase <= UNSIGNED(final_carrier_phase);
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_final_carrier_phase_ap_vld <= '0';
            elsif (ACLK_EN = '1') then
                if (final_carrier_phase_ap_vld = '1') then
                    int_final_carrier_phase_ap_vld <= '1';
                elsif (ar_hs = '1' and raddr = ADDR_FINAL_CARRIER_PHASE_CTRL) then
                    int_final_carrier_phase_ap_vld <= '0'; -- clear on read
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_final_code_phase <= (others => '0');
            elsif (ACLK_EN = '1') then
                if (final_code_phase_ap_vld = '1') then
                    int_final_code_phase <= UNSIGNED(final_code_phase);
                end if;
            end if;
        end if;
    end process;

    process (ACLK)
    begin
        if (ACLK'event and ACLK = '1') then
            if (ARESET = '1') then
                int_final_code_phase_ap_vld <= '0';
            elsif (ACLK_EN = '1') then
                if (final_code_phase_ap_vld = '1') then
                    int_final_code_phase_ap_vld <= '1';
                elsif (ar_hs = '1' and raddr = ADDR_FINAL_CODE_PHASE_CTRL) then
                    int_final_code_phase_ap_vld <= '0'; -- clear on read
                end if;
            end if;
        end if;
    end process;


-- ----------------------- Memory logic ------------------

end architecture behave;
