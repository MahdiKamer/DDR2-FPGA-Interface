library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
entity ddr2_controller_phy is
  port (
    signal dqs_delay_ctrl_import        : in    std_logic_vector (5 downto 0);
    signal global_reset_n               : in    std_logic;
    signal local_address                : in    std_logic_vector (25 downto 0);
    signal local_autopch_req            : in    std_logic;
    signal local_be                     : in    std_logic_vector (17 downto 0);
    signal local_burstbegin             : in    std_logic;
    signal local_powerdn_req            : in    std_logic;
    signal local_read_req               : in    std_logic;
    signal local_refresh_req            : in    std_logic;
    signal local_self_rfsh_req          : in    std_logic;
    signal local_size                   : in    std_logic_vector(1 downto 0);
    signal local_wdata                  : in    std_logic_vector (143 downto 0);
    signal local_write_req              : in    std_logic;
    signal oct_ctl_rs_value             : in    std_logic_vector (13 downto 0);
    signal oct_ctl_rt_value             : in    std_logic_vector (13 downto 0);
    signal pll_reconfig                 : in    std_logic;
    signal pll_reconfig_counter_param   : in    std_logic_vector (2 downto 0);
    signal pll_reconfig_counter_type    : in    std_logic_vector (3 downto 0);
    signal pll_reconfig_data_in         : in    std_logic_vector (8 downto 0);
    signal pll_reconfig_enable          : in    std_logic;
    signal pll_reconfig_read_param      : in    std_logic;
    signal pll_reconfig_soft_reset_en_n : in    std_logic;
    signal pll_reconfig_write_param     : in    std_logic;
    signal pll_ref_clk                  : in    std_logic;
    signal soft_reset_n                 : in    std_logic;
    signal aux_full_rate_clk            : out   std_logic;
    signal aux_half_rate_clk            : out   std_logic;
    signal dll_reference_clk            : out   std_logic;
    signal dqs_delay_ctrl_export        : out   std_logic_vector (5 downto 0);
    signal local_init_done              : out   std_logic;
    signal local_powerdn_ack            : out   std_logic;
    signal local_rdata                  : out   std_logic_vector (143 downto 0);
    signal local_rdata_valid            : out   std_logic;
    signal local_ready                  : out   std_logic;
    signal local_refresh_ack            : out   std_logic;
    signal local_self_rfsh_ack          : out   std_logic;
    signal local_wdata_req              : out   std_logic;
    signal mem_addr                     : out   std_logic_vector (13 downto 0);
    signal mem_ba                       : out   std_logic_vector (2 downto 0);
    signal mem_cas_n                    : out   std_logic;
    signal mem_cke                      : out   std_logic_vector (0 downto 0);
    signal mem_clk                      : inout std_logic_vector (2 downto 0);
    signal mem_clk_n                    : inout std_logic_vector (2 downto 0);
    signal mem_cs_n                     : out   std_logic_vector (0 downto 0);
    signal mem_dm                       : out   std_logic_vector (8 downto 0);
    signal mem_dq                       : inout std_logic_vector (71 downto 0);
    signal mem_dqs                      : inout std_logic_vector (8 downto 0);
    signal mem_dqsn                     : inout std_logic_vector (8 downto 0);
    signal mem_odt                      : out   std_logic_vector (0 downto 0);
    signal mem_ras_n                    : out   std_logic;
    signal mem_reset_n                  : out   std_logic;
    signal mem_we_n                     : out   std_logic;
    signal phy_clk                      : out   std_logic;
    signal pll_reconfig_busy            : out   std_logic;
    signal pll_reconfig_clk             : out   std_logic;
    signal pll_reconfig_data_out        : out   std_logic_vector (8 downto 0);
    signal pll_reconfig_reset           : out   std_logic;
    signal reset_phy_clk_n              : out   std_logic;
    signal reset_request_n              : out   std_logic
    );
