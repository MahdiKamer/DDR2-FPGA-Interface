library IEEE;
use IEEE.std_logic_1164.all;
entity ddr2 is
  port (
    local_address     : in    std_logic_vector (25 downto 0);
    local_write_req   : in    std_logic;
    local_read_req    : in    std_logic;
    local_burstbegin  : in    std_logic;
    local_wdata       : in    std_logic_vector (143 downto 0);
    local_be          : in    std_logic_vector (17 downto 0);
    local_size        : in    std_logic_vector (1 downto 0);
    oct_ctl_rs_value  : in    std_logic_vector (13 downto 0);
    oct_ctl_rt_value  : in    std_logic_vector (13 downto 0);
    global_reset_n    : in    std_logic;
    pll_ref_clk       : in    std_logic;
    soft_reset_n      : in    std_logic;
    local_ready       : out   std_logic;
    local_rdata       : out   std_logic_vector (143 downto 0);
    local_rdata_valid : out   std_logic;
    reset_request_n   : out   std_logic;
    mem_odt           : out   std_logic_vector (0 downto 0);
    mem_cs_n          : out   std_logic_vector (0 downto 0);
    mem_cke           : out   std_logic_vector (0 downto 0);
    mem_addr          : out   std_logic_vector (13 downto 0);
    mem_ba            : out   std_logic_vector (2 downto 0);
    mem_ras_n         : out   std_logic;
    mem_cas_n         : out   std_logic;
    mem_we_n          : out   std_logic;
    mem_dm            : out   std_logic_vector (8 downto 0);
    local_refresh_ack : out   std_logic;
    local_wdata_req   : out   std_logic;
    local_init_done   : out   std_logic;
    reset_phy_clk_n   : out   std_logic;
    phy_clk           : out   std_logic;
    aux_full_rate_clk : out   std_logic;
    aux_half_rate_clk : out   std_logic;
    mem_clk           : inout std_logic_vector (2 downto 0);
    mem_clk_n         : inout std_logic_vector (2 downto 0);
    mem_dq            : inout std_logic_vector (71 downto 0);
    mem_dqs           : inout std_logic_vector (8 downto 0);
    mem_dqsn          : inout std_logic_vector (8 downto 0)
    );
end ddr2;
architecture SYN of ddr2 is
  signal signal_wire0  : std_logic;
  signal signal_wire1  : std_logic_vector (5 downto 0);
  signal signal_wire2  : std_logic;
  signal signal_wire3  : std_logic;
  signal signal_wire4  : std_logic;
  signal signal_wire5  : std_logic;
  signal signal_wire6  : std_logic_vector (3 downto 0);
  signal signal_wire7  : std_logic_vector (2 downto 0);
  signal signal_wire8  : std_logic_vector (8 downto 0);
  signal signal_wire9  : std_logic;
  signal signal_wire10 : std_logic;
  signal signal_wire11 : std_logic;
  signal signal_wire12 : std_logic;
  component ddr2_controller_phy
    port (
      local_address                : in    std_logic_vector (25 downto 0);
      local_write_req              : in    std_logic;
      local_read_req               : in    std_logic;
      local_burstbegin             : in    std_logic;
      local_wdata                  : in    std_logic_vector (143 downto 0);
      local_be                     : in    std_logic_vector (17 downto 0);
      local_size                   : in    std_logic_vector (1 downto 0);
      local_refresh_req            : in    std_logic;
      oct_ctl_rs_value             : in    std_logic_vector (13 downto 0);
      oct_ctl_rt_value             : in    std_logic_vector (13 downto 0);
      dqs_delay_ctrl_import        : in    std_logic_vector (5 downto 0);
      pll_reconfig_enable          : in    std_logic;
      pll_reconfig_write_param     : in    std_logic;
      pll_reconfig_read_param      : in    std_logic;
      pll_reconfig                 : in    std_logic;
      pll_reconfig_counter_type    : in    std_logic_vector (3 downto 0);
      pll_reconfig_counter_param   : in    std_logic_vector (2 downto 0);
      pll_reconfig_data_in         : in    std_logic_vector (8 downto 0);
      pll_reconfig_soft_reset_en_n : in    std_logic;
      global_reset_n               : in    std_logic;
      local_autopch_req            : in    std_logic;
      local_powerdn_req            : in    std_logic;
      local_self_rfsh_req          : in    std_logic;
      pll_ref_clk                  : in    std_logic;
      soft_reset_n                 : in    std_logic;
      local_ready                  : out   std_logic;
      local_rdata                  : out   std_logic_vector (143 downto 0);
      local_rdata_valid            : out   std_logic;
      reset_request_n              : out   std_logic;
      mem_odt                      : out   std_logic_vector (0 downto 0);
      mem_cs_n                     : out   std_logic_vector (0 downto 0);
      mem_cke                      : out   std_logic_vector (0 downto 0);
      mem_addr                     : out   std_logic_vector (13 downto 0);
      mem_ba                       : out   std_logic_vector (2 downto 0);
      mem_ras_n                    : out   std_logic;
      mem_cas_n                    : out   std_logic;
      mem_we_n                     : out   std_logic;
      mem_dm                       : out   std_logic_vector (8 downto 0);
      local_refresh_ack            : out   std_logic;
      local_wdata_req              : out   std_logic;
      local_init_done              : out   std_logic;
      reset_phy_clk_n              : out   std_logic;
      mem_reset_n                  : out   std_logic;
      dll_reference_clk            : out   std_logic;
      dqs_delay_ctrl_export        : out   std_logic_vector (5 downto 0);
      pll_reconfig_busy            : out   std_logic;
      pll_reconfig_data_out        : out   std_logic_vector (8 downto 0);
      pll_reconfig_clk             : out   std_logic;
      pll_reconfig_reset           : out   std_logic;
      local_powerdn_ack            : out   std_logic;
      local_self_rfsh_ack          : out   std_logic;
      phy_clk                      : out   std_logic;
      aux_full_rate_clk            : out   std_logic;
      aux_half_rate_clk            : out   std_logic;
      mem_clk                      : inout std_logic_vector (2 downto 0);
      mem_clk_n                    : inout std_logic_vector (2 downto 0);
      mem_dq                       : inout std_logic_vector (71 downto 0);
      mem_dqs                      : inout std_logic_vector (8 downto 0);
      mem_dqsn                     : inout std_logic_vector (8 downto 0)
      );
  end component;
