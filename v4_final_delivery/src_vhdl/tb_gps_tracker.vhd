library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_gps_tracker is
-- Testbench has no ports
end tb_gps_tracker;

architecture behavior of tb_gps_tracker is

    -- Component Declaration for the Unit Under Test (UUT)
    component gps_tracker
    generic (
        C_S_AXI_CONFIG_ADDR_WIDTH : INTEGER := 6;
        C_S_AXI_CONFIG_DATA_WIDTH : INTEGER := 32;
        C_S_AXI_STATUS_ADDR_WIDTH : INTEGER := 8;
        C_S_AXI_STATUS_DATA_WIDTH : INTEGER := 32
    );
    port (
        ap_clk : IN STD_LOGIC;
        ap_rst_n : IN STD_LOGIC;
        
        -- AXI-Stream Input
        sample_in_TDATA : IN STD_LOGIC_VECTOR (31 downto 0);
        sample_in_TVALID : IN STD_LOGIC;
        sample_in_TREADY : OUT STD_LOGIC;
        
        -- AXI-Lite Config
        s_axi_config_AWVALID : IN STD_LOGIC;
        s_axi_config_AWREADY : OUT STD_LOGIC;
        s_axi_config_AWADDR : IN STD_LOGIC_VECTOR (5 downto 0);
        s_axi_config_WVALID : IN STD_LOGIC;
        s_axi_config_WREADY : OUT STD_LOGIC;
        s_axi_config_WDATA : IN STD_LOGIC_VECTOR (31 downto 0);
        s_axi_config_WSTRB : IN STD_LOGIC_VECTOR (3 downto 0);
        s_axi_config_ARVALID : IN STD_LOGIC;
        s_axi_config_ARREADY : OUT STD_LOGIC;
        s_axi_config_ARADDR : IN STD_LOGIC_VECTOR (5 downto 0);
        s_axi_config_RVALID : OUT STD_LOGIC;
        s_axi_config_RREADY : IN STD_LOGIC;
        s_axi_config_RDATA : OUT STD_LOGIC_VECTOR (31 downto 0);
        s_axi_config_RRESP : OUT STD_LOGIC_VECTOR (1 downto 0);
        s_axi_config_BVALID : OUT STD_LOGIC;
        s_axi_config_BREADY : IN STD_LOGIC;
        s_axi_config_BRESP : OUT STD_LOGIC_VECTOR (1 downto 0);
        interrupt : OUT STD_LOGIC;
        
        -- AXI-Lite Status
        s_axi_status_AWVALID : IN STD_LOGIC;
        s_axi_status_AWREADY : OUT STD_LOGIC;
        s_axi_status_AWADDR : IN STD_LOGIC_VECTOR (7 downto 0);
        s_axi_status_WVALID : IN STD_LOGIC;
        s_axi_status_WREADY : OUT STD_LOGIC;
        s_axi_status_WDATA : IN STD_LOGIC_VECTOR (31 downto 0);
        s_axi_status_WSTRB : IN STD_LOGIC_VECTOR (3 downto 0);
        s_axi_status_ARVALID : IN STD_LOGIC;
        s_axi_status_ARREADY : OUT STD_LOGIC;
        s_axi_status_ARADDR : IN STD_LOGIC_VECTOR (7 downto 0);
        s_axi_status_RVALID : OUT STD_LOGIC;
        s_axi_status_RREADY : IN STD_LOGIC;
        s_axi_status_RDATA : OUT STD_LOGIC_VECTOR (31 downto 0);
        s_axi_status_RRESP : OUT STD_LOGIC_VECTOR (1 downto 0);
        s_axi_status_BVALID : OUT STD_LOGIC;
        s_axi_status_BREADY : IN STD_LOGIC;
        s_axi_status_BRESP : OUT STD_LOGIC_VECTOR (1 downto 0)
    );
    end component;

    -- Inputs
    signal ap_clk : std_logic := '0';
    signal ap_rst_n : std_logic := '0';
    
    signal sample_in_TDATA : std_logic_vector(31 downto 0) := (others => '0');
    signal sample_in_TVALID : std_logic := '0';
    
    signal s_axi_config_AWVALID, s_axi_config_WVALID : std_logic := '0';
    signal s_axi_config_AWADDR : std_logic_vector(5 downto 0) := (others => '0');
    signal s_axi_config_WDATA : std_logic_vector(31 downto 0) := (others => '0');
    signal s_axi_config_WSTRB : std_logic_vector(3 downto 0) := (others => '1');
    signal s_axi_config_ARVALID : std_logic := '0';
    signal s_axi_config_ARADDR : std_logic_vector(5 downto 0) := (others => '0');
    signal s_axi_config_RREADY, s_axi_config_BREADY : std_logic := '0';
    
    signal s_axi_status_AWVALID, s_axi_status_WVALID : std_logic := '0';
    signal s_axi_status_AWADDR : std_logic_vector(7 downto 0) := (others => '0');
    signal s_axi_status_WDATA : std_logic_vector(31 downto 0) := (others => '0');
    signal s_axi_status_WSTRB : std_logic_vector(3 downto 0) := (others => '1');
    signal s_axi_status_ARVALID : std_logic := '0';
    signal s_axi_status_ARADDR : std_logic_vector(7 downto 0) := (others => '0');
    signal s_axi_status_RREADY, s_axi_status_BREADY : std_logic := '0';

    -- Outputs
    signal sample_in_TREADY : std_logic;
    signal s_axi_config_AWREADY, s_axi_config_WREADY, s_axi_config_ARREADY : std_logic;
    signal s_axi_config_RVALID, s_axi_config_BVALID : std_logic;
    signal s_axi_config_RDATA : std_logic_vector(31 downto 0);
    signal s_axi_config_RRESP, s_axi_config_BRESP : std_logic_vector(1 downto 0);
    signal interrupt : std_logic;
    
    signal s_axi_status_AWREADY, s_axi_status_WREADY, s_axi_status_ARREADY : std_logic;
    signal s_axi_status_RVALID, s_axi_status_BVALID : std_logic;
    signal s_axi_status_RDATA : std_logic_vector(31 downto 0);
    signal s_axi_status_RRESP, s_axi_status_BRESP : std_logic_vector(1 downto 0);

    -- Clock period definitions (100 MHz)
    constant clk_period : time := 10 ns;

    -- Procedure for AXI-Lite Write (Config)
    procedure axi_write_config(
        constant addr_in : in std_logic_vector(5 downto 0);
        constant data_in : in std_logic_vector(31 downto 0);
        signal clk : in std_logic;
        signal awaddr : out std_logic_vector(5 downto 0);
        signal awvalid : out std_logic;
        signal awready : in std_logic;
        signal wdata : out std_logic_vector(31 downto 0);
        signal wvalid : out std_logic;
        signal wready : in std_logic;
        signal bready : out std_logic;
        signal bvalid : in std_logic
    ) is
        variable aw_done : boolean := false;
        variable w_done : boolean := false;
    begin
        wait until rising_edge(clk);
        awaddr <= addr_in;
        awvalid <= '1';
        wdata <= data_in;
        wvalid <= '1';
        bready <= '1';
        aw_done := false;
        w_done := false;
        
        loop
            wait until rising_edge(clk);
            if awready = '1' then 
                awvalid <= '0'; 
                aw_done := true;
            end if;
            if wready = '1' then 
                wvalid <= '0'; 
                w_done := true;
            end if;
            exit when (aw_done and w_done);
        end loop;
        
        loop
            wait until rising_edge(clk);
            exit when bvalid = '1';
        end loop;
        
        bready <= '0';
        wait until rising_edge(clk);
    end procedure;

    -- Procedure for AXI-Lite Read (Status)
    procedure axi_read_status(
        constant addr_in : in std_logic_vector(7 downto 0);
        signal data_out : out std_logic_vector(31 downto 0);
        signal clk : in std_logic;
        signal araddr : out std_logic_vector(7 downto 0);
        signal arvalid : out std_logic;
        signal arready : in std_logic;
        signal rdata : in std_logic_vector(31 downto 0);
        signal rvalid : in std_logic;
        signal rready : out std_logic
    ) is
        variable ar_done : boolean := false;
    begin
        wait until rising_edge(clk);
        araddr <= addr_in;
        arvalid <= '1';
        rready <= '1';
        ar_done := false;
        
        loop
            wait until rising_edge(clk);
            if arready = '1' then 
                arvalid <= '0'; 
                ar_done := true;
            end if;
            exit when ar_done;
        end loop;
        
        loop
            wait until rising_edge(clk);
            if rvalid = '1' then
                data_out <= rdata;
                exit;
            end if;
        end loop;
        
        rready <= '0';
        wait until rising_edge(clk);
    end procedure;

    signal read_val : std_logic_vector(31 downto 0);