end entity ddr2_controller_phy;
architecture europa of ddr2_controller_phy is
  component Speedy_DDR2_Module is
    port (
      signal clk_mem_interface   : in  std_logic;
      signal rst_n               : in  std_logic;
      signal ctl_read_req        : in  std_logic;
      signal ctl_write_req       : in  std_logic;
      signal ctl_burstbegin      : in  std_logic;
      signal ctl_ready           : out std_logic;
      signal ctl_doing_read      : out std_logic;
      signal ctl_refresh_ack     : out std_logic;
      signal ctl_usr_mode_rdy    : in  std_logic;
      signal ctl_init_done       : out std_logic;
      signal ctl_addr            : in  std_logic_vector (31 downto 0);
      signal ctl_wdata           : in  std_logic_vector (143 downto 0);
      signal ctl_be              : in  std_logic_vector (17 downto 0);
      signal ctl_rdata           : out std_logic_vector (143 downto 0);
      signal ctl_rdata_valid     : out std_logic;
      signal ctl_mem_rdata       : in  std_logic_vector (143 downto 0);
      signal ctl_mem_rdata_valid : in  std_logic;
      signal ctl_mem_wdata       : out std_logic_vector (143 downto 0);
      signal ctl_mem_be          : out std_logic_vector (17 downto 0);
      signal ctl_mem_wdata_valid : out std_logic;
      signal ctl_mem_dqs_burst   : out std_logic;
      signal ctl_mem_ras_n       : out std_logic;
      signal ctl_mem_cas_n       : out std_logic;
      signal ctl_mem_we_n        : out std_logic;
      signal ctl_mem_cs_n        : out std_logic_vector (0 downto 0);
      signal ctl_mem_cke         : out std_logic_vector (0 downto 0);
      signal ctl_mem_odt         : out std_logic_vector (0 downto 0);
      signal ctl_mem_ba          : out std_logic_vector (2 downto 0);
      signal ctl_mem_addr        : out std_logic_vector (13 downto 0)
      );
  end component Speedy_DDR2_Module;
  component ddr2_phy is
    port (
      signal mem_cke                      : out   std_logic_vector (0 downto 0);
      signal ctl_address                  : out   std_logic_vector (25 downto 0);
      signal ctl_autopch_req              : out   std_logic;
      signal mem_dqsn                     : inout std_logic_vector (8 downto 0);
      signal tracking_adjustment_down     : out   std_logic;
      signal local_init_done              : out   std_logic;
      signal mem_ras_n                    : out   std_logic;
      signal tracking_adjustment_up       : out   std_logic;
      signal mem_cs_n                     : out   std_logic_vector (0 downto 0);
      signal mem_reset_n                  : out   std_logic;
      signal ctl_powerdn_req              : out   std_logic;
      signal ctl_size                     : out   std_logic_vector (1 downto 0);
      signal ctl_be                       : out   std_logic_vector (17 downto 0);
      signal ctl_usr_mode_rdy             : out   std_logic;
      signal pll_reconfig_data_out        : out   std_logic_vector (8 downto 0);
      signal ctl_wdata                    : out   std_logic_vector (143 downto 0);
      signal aux_half_rate_clk            : out   std_logic;
      signal local_rdata_valid            : out   std_logic;
      signal mem_we_n                     : out   std_logic;
      signal ctl_mem_rdata_valid          : out   std_logic;
      signal local_ready                  : out   std_logic;
      signal mem_cas_n                    : out   std_logic;
      signal pll_reconfig_reset           : out   std_logic;
      signal dll_reference_clk            : out   std_logic;
      signal local_powerdn_ack            : out   std_logic;
      signal local_wdata_req              : out   std_logic;
      signal local_refresh_ack            : out   std_logic;
      signal ctl_read_req                 : out   std_logic;
      signal reset_request_n              : out   std_logic;
      signal mem_clk_n                    : inout std_logic_vector (2 downto 0);
      signal mem_addr                     : out   std_logic_vector (13 downto 0);
      signal mem_dm                       : out   std_logic_vector (8 downto 0);
      signal pll_reconfig_clk             : out   std_logic;
      signal ctl_write_req                : out   std_logic;
      signal aux_full_rate_clk            : out   std_logic;
      signal mem_dq                       : inout std_logic_vector (71 downto 0);
      signal phy_clk                      : out   std_logic;
      signal tracking_successful          : out   std_logic;
      signal mem_ba                       : out   std_logic_vector (2 downto 0);
      signal pll_reconfig_busy            : out   std_logic;
      signal ctl_burstbegin               : out   std_logic;
      signal postamble_successful         : out   std_logic;
      signal dqs_delay_ctrl_export        : out   std_logic_vector (5 downto 0);
      signal local_rdata                  : out   std_logic_vector (143 downto 0);
      signal ctl_refresh_req              : out   std_logic;
      signal reset_phy_clk_n              : out   std_logic;
      signal mem_odt                      : out   std_logic_vector (0 downto 0);
      signal local_self_rfsh_ack          : out   std_logic;
      signal mem_clk                      : inout std_logic_vector (2 downto 0);
      signal ctl_mem_rdata                : out   std_logic_vector (143 downto 0);
      signal ctl_self_rfsh_req            : out   std_logic;
      signal mem_dqs                      : inout std_logic_vector (8 downto 0);
      signal resynchronisation_successful : out   std_logic;
      signal ctl_doing_rd                 : in    std_logic;
      signal pll_reconfig_data_in         : in    std_logic_vector (8 downto 0);
      signal local_autopch_req            : in    std_logic;
      signal oct_ctl_rt_value             : in    std_logic_vector (13 downto 0);
      signal ctl_mem_wdata_valid          : in    std_logic;
      signal ctl_mem_cke_l                : in    std_logic_vector (0 downto 0);
      signal ctl_add_1t_ac_lat            : in    std_logic;
      signal soft_reset_n                 : in    std_logic;
      signal pll_reconfig_counter_param   : in    std_logic_vector (2 downto 0);
      signal global_reset_n               : in    std_logic;
      signal ctl_mem_cs_n_l               : in    std_logic_vector (0 downto 0);
      signal ctl_mem_cke_h                : in    std_logic_vector (0 downto 0);
      signal ctl_refresh_ack              : in    std_logic;
      signal ctl_mem_wdata                : in    std_logic_vector (143 downto 0);
      signal oct_ctl_rs_value             : in    std_logic_vector (13 downto 0);
      signal pll_reconfig_enable          : in    std_logic;
      signal ctl_rdata_valid              : in    std_logic;
      signal local_self_rfsh_req          : in    std_logic;
      signal ctl_powerdn_ack              : in    std_logic;
      signal ctl_mem_cs_n_h               : in    std_logic_vector (0 downto 0);
      signal pll_reconfig_write_param     : in    std_logic;
      signal ctl_init_done                : in    std_logic;
      signal pll_ref_clk                  : in    std_logic;
      signal ctl_add_1t_odt_lat           : in    std_logic;
      signal ctl_mem_we_n_l               : in    std_logic;
      signal local_read_req               : in    std_logic;
      signal local_be                     : in    std_logic_vector (17 downto 0);
      signal ctl_mem_cas_n_h              : in    std_logic;
      signal ctl_mem_odt_h                : in    std_logic_vector (0 downto 0);
      signal ctl_add_intermediate_regs    : in    std_logic;
      signal local_size                   : in    std_logic_vector (1 downto 0);
      signal ctl_mem_cas_n_l              : in    std_logic;
      signal local_wdata                  : in    std_logic_vector (143 downto 0);
      signal local_refresh_req            : in    std_logic;
      signal ctl_mem_ras_n_l              : in    std_logic;
      signal pll_reconfig_counter_type    : in    std_logic_vector (3 downto 0);
      signal dqs_delay_ctrl_import        : in    std_logic_vector (5 downto 0);
      signal ctl_mem_addr_l               : in    std_logic_vector (13 downto 0);
      signal ctl_negedge_en               : in    std_logic;
      signal ctl_rdata                    : in    std_logic_vector (143 downto 0);
      signal local_burstbegin             : in    std_logic;
      signal pll_reconfig_read_param      : in    std_logic;
      signal local_write_req              : in    std_logic;
      signal ctl_mem_dqs_burst            : in    std_logic;
      signal local_address                : in    std_logic_vector (25 downto 0);
      signal local_powerdn_req            : in    std_logic;
      signal ctl_mem_ras_n_h              : in    std_logic;
      signal ctl_mem_be                   : in    std_logic_vector (17 downto 0);
      signal ctl_ready                    : in    std_logic;
      signal ctl_mem_ba_l                 : in    std_logic_vector (2 downto 0);
      signal ctl_self_rfsh_ack            : in    std_logic;
      signal pll_reconfig                 : in    std_logic;
      signal ctl_mem_odt_l                : in    std_logic_vector (0 downto 0);
      signal ctl_mem_ba_h                 : in    std_logic_vector (2 downto 0);
      signal ctl_wdata_req                : in    std_logic;
      signal ctl_mem_addr_h               : in    std_logic_vector (13 downto 0);
      signal ctl_mem_we_n_h               : in    std_logic
      );
  end component ddr2_phy;
  signal ctl_mem_be                     : std_logic_vector (17 downto 0);
  signal ctl_doing_rd                   : std_logic;
  signal ctl_mem_wdata                  : std_logic_vector (143 downto 0);
  signal ctl_mem_wdata_valid            : std_logic;
  signal ctl_address                    : std_logic_vector (25 downto 0);
  signal ctl_autopch_req_sig            : std_logic;
  signal ctl_powerdn_req_sig            : std_logic;
  signal ctl_self_rfsh_req_sig          : std_logic;
  signal ctl_refresh_req_sig            : std_logic;
  signal ctl_size_sig                   : std_logic_vector (1 downto 0);
  signal no_connect2                    : std_logic;
  signal no_connect4                    : std_logic;
  signal ctl_be                         : std_logic_vector (17 downto 0);
  signal ctl_burstbegin                 : std_logic;
  signal ctl_init_done                  : std_logic;
  signal ctl_mem_a                      : std_logic_vector (13 downto 0);
  signal ctl_mem_ba                     : std_logic_vector (2 downto 0);
  signal ctl_mem_cas_n                  : std_logic;
  signal ctl_mem_cke_h                  : std_logic;
  signal ctl_mem_cs_n                   : std_logic;
  signal ctl_mem_odt                    : std_logic;
  signal ctl_mem_ras_n                  : std_logic;
  signal ctl_mem_rdata                  : std_logic_vector (143 downto 0);
  signal ctl_mem_rdata_valid            : std_logic;
  signal ctl_mem_we_n                   : std_logic;
  signal ctl_rdata                      : std_logic_vector (143 downto 0);
  signal ctl_rdata_valid                : std_logic;
  signal ctl_read_req                   : std_logic;
  signal ctl_ready                      : std_logic;
  signal ctl_refresh_ack                : std_logic;
  signal ctl_usr_mode_rdy_sig           : std_logic;
  signal ctl_wdata                      : std_logic_vector (143 downto 0);
  signal ctl_write_req                  : std_logic;
  signal internal_aux_full_rate_clk     : std_logic;
  signal internal_aux_half_rate_clk     : std_logic;
  signal internal_dll_reference_clk     : std_logic;
  signal internal_dqs_delay_ctrl_export : std_logic_vector (5 downto 0);
  signal internal_local_init_done       : std_logic;
  signal internal_local_powerdn_ack     : std_logic;
  signal internal_local_rdata_valid     : std_logic;
  signal internal_local_ready           : std_logic;
  signal internal_local_refresh_ack     : std_logic;
  signal internal_local_self_rfsh_ack   : std_logic;
  signal internal_local_wdata_req       : std_logic;
  signal internal_mem_addr              : std_logic_vector (13 downto 0);
  signal internal_mem_ba                : std_logic_vector (2 downto 0);
  signal internal_mem_cas_n             : std_logic;
  signal internal_mem_cke               : std_logic_vector (0 downto 0);
  signal internal_mem_cs_n              : std_logic_vector (0 downto 0);
  signal internal_mem_dm                : std_logic_vector (8 downto 0);
  signal internal_mem_odt               : std_logic_vector (0 downto 0);
  signal internal_mem_ras_n             : std_logic;
  signal internal_mem_reset_n           : std_logic;
  signal internal_mem_we_n              : std_logic;
  signal internal_phy_clk               : std_logic;
  signal internal_pll_reconfig_busy     : std_logic;
  signal internal_pll_reconfig_clk      : std_logic;
  signal internal_pll_reconfig_data_out : std_logic_vector (8 downto 0);
  signal internal_pll_reconfig_reset    : std_logic;
  signal internal_reset_phy_clk_n       : std_logic;
  signal internal_reset_request_n       : std_logic;
  signal local_be_sig                   : std_logic_vector (17 downto 0);
  signal local_rdata_sig                : std_logic_vector (143 downto 0);
  signal local_wdata_sig                : std_logic_vector (143 downto 0);
  signal postamble_successful           : std_logic;
  signal resynchronisation_successful   : std_logic;
  signal ctl_mem_dqs_burst              : std_logic;
  signal tie_low                        : std_logic;
  signal tracking_adjustment_down       : std_logic;
  signal tracking_adjustment_up         : std_logic;
  signal tracking_successful            : std_logic;
  signal ctl_addr_sig                   : std_logic_vector (31 downto 0);