begin
  signal_wire0  <= '0';
  signal_wire1  <= (others => '0');
  signal_wire2  <= '0';
  signal_wire3  <= '0';
  signal_wire4  <= '0';
  signal_wire5  <= '0';
  signal_wire6  <= (others => '0');
  signal_wire7  <= (others => '0');
  signal_wire8  <= (others => '0');
  signal_wire9  <= '0';
  signal_wire10 <= '0';
  signal_wire11 <= '0';
  signal_wire12 <= '0';
  ddr2_controller_phy_inst : ddr2_controller_phy
    port map (
      local_address                => local_address,
      local_write_req              => local_write_req,
      local_read_req               => local_read_req,
      local_burstbegin             => local_burstbegin,
      local_ready                  => local_ready,
      local_rdata                  => local_rdata,
      local_rdata_valid            => local_rdata_valid,
      local_wdata                  => local_wdata,
      local_be                     => local_be,
      local_size                   => local_size,
      reset_request_n              => reset_request_n,
      mem_odt                      => mem_odt,
      mem_clk                      => mem_clk,
      mem_clk_n                    => mem_clk_n,
      mem_cs_n                     => mem_cs_n,
      mem_cke                      => mem_cke,
      mem_addr                     => mem_addr,
      mem_ba                       => mem_ba,
      mem_ras_n                    => mem_ras_n,
      mem_cas_n                    => mem_cas_n,
      mem_we_n                     => mem_we_n,
      mem_dq                       => mem_dq,
      mem_dqs                      => mem_dqs,
      mem_dqsn                     => mem_dqsn,
      mem_dm                       => mem_dm,
      local_refresh_ack            => local_refresh_ack,
      local_refresh_req            => signal_wire0,
      local_wdata_req              => local_wdata_req,
      local_init_done              => local_init_done,
      reset_phy_clk_n              => reset_phy_clk_n,
      mem_reset_n                  => open,
      oct_ctl_rs_value             => oct_ctl_rs_value,
      oct_ctl_rt_value             => oct_ctl_rt_value,
      dqs_delay_ctrl_import        => signal_wire1,
      dll_reference_clk            => open,
      dqs_delay_ctrl_export        => open,
      pll_reconfig_busy            => open,
      pll_reconfig_data_out        => open,
      pll_reconfig_enable          => signal_wire2,
      pll_reconfig_write_param     => signal_wire3,
      pll_reconfig_read_param      => signal_wire4,
      pll_reconfig                 => signal_wire5,
      pll_reconfig_counter_type    => signal_wire6,
      pll_reconfig_counter_param   => signal_wire7,
      pll_reconfig_data_in         => signal_wire8,
      pll_reconfig_clk             => open,
      pll_reconfig_reset           => open,
      pll_reconfig_soft_reset_en_n => signal_wire9,
      global_reset_n               => global_reset_n,
      local_autopch_req            => signal_wire10,
      local_powerdn_req            => signal_wire11,
      local_powerdn_ack            => open,
      local_self_rfsh_req          => signal_wire12,
      local_self_rfsh_ack          => open,
      pll_ref_clk                  => pll_ref_clk,
      phy_clk                      => phy_clk,
      aux_full_rate_clk            => aux_full_rate_clk,
      aux_half_rate_clk            => aux_half_rate_clk,
      soft_reset_n                 => soft_reset_n
      );
end SYN;