begin

    -- Instantiate the Unit Under Test (UUT)
    uut: gps_tracker port map (
        ap_clk => ap_clk,
        ap_rst_n => ap_rst_n,
        sample_in_TDATA => sample_in_TDATA,
        sample_in_TVALID => sample_in_TVALID,
        sample_in_TREADY => sample_in_TREADY,
        
        s_axi_config_AWVALID => s_axi_config_AWVALID,
        s_axi_config_AWREADY => s_axi_config_AWREADY,
        s_axi_config_AWADDR => s_axi_config_AWADDR,
        s_axi_config_WVALID => s_axi_config_WVALID,
        s_axi_config_WREADY => s_axi_config_WREADY,
        s_axi_config_WDATA => s_axi_config_WDATA,
        s_axi_config_WSTRB => s_axi_config_WSTRB,
        s_axi_config_ARVALID => s_axi_config_ARVALID,
        s_axi_config_ARREADY => s_axi_config_ARREADY,
        s_axi_config_ARADDR => s_axi_config_ARADDR,
        s_axi_config_RVALID => s_axi_config_RVALID,
        s_axi_config_RREADY => s_axi_config_RREADY,
        s_axi_config_RDATA => s_axi_config_RDATA,
        s_axi_config_RRESP => s_axi_config_RRESP,
        s_axi_config_BVALID => s_axi_config_BVALID,
        s_axi_config_BREADY => s_axi_config_BREADY,
        s_axi_config_BRESP => s_axi_config_BRESP,
        interrupt => interrupt,
        
        s_axi_status_AWVALID => s_axi_status_AWVALID,
        s_axi_status_AWREADY => s_axi_status_AWREADY,
        s_axi_status_AWADDR => s_axi_status_AWADDR,
        s_axi_status_WVALID => s_axi_status_WVALID,
        s_axi_status_WREADY => s_axi_status_WREADY,
        s_axi_status_WDATA => s_axi_status_WDATA,
        s_axi_status_WSTRB => s_axi_status_WSTRB,
        s_axi_status_ARVALID => s_axi_status_ARVALID,
        s_axi_status_ARREADY => s_axi_status_ARREADY,
        s_axi_status_ARADDR => s_axi_status_ARADDR,
        s_axi_status_RVALID => s_axi_status_RVALID,
        s_axi_status_RREADY => s_axi_status_RREADY,
        s_axi_status_RDATA => s_axi_status_RDATA,
        s_axi_status_RRESP => s_axi_status_RRESP,
        s_axi_status_BVALID => s_axi_status_BVALID,
        s_axi_status_BREADY => s_axi_status_BREADY,
        s_axi_status_BRESP => s_axi_status_BRESP
    );

    -- Clock process
    ap_clk_process :process
    begin
        ap_clk <= '0';
        wait for clk_period/2;
        ap_clk <= '1';
        wait for clk_period/2;
    end process;
    
    -- Stimulus process
    stim_proc: process
    begin
        -- Hold reset state for 100 ns.
        ap_rst_n <= '0';
        wait for 100 ns;
        ap_rst_n <= '1';
        wait for clk_period*10;

        report "--- Configuring GPS Tracker via AXI-Lite ---";
        -- Config PRN (0x10) = 31 (PRN 31)
        axi_write_config(std_logic_vector(to_unsigned(16#10#, 6)), std_logic_vector(to_unsigned(31, 32)), 
                         ap_clk, s_axi_config_AWADDR, s_axi_config_AWVALID, s_axi_config_AWREADY, 
                         s_axi_config_WDATA, s_axi_config_WVALID, s_axi_config_WREADY, s_axi_config_BREADY, s_axi_config_BVALID);
        
        -- Config Carrier Step (0x18) = Doppler (arbitrary test value)
        axi_write_config(std_logic_vector(to_unsigned(16#18#, 6)), std_logic_vector(to_unsigned(1000000, 32)), 
                         ap_clk, s_axi_config_AWADDR, s_axi_config_AWVALID, s_axi_config_AWREADY, 
                         s_axi_config_WDATA, s_axi_config_WVALID, s_axi_config_WREADY, s_axi_config_BREADY, s_axi_config_BVALID);
        
        -- Config Carrier Phase Init (0x20) = 0
        axi_write_config(std_logic_vector(to_unsigned(16#20#, 6)), std_logic_vector(to_unsigned(0, 32)), 
                         ap_clk, s_axi_config_AWADDR, s_axi_config_AWVALID, s_axi_config_AWREADY, 
                         s_axi_config_WDATA, s_axi_config_WVALID, s_axi_config_WREADY, s_axi_config_BREADY, s_axi_config_BVALID);

        -- Config Code Phase Init (0x28) = 0
        axi_write_config(std_logic_vector(to_unsigned(16#28#, 6)), std_logic_vector(to_unsigned(0, 32)), 
                         ap_clk, s_axi_config_AWADDR, s_axi_config_AWVALID, s_axi_config_AWREADY, 
                         s_axi_config_WDATA, s_axi_config_WVALID, s_axi_config_WREADY, s_axi_config_BREADY, s_axi_config_BVALID);
                         
        -- Config Code Step (0x30) = Code rate step
        axi_write_config(std_logic_vector(to_unsigned(16#30#, 6)), std_logic_vector(to_unsigned(16760, 32)), -- approx 1.023M / 4M * 65536
                         ap_clk, s_axi_config_AWADDR, s_axi_config_AWVALID, s_axi_config_AWREADY, 
                         s_axi_config_WDATA, s_axi_config_WVALID, s_axi_config_WREADY, s_axi_config_BREADY, s_axi_config_BVALID);

        report "--- Sending ap_start ---";
        -- Write ap_start (0x00) = 1
        axi_write_config(std_logic_vector(to_unsigned(16#00#, 6)), std_logic_vector(to_unsigned(1, 32)), 
                         ap_clk, s_axi_config_AWADDR, s_axi_config_AWVALID, s_axi_config_AWREADY, 
                         s_axi_config_WDATA, s_axi_config_WVALID, s_axi_config_WREADY, s_axi_config_BREADY, s_axi_config_BVALID);

        wait for clk_period*5;
        
        report "--- Streaming 4000 I/Q Samples ---";
        -- Stream 4000 samples (1ms epoch)
        for i in 0 to 3999 loop
            wait until rising_edge(ap_clk);
            -- Pack dummy I=1, Q=-1 (0xFF01)
            sample_in_TDATA <= x"0000FF01"; 
            sample_in_TVALID <= '1';
            
            loop
                if sample_in_TREADY = '1' then
                    exit;
                end if;
                wait until rising_edge(ap_clk);
            end loop;
        end loop;
        
        wait until rising_edge(ap_clk);
        sample_in_TVALID <= '0';
        
        report "--- Waiting for Pipeline to flush and ap_done to trigger ---";
        -- The correlator has 3 clock cycles of latency. Let's wait.
        wait for clk_period*10;
        
        report "--- Reading Status Registers ---";
        
        -- Read Ip_acc (0x30 in status mmio)
        axi_read_status(std_logic_vector(to_unsigned(16#30#, 8)), read_val, 
                        ap_clk, s_axi_status_ARADDR, s_axi_status_ARVALID, s_axi_status_ARREADY, 
                        s_axi_status_RDATA, s_axi_status_RVALID, s_axi_status_RREADY);
        report "Ip_acc = " & integer'image(to_integer(signed(read_val)));

        -- Read Qp_acc (0x40 in status mmio)
        axi_read_status(std_logic_vector(to_unsigned(16#40#, 8)), read_val, 
                        ap_clk, s_axi_status_ARADDR, s_axi_status_ARVALID, s_axi_status_ARREADY, 
                        s_axi_status_RDATA, s_axi_status_RVALID, s_axi_status_RREADY);
        report "Qp_acc = " & integer'image(to_integer(signed(read_val)));
        
        report "--- Simulation Complete ---";
        std.env.stop;
        
    end process;

end behavior;