begin
  local_wdata_sig(143 downto 0) <= local_wdata(143 downto 0);
  local_be_sig(17 downto 0)     <= local_be(17 downto 0);
  local_rdata                   <= local_rdata_sig(143 downto 0);
  tie_low                       <= '0';
  ctl_addr_sig                  <= ("00" & ctl_address & "0000");
  ddr_sp_ctrl_inst : Speedy_DDR2_Module
    port map (
      clk_mem_interface   => internal_phy_clk,
      rst_n               => internal_reset_phy_clk_n,
      ctl_read_req        => ctl_read_req,
      ctl_write_req       => ctl_write_req,
      ctl_burstbegin      => ctl_burstbegin,
      ctl_ready           => ctl_ready,
      ctl_doing_read      => ctl_doing_rd,
      ctl_refresh_ack     => ctl_refresh_ack,
      ctl_usr_mode_rdy    => ctl_usr_mode_rdy_sig,
      ctl_init_done       => ctl_init_done,
      ctl_addr            => ctl_addr_sig,
      ctl_wdata           => ctl_wdata,
      ctl_be              => ctl_be,
      ctl_rdata           => ctl_rdata,
      ctl_rdata_valid     => ctl_rdata_valid,
      ctl_mem_rdata       => ctl_mem_rdata,
      ctl_mem_rdata_valid => ctl_mem_rdata_valid,
      ctl_mem_wdata       => ctl_mem_wdata,
      ctl_mem_be          => ctl_mem_be,
      ctl_mem_wdata_valid => ctl_mem_wdata_valid,
      ctl_mem_dqs_burst   => ctl_mem_dqs_burst,
      ctl_mem_ras_n       => ctl_mem_ras_n,
      ctl_mem_cas_n       => ctl_mem_cas_n,
      ctl_mem_we_n        => ctl_mem_we_n,
      ctl_mem_cs_n(0)     => ctl_mem_cs_n,
      ctl_mem_cke(0)      => ctl_mem_cke_h,
      ctl_mem_odt(0)      => ctl_mem_odt,
      ctl_mem_ba          => ctl_mem_ba,
      ctl_mem_addr        => ctl_mem_a);
  alt_mem_phy_inst : ddr2_phy
    port map(
      aux_full_rate_clk            => internal_aux_full_rate_clk,
      aux_half_rate_clk            => internal_aux_half_rate_clk,
      ctl_add_1t_ac_lat            => tie_low,
      ctl_add_1t_odt_lat           => tie_low,
      ctl_add_intermediate_regs    => tie_low,
      ctl_address                  => ctl_address,
      ctl_autopch_req              => ctl_autopch_req_sig,
      ctl_be                       => ctl_be,
      ctl_burstbegin               => ctl_burstbegin,
      ctl_doing_rd                 => ctl_doing_rd,
      ctl_init_done                => ctl_init_done,
      ctl_mem_addr_h               => ctl_mem_a,
      ctl_mem_addr_l               => ctl_mem_a,
      ctl_mem_ba_h                 => ctl_mem_ba,
      ctl_mem_ba_l                 => ctl_mem_ba,
      ctl_mem_be                   => ctl_mem_be,
      ctl_mem_cas_n_h              => ctl_mem_cas_n,
      ctl_mem_cas_n_l              => ctl_mem_cas_n,
      ctl_mem_cke_h(0)             => ctl_mem_cke_h,
      ctl_mem_cke_l(0)             => ctl_mem_cke_h,
      ctl_mem_cs_n_h(0)            => ctl_mem_cs_n,
      ctl_mem_cs_n_l(0)            => ctl_mem_cs_n,
      ctl_mem_dqs_burst            => ctl_mem_dqs_burst,
      ctl_mem_odt_h(0)             => ctl_mem_odt,
      ctl_mem_odt_l(0)             => ctl_mem_odt,
      ctl_mem_ras_n_h              => ctl_mem_ras_n,
      ctl_mem_ras_n_l              => ctl_mem_ras_n,
      ctl_mem_rdata                => ctl_mem_rdata,
      ctl_mem_rdata_valid          => ctl_mem_rdata_valid,
      ctl_mem_wdata                => ctl_mem_wdata,
      ctl_mem_wdata_valid          => ctl_mem_wdata_valid,
      ctl_mem_we_n_h               => ctl_mem_we_n,
      ctl_mem_we_n_l               => ctl_mem_we_n,
      ctl_negedge_en               => tie_low,
      ctl_powerdn_ack              => tie_low,
      ctl_powerdn_req              => ctl_powerdn_req_sig,
      ctl_rdata                    => ctl_rdata,
      ctl_rdata_valid              => ctl_rdata_valid,
      ctl_read_req                 => ctl_read_req,
      ctl_ready                    => ctl_ready,
      ctl_refresh_ack              => ctl_refresh_ack,
      ctl_refresh_req              => ctl_refresh_req_sig,
      ctl_self_rfsh_ack            => tie_low,
      ctl_self_rfsh_req            => ctl_self_rfsh_req_sig,
      ctl_size                     => ctl_size_sig,
      ctl_usr_mode_rdy             => ctl_usr_mode_rdy_sig,
      ctl_wdata                    => ctl_wdata,
      ctl_wdata_req                => tie_low,
      ctl_write_req                => ctl_write_req,
      dll_reference_clk            => internal_dll_reference_clk,
      dqs_delay_ctrl_export        => internal_dqs_delay_ctrl_export,
      dqs_delay_ctrl_import        => dqs_delay_ctrl_import,
      global_reset_n               => global_reset_n,
      local_address                => local_address,
      local_autopch_req            => local_autopch_req,
      local_be                     => local_be_sig,
      local_burstbegin             => local_burstbegin,
      local_init_done              => internal_local_init_done,
      local_powerdn_ack            => internal_local_powerdn_ack,
      local_powerdn_req            => local_powerdn_req,
      local_rdata                  => local_rdata_sig,
      local_rdata_valid            => internal_local_rdata_valid,
      local_read_req               => local_read_req,
      local_ready                  => internal_local_ready,
      local_refresh_ack            => internal_local_refresh_ack,
      local_refresh_req            => local_refresh_req,
      local_self_rfsh_ack          => internal_local_self_rfsh_ack,
      local_self_rfsh_req          => local_self_rfsh_req,
      local_size                   => local_size,
      local_wdata                  => local_wdata_sig,
      local_wdata_req              => internal_local_wdata_req,
      local_write_req              => local_write_req,
      mem_addr                     => internal_mem_addr,
      mem_ba                       => internal_mem_ba,
      mem_cas_n                    => internal_mem_cas_n,
      mem_cke(0)                   => internal_mem_cke(0),
      mem_clk                      => mem_clk(2 downto 0),
      mem_clk_n                    => mem_clk_n(2 downto 0),
      mem_cs_n(0)                  => internal_mem_cs_n(0),
      mem_dm                       => internal_mem_dm(8 downto 0),
      mem_dq                       => mem_dq,
      mem_dqs                      => mem_dqs(8 downto 0),
      mem_dqsn                     => mem_dqsn(8 downto 0),
      mem_odt(0)                   => internal_mem_odt(0),
      mem_ras_n                    => internal_mem_ras_n,
      mem_reset_n                  => internal_mem_reset_n,
      mem_we_n                     => internal_mem_we_n,
      oct_ctl_rs_value             => oct_ctl_rs_value,
      oct_ctl_rt_value             => oct_ctl_rt_value,
      phy_clk                      => internal_phy_clk,
      pll_reconfig                 => pll_reconfig,
      pll_reconfig_busy            => internal_pll_reconfig_busy,
      pll_reconfig_clk             => internal_pll_reconfig_clk,
      pll_reconfig_counter_param   => pll_reconfig_counter_param,
      pll_reconfig_counter_type    => pll_reconfig_counter_type,
      pll_reconfig_data_in         => pll_reconfig_data_in,
      pll_reconfig_data_out        => internal_pll_reconfig_data_out,
      pll_reconfig_enable          => pll_reconfig_enable,
      pll_reconfig_read_param      => pll_reconfig_read_param,
      pll_reconfig_reset           => internal_pll_reconfig_reset,
      pll_reconfig_write_param     => pll_reconfig_write_param,
      pll_ref_clk                  => pll_ref_clk,
      postamble_successful         => postamble_successful,
      reset_phy_clk_n              => internal_reset_phy_clk_n,
      reset_request_n              => internal_reset_request_n,
      resynchronisation_successful => resynchronisation_successful,
      soft_reset_n                 => soft_reset_n,
      tracking_adjustment_down     => tracking_adjustment_down,
      tracking_adjustment_up       => tracking_adjustment_up,
      tracking_successful          => tracking_successful
      );
  aux_full_rate_clk     <= internal_aux_full_rate_clk;
  aux_half_rate_clk     <= internal_aux_half_rate_clk;
  dll_reference_clk     <= internal_dll_reference_clk;
  dqs_delay_ctrl_export <= internal_dqs_delay_ctrl_export;
  local_init_done       <= internal_local_init_done;
  local_powerdn_ack     <= internal_local_powerdn_ack;
  local_rdata_valid     <= internal_local_rdata_valid;
  local_ready           <= internal_local_ready;
  local_refresh_ack     <= internal_local_refresh_ack;
  local_self_rfsh_ack   <= internal_local_self_rfsh_ack;
  local_wdata_req       <= internal_local_wdata_req;
  mem_addr              <= internal_mem_addr;
  mem_ba                <= internal_mem_ba;
  mem_cas_n             <= internal_mem_cas_n;
  mem_cke               <= internal_mem_cke;
  mem_cs_n              <= internal_mem_cs_n;
  mem_dm                <= internal_mem_dm;
  mem_odt               <= internal_mem_odt;
  mem_ras_n             <= internal_mem_ras_n;
  mem_reset_n           <= internal_mem_reset_n;
  mem_we_n              <= internal_mem_we_n;
  phy_clk               <= internal_phy_clk;
  pll_reconfig_busy     <= internal_pll_reconfig_busy;
  pll_reconfig_clk      <= internal_pll_reconfig_clk;
  pll_reconfig_data_out <= internal_pll_reconfig_data_out;
  pll_reconfig_reset    <= internal_pll_reconfig_reset;
  reset_phy_clk_n       <= internal_reset_phy_clk_n;
  reset_request_n       <= internal_reset_request_n;
end europa;
