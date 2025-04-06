	`timescale 1ns / 1ps
// These are the commands that can be issued internally down to the bus controller.  The commands that can
//	be issued is dictated by those handled in BusControl_AdvanceInputPipelineStage1ToStage2() and the stage 2
//	state machine below it.
`define DDR2_CMD_READ			0
`define DDR2_CMD_WRITE			1
`define DDR2_CMD_LOAD_MODE		2
`define DDR2_CMD_REFRESH		3
`define DDR2_CMD_PRECHARGE_ALL		4
// This is the top level module that is instantiated by the user.  Most of these parameters can be customized for
//	a particular implementation and the underlying code will adjust.  All times are in terms of picoseconds, unless
//	otherwise noted.
module Speedy_DDR2_Module
  #(
    parameter DDR2_CLK_WIDTH = 3,		// # of clock output pairs,
    parameter DDR2_ROW_WIDTH = 14,		// # of memory row and # of addr bits,
    parameter DDR2_COL_WIDTH = 10,		// # of memory column bits
    parameter DDR2_DQS_WIDTH = 9,		// # of DQS strobes
    parameter DDR2_DQ_WIDTH = 72,		// # of data pins on the external bus
    parameter DDR2_DM_WIDTH = 9,		// # of data mask bits.  Right now the code is written so that this must equal DDR2_DQS_WIDTH
    parameter DDR2_BANK_WIDTH = 3,		// # of memory bank addr bits
    parameter DDR2_CKE_WIDTH = 1,		// # of memory clock enable outputs
    parameter DDR2_CS_WIDTH = 1,		// # of total memory chip selects.  The code only supports one right now.
    parameter DDR2_ODT_WIDTH = 1,		// # of memory on-die term enables
    parameter DQ_PER_DQS = 8,			// # of DQ pins that are associated with each DQS strobe
    parameter TIME_RP = 15000,			// Precharge one bank time (in ps)
    parameter TIME_WR = 15000,			// Write recovery time
    parameter TIME_REFI = 7800000,		// Average periodic refresh interval
    parameter TIME_RFC = 127500,		// REFRESH to ACTIVE or REFRESH to REFRESH command interval
    parameter CLOCKS_CL = 6,			// CAS Latency - The datasheet is strange for this.  For my default part, I can use CL 3, 4, 5, 6
    parameter CLOCKS_AL = 0,			// Additive Latency - The code does not fully support values other than 0.
    parameter BURST_LENGTH_SELECT = 2,	// Burst Length - Set to 2 for length 4 bursts, or 3 for length 8 bursts
    parameter BURST_LENGTH = 4,			// The burst length in normal terms.  Note that the code is only set up to handle burst length 4.
    parameter TIME_RCD = 15000,			// ACTIVE to READ or WRITE delay
    parameter TIME_RC = 57500,			// ACTIVE to ACTIVE delay (same bank)
    parameter TIME_RRD = 7500,			// ACTIVE bank a to ACTIVE bank b delay
    parameter TIME_RTP = 7500,			// Read to Precharge delay
    parameter TIME_WTR = 30000,			// Write To Read Delay for 100 MHz clock period
    parameter TIME_RAS_MIN = 45000,		// Activate to Precharge Delay Minimum
    parameter DDR2_MAX_CS_BITS = 1,
    parameter DDR2_MAX_BANK_BITS = 3,
    parameter DDR2_MAX_ADDR_BITS = 14,
    parameter CLOCKS_RAS_MAX = 7000,		// Activate to Precharge Delay Maximum (Specified in clk_mem_interface clocks, because it overflows in picoseconds)for 100Mhz clock period
    parameter CLK_PERIOD = 10000				// Core/Memory clock period (in ps) - 100 MHz 
    )
   (
    input wire clk_mem_interface,
    input wire rst_n,
    input wire ctl_read_req,
    input wire ctl_write_req,
    input wire ctl_burstbegin,
    output reg ctl_ready,
    output wire ctl_doing_read,
    output wire ctl_refresh_ack,
    input wire ctl_usr_mode_rdy,
    output reg ctl_init_done,
    input wire [31:0] ctl_addr,
    input wire [2*DDR2_DQ_WIDTH-1:0] ctl_wdata,
    input wire [2*DDR2_DM_WIDTH-1:0] ctl_be,
    output reg [2*DDR2_DQ_WIDTH-1:0] ctl_rdata,
    output reg ctl_rdata_valid,
    input wire [2*DDR2_DQ_WIDTH-1:0] ctl_mem_rdata,
    input wire ctl_mem_rdata_valid,
    output wire [2*DDR2_DQ_WIDTH-1:0] ctl_mem_wdata,
    output reg [2*DDR2_DM_WIDTH-1:0] ctl_mem_be,
    output wire ctl_mem_wdata_valid,
    output wire ctl_mem_dqs_burst,
    output wire ctl_mem_ras_n,
    output wire ctl_mem_cas_n,
    output wire ctl_mem_we_n,
    output wire [DDR2_CS_WIDTH-1:0] ctl_mem_cs_n,
    output reg [DDR2_CKE_WIDTH-1:0] ctl_mem_cke,
    output reg [DDR2_ODT_WIDTH-1:0] ctl_mem_odt,
    output wire [DDR2_BANK_WIDTH-1:0] ctl_mem_ba,
    output wire [DDR2_ROW_WIDTH-1:0] ctl_mem_addr
    /*AUTOARG*/);
   // Extended Mode Register values
   //	These constants contain the settings that will be used once the system is initialized.  Some of the
   //	bits are toggled during the initialization phase to get the DLLs working, etc.  The bits that are
   //	toggled are set to 0 here, and flipped in the code below.
   // Fast Exit, Write Recovery Time is computed, Normal Mode, CAS Latency = computed, Sequential burst, Burst Length = computed
   localparam CLOCKS_WR = (TIME_WR + CLK_PERIOD - 1)/CLK_PERIOD;		// Clocks for the write recovery time
   localparam MR_REG_INIT_VALUE = ((CLOCKS_WR-1) * 14'h0200) | (CLOCKS_CL * 14'h0010) | BURST_LENGTH_SELECT;
   // Outputs Enabled, RDQS Disabled, DQS# Enabled, CAS Additive Latency = computed, RTT = 75 Ohms, Full Output Drive Strength, DLL Enabled
   localparam EMR1_REG_INIT_VALUE = {2'b00, 4'b0000, 4'b0000, 4'b0100 } | (CLOCKS_AL * 14'h0008);
   // Set for commercial temperatures
   localparam EMR2_REG_INIT_VALUE = 14'h0000;
   // All bits are reserved
   localparam EMR3_REG_INIT_VALUE = 14'h0000;
   reg 				     bus_ctl_cmd_req;
   wire        bus_ctl_ready;
   reg [2:0]   bus_ctl_cmd;
   reg [31:0]  bus_ctl_addr;
   reg [31:0]  GeneralTimer;
   reg 			      bus_ctl_override;
   reg 			      or_bus_ctl_cmd_req;
   reg 			      or_bus_ctl_ready;
   reg [2:0] 		      or_bus_ctl_cmd;
   reg [31:0] 		      or_bus_ctl_addr;
   reg [2*DDR2_DM_WIDTH-1:0]  or_ctl_mem_be;
   wire 		      permit_wr_cmd;
   wire 		      wr_fifo_full;
   wire 		      delay_cmd;
   wire 		      ctl_cmd_req = ((!ctl_read_req && ctl_write_req && permit_wr_cmd) || (ctl_read_req && !ctl_write_req && !permit_wr_cmd) || (ctl_read_req && !ctl_write_req && permit_wr_cmd)) ? 1'b1 : 1'b0;
   wire 		      ctl_write_n = (!(ctl_read_req || !ctl_write_req || !permit_wr_cmd)) ? 1'b0 : 1'b1;
   wire [2:0] 		      bus_ctl_cmd_sig = (!ctl_write_n) ? `DDR2_CMD_WRITE : `DDR2_CMD_READ;
   wire 		      ctl_ready_cmd = (!(bus_ctl_ready && (ctl_read_req || !ctl_write_req || !wr_fifo_full ))) ? 1'b0 : 1'b1;
   assign permit_wr_cmd = ((ctl_burstbegin && ctl_ready_cmd && !delay_cmd) || (!ctl_burstbegin && delay_cmd && ctl_ready_cmd)) ? 1'b1 : 1'b0;
   sr_ff sr_ff_inst1(
		     .clk    (clk_mem_interface),
		     .rst_n  (rst_n),
		     .s       ((ctl_burstbegin & (~ctl_ready_cmd))),
		     .r       (delay_cmd),
		     .q       (delay_cmd));
   
   reg 			      one_clk_after_wr_cmd;
   always @ (posedge clk_mem_interface) begin
      if(!ctl_read_req && ctl_write_req && permit_wr_cmd)
	one_clk_after_wr_cmd <= 1'b1;
      else 
	one_clk_after_wr_cmd <= 1'b0;
   end
   wire ctl_refresh_ack_sig;
   assign ctl_refresh_ack = ctl_refresh_ack_sig;
   wire ctl_ready_wdata = (!ctl_ready_cmd && one_clk_after_wr_cmd && !wr_fifo_full) ? 1'b1 :1'b0;
   wire ctl_ready_sig = (ctl_ready_cmd | ctl_ready_wdata) & ~ctl_refresh_ack_sig;
   wire [2*DDR2_DQ_WIDTH-1:0] q_wdata;
   wire 		      fifo_rdreq;
   wr_fifo wr_fifo_inst1(
			 .aclr	   (~rst_n),
			 .clock	   (clk_mem_interface),
			 .data	   (ctl_wdata),
			 .rdreq	   (fifo_rdreq),
			 .wrreq	   ((ctl_write_req & ctl_ready_sig)),
			 .full	   (wr_fifo_full),
			 .q	   (q_wdata)
			 );
   assign ctl_mem_wdata = q_wdata;
   always @(*) begin
      if (bus_ctl_override == 1'b1) begin
	 bus_ctl_cmd_req <= or_bus_ctl_cmd_req;
	 or_bus_ctl_ready <= bus_ctl_ready;
	 ctl_ready <= ctl_init_done;
	 bus_ctl_cmd <= or_bus_ctl_cmd;
	 bus_ctl_addr <= or_bus_ctl_addr;
	 ctl_mem_be <= or_ctl_mem_be;
      end
      else begin
	 bus_ctl_cmd_req <= ctl_cmd_req;
	 or_bus_ctl_ready <= 1'b0;
	 ctl_ready <= ctl_ready_sig;
	 bus_ctl_cmd <= bus_ctl_cmd_sig; 
	 bus_ctl_addr <= ctl_addr;
	 ctl_mem_be <= ctl_be;
      end
      ctl_rdata <= ctl_mem_rdata;
      ctl_rdata_valid <= ctl_mem_rdata_valid;
   end
   // Instantiate the bus control module.  This module does the real work, enforcing DDR2 timings, handling row changes, generating
   //	mandatory row closes, refresh cycles and read calibrations.  In normal use, the user is more or less talking to this module
   //	directly.
   DDR2_Bus_Control_Module
     #(
       .DDR2_CLK_WIDTH(DDR2_CLK_WIDTH),
       .DDR2_ROW_WIDTH(DDR2_ROW_WIDTH),
       .DDR2_COL_WIDTH(DDR2_COL_WIDTH),
       .DDR2_DQS_WIDTH(DDR2_DQS_WIDTH),
       .DDR2_DQ_WIDTH(DDR2_DQ_WIDTH),
       .DDR2_DM_WIDTH(DDR2_DM_WIDTH),
       .DDR2_BANK_WIDTH(DDR2_BANK_WIDTH),
       .DDR2_CKE_WIDTH(DDR2_CKE_WIDTH),
       .DDR2_CS_WIDTH(DDR2_CS_WIDTH),
       .DDR2_ODT_WIDTH(DDR2_ODT_WIDTH),
       .DDR2_MAX_CS_BITS(DDR2_MAX_CS_BITS),
       .DDR2_MAX_BANK_BITS(DDR2_MAX_BANK_BITS),
       .DDR2_MAX_ADDR_BITS(DDR2_MAX_ADDR_BITS),
       .DQ_PER_DQS(DQ_PER_DQS),
       .TIME_RP(TIME_RP),
       .TIME_WR(TIME_WR),
       .CLOCKS_WR(CLOCKS_WR),
       .TIME_REFI(TIME_REFI),
       .TIME_RFC(TIME_RFC),
       .CLOCKS_CL(CLOCKS_CL),
       .CLOCKS_AL(CLOCKS_AL),
       .BURST_LENGTH_SELECT(BURST_LENGTH_SELECT),
       .BURST_LENGTH(BURST_LENGTH),
       .TIME_RCD(TIME_RCD),
       .TIME_RC(TIME_RC),
       .TIME_RRD(TIME_RRD),
       .TIME_RTP(TIME_RTP),
       .TIME_WTR(TIME_WTR),
       .TIME_RAS_MIN(TIME_RAS_MIN),
       .CLOCKS_RAS_MAX(CLOCKS_RAS_MAX),
       .CLK_PERIOD(CLK_PERIOD)
       )
   DDR2_Bus_Control
     (
      /*AUTOINST*/
      // Outputs
      .bus_ctl_ready			(bus_ctl_ready),
      .ctl_mem_wdata_valid		(ctl_mem_wdata_valid),
      .ctl_mem_dqs_burst		(ctl_mem_dqs_burst),
      .fifo_rdreq			(fifo_rdreq),
      .ctl_doing_read			(ctl_doing_read),
      .ctl_refresh_ack			(ctl_refresh_ack_sig),
      .ctl_mem_ras_n			(ctl_mem_ras_n),
      .ctl_mem_cas_n			(ctl_mem_cas_n),
      .ctl_mem_we_n			(ctl_mem_we_n),
      .ctl_mem_cs_n			(ctl_mem_cs_n[DDR2_CS_WIDTH-1:0]),
      .ctl_mem_ba			(ctl_mem_ba[DDR2_BANK_WIDTH-1:0]),
      .ctl_mem_addr			(ctl_mem_addr[DDR2_ROW_WIDTH-1:0]),
      // Inputs
      .clk_mem_interface		(clk_mem_interface),
      .rst_n				(rst_n),
      .bus_ctl_cmd_req			(bus_ctl_cmd_req),
      .bus_ctl_cmd			(bus_ctl_cmd[2:0]),
      .bus_ctl_addr			(bus_ctl_addr[31:0]));
   // These are the states for the initialization state machine.  It runs after reset, setting up the DDR2 control registers
   //	and establishing a read calibration lock.  Then it steps out of the way so that the user can communicate with the
   //	bus control state machine directly.
   reg[7:0] ControlState;
   localparam CTRL_STATE_INIT_CKE_BEGIN			= 8'h10;
   localparam CTRL_STATE_INIT_CKE_WAIT			= 8'h11;
   localparam CTRL_STATE_INIT_NOP_WAIT			= 8'h12;
   localparam CTRL_STATE_INIT_PRECHARGE1_WAIT		= 8'h13;
   localparam CTRL_STATE_INIT_EMR2_WAIT			= 8'h14;
   localparam CTRL_STATE_INIT_EMR3_WAIT			= 8'h15;
   localparam CTRL_STATE_INIT_DLL_ENABLE_WAIT		= 8'h16;
   localparam CTRL_STATE_INIT_DLL_RESET_WAIT		= 8'h17;
   localparam CTRL_STATE_INIT_PRECHARGE2_WAIT		= 8'h18;
   localparam CTRL_STATE_INIT_REFRESH1_WAIT		= 8'h19;
   localparam CTRL_STATE_INIT_REFRESH2_WAIT		= 8'h1A;
   localparam CTRL_STATE_INIT_CLEAR_DLL_RESET_WAIT	= 8'h1B;
   localparam CTRL_STATE_INIT_DLL_TIMEOUT		= 8'h1C;
   localparam CTRL_STATE_INIT_SETOCD1_WAIT		= 8'h1D;
   localparam CTRL_STATE_INIT_SETOCD2_WAIT		= 8'h1E;
   localparam CTRL_STATE_INIT_ODT_ENABLE		= 8'h1F;
   localparam CTRL_STATE_INIT_ODT_SETTLE		= 8'h20;
   localparam CTRL_STATE_INIT_DUMMY_WRITE		= 8'h21;
   localparam CTRL_STATE_INIT_COMPLETE			= 8'h22;
   localparam CTRL_STATE_INIT_DONE			= 8'h30;
   localparam CTRL_STATE_CAL_SEQUENCE			= 8'h31;
   localparam CTRL_STATE_RUN_DISPATCH			= 8'h32;
   always @(negedge rst_n or posedge clk_mem_interface) begin
      if (!rst_n) begin
	 ctl_mem_cke <= 0;	// Make all clock enables low for the reset period
	 ctl_mem_odt <= 0;	// Turn off On Die Termination during the initialization sequence.
	 or_bus_ctl_cmd_req <= 1'b0;
	 or_bus_ctl_cmd <= `DDR2_CMD_READ;
	 or_bus_ctl_addr <= 0;
	 or_ctl_mem_be <= ~0;
	 ctl_init_done <= 1'b0;
	 // Turn on the overrides, so that I can control the bus controller from here, rather than the user.
	 bus_ctl_override <= 1'b1;
	 //bus_rd_override <= 1'b1;
	 GeneralTimer <= 0;
	 ControlState <= CTRL_STATE_INIT_CKE_BEGIN;
      end
      else begin
	 or_ctl_mem_be <= ~0;
	 // Decrement the timer as the default action.  Note that this one will wrap, which is used for the refresh interval
	 GeneralTimer <= GeneralTimer - 1;
	 case(ControlState)
	   // Begin the lengthy DDR2 initialization sequence.
	   CTRL_STATE_INIT_CKE_BEGIN: begin
	      // I need to keep all CKE signals low for >= 200us
	      //	At 400MHz, that will take 80,000 clock cycles
	      ctl_mem_cke <= 0;
	      GeneralTimer <= (200000000 + CLK_PERIOD - 1) / CLK_PERIOD;
	      ControlState <= CTRL_STATE_INIT_CKE_WAIT;
	   end
	   CTRL_STATE_INIT_CKE_WAIT: begin
	      // At the end of 200us, put all the CKE's high
	      if (GeneralTimer == 0) begin
		 ctl_mem_cke <= ~0;
		 // Next I will wait for >= 400ns issuing NOPs
		 GeneralTimer <= (400000 + CLK_PERIOD - 1) / CLK_PERIOD;
		 ControlState <= CTRL_STATE_INIT_NOP_WAIT;
	      end
	   end
	   CTRL_STATE_INIT_NOP_WAIT: begin
	      // Wait 400ns with all CKEs at 1
	      if (GeneralTimer == 0) begin
		 // At the end, issue a precharge all command to all chips
		 or_bus_ctl_cmd_req <= 1'b1;
		 or_bus_ctl_cmd <= `DDR2_CMD_PRECHARGE_ALL;
		 ControlState <= CTRL_STATE_INIT_PRECHARGE1_WAIT;
	      end
	   end
	   CTRL_STATE_INIT_PRECHARGE1_WAIT: begin
	      // Wait until the precharge all is done
	      if (or_bus_ctl_ready == 1'b1) begin
		 // At the end, issue load mode to EMR2
		 // I'm going to load all EMR2s of them with the same values.  If I do a real multi-module implemenation,
		 //	that might need to change.
		 or_bus_ctl_cmd_req <= 1'b1;
		 or_bus_ctl_cmd <= `DDR2_CMD_LOAD_MODE;
		 // When doing a LOAD_MODE, the mode register is selected by bits 15:14 of the address, and the
		 //	data is in bits 13:0 of the address.  By not using the data field at all, I removed the need
		 //	to pipeline the data bits since they would have had to have been accessed in the middle of
		 //	the DDR pipeline.  This way I don't have to do that and they can just sit in the block RAM
		 //	FIFO until the very end as this is all that is needed for all normal accesses.  LOAD_MODE is
		 //	a little special and this was a clean way to fix it.
		 or_bus_ctl_addr[DDR2_ROW_WIDTH+:DDR2_BANK_WIDTH] <= 2;
		 or_bus_ctl_addr[DDR2_ROW_WIDTH-1:0] <= EMR2_REG_INIT_VALUE;
		 ControlState <= CTRL_STATE_INIT_EMR2_WAIT;
	      end
	   end
	   CTRL_STATE_INIT_EMR2_WAIT: begin
	      // Wait until the load mode is done
	      if (or_bus_ctl_ready == 1'b1) begin
		 // Load all EMR3s with the same value
		 or_bus_ctl_cmd_req <= 1'b1;
		 or_bus_ctl_cmd <= `DDR2_CMD_LOAD_MODE;
		 or_bus_ctl_addr[DDR2_ROW_WIDTH+:DDR2_BANK_WIDTH] <= 3;
		 or_bus_ctl_addr[DDR2_ROW_WIDTH-1:0] <= EMR3_REG_INIT_VALUE;
		 ControlState <= CTRL_STATE_INIT_EMR3_WAIT;
	      end
	   end
	   CTRL_STATE_INIT_EMR3_WAIT: begin
	      // Wait until the load mode is done
	      if (or_bus_ctl_ready == 1'b1) begin
		 // Enable all the DLLs
		 or_bus_ctl_cmd_req <= 1'b1;
		 or_bus_ctl_cmd <= `DDR2_CMD_LOAD_MODE;
		 or_bus_ctl_addr[DDR2_ROW_WIDTH+:DDR2_BANK_WIDTH] <= 1;
		 or_bus_ctl_addr[DDR2_ROW_WIDTH-1:0] <= EMR1_REG_INIT_VALUE;
		 ControlState <= CTRL_STATE_INIT_DLL_ENABLE_WAIT;
	      end
	   end
	   CTRL_STATE_INIT_DLL_ENABLE_WAIT: begin
	      // Wait until the load mode is done
	      if (or_bus_ctl_ready == 1'b1) begin
		 // Reset all the DLLs
		 or_bus_ctl_cmd_req <= 1'b1;
		 or_bus_ctl_cmd <= `DDR2_CMD_LOAD_MODE;
		 or_bus_ctl_addr[DDR2_ROW_WIDTH+:DDR2_BANK_WIDTH] <= 0;
		 or_bus_ctl_addr[DDR2_ROW_WIDTH-1:0] <= MR_REG_INIT_VALUE | 16'h0100;
		 ControlState <= CTRL_STATE_INIT_DLL_RESET_WAIT;
	      end
	   end
	   CTRL_STATE_INIT_DLL_RESET_WAIT: begin
	      // Wait until the load mode is done
	      if (or_bus_ctl_ready == 1'b1) begin
		 // Issue a precharge all command to all chips
		 or_bus_ctl_cmd_req <= 1'b1;
		 or_bus_ctl_cmd <= `DDR2_CMD_PRECHARGE_ALL;
		 ControlState <= CTRL_STATE_INIT_PRECHARGE2_WAIT;
	      end
	   end
	   CTRL_STATE_INIT_PRECHARGE2_WAIT: begin
	      // Wait until the precharge all is done
	      if (or_bus_ctl_ready == 1'b1) begin
		 // Issue a refresh to all chips
		 or_bus_ctl_cmd_req <= 1'b1;
		 or_bus_ctl_cmd <= `DDR2_CMD_REFRESH;
		 ControlState <= CTRL_STATE_INIT_REFRESH1_WAIT;
	      end
	   end
	   CTRL_STATE_INIT_REFRESH1_WAIT: begin
	      // Wait until the refresh is done
	      if (or_bus_ctl_ready == 1'b1) begin
		 // Issue a second refresh to all chips
		 or_bus_ctl_cmd_req <= 1'b1;
		 or_bus_ctl_cmd <= `DDR2_CMD_REFRESH;
		 ControlState <= CTRL_STATE_INIT_REFRESH2_WAIT;
	      end
	   end
	   CTRL_STATE_INIT_REFRESH2_WAIT: begin
	      // Wait until the refresh is done
	      if (or_bus_ctl_ready == 1'b1) begin
		 // Program MR again to stop the DLL reset, this time A8 = 0
		 or_bus_ctl_cmd_req <= 1'b1;
		 or_bus_ctl_cmd <= `DDR2_CMD_LOAD_MODE;
		 or_bus_ctl_addr[DDR2_ROW_WIDTH+:DDR2_BANK_WIDTH] <= 0;
		 or_bus_ctl_addr[DDR2_ROW_WIDTH-1:0] <= MR_REG_INIT_VALUE;
		 ControlState <= CTRL_STATE_INIT_CLEAR_DLL_RESET_WAIT;
	      end
	   end
	   CTRL_STATE_INIT_CLEAR_DLL_RESET_WAIT: begin
	      // Wait until the load mode that cleared the DLL reset flag is done
	      if (or_bus_ctl_ready == 1'b1) begin
		 or_bus_ctl_cmd_req <= 1'b0;
		 // I'm going to wait 200 clock cycles here, since that is the minimum that needs to pass before
		 //	I can turn off OCD
 		 GeneralTimer <= 200;
		 ControlState <= CTRL_STATE_INIT_DLL_TIMEOUT;
	      end
	   end
	   CTRL_STATE_INIT_DLL_TIMEOUT: begin
	      // Wait 200 clock cycles
	      if (GeneralTimer == 0) begin
		 // I'm not going to use OCD, so first I program EMR1 to put OCD into default mode.
		 or_bus_ctl_cmd_req <= 1'b1;
		 or_bus_ctl_cmd <= `DDR2_CMD_LOAD_MODE;
		 or_bus_ctl_addr[DDR2_ROW_WIDTH+:DDR2_BANK_WIDTH] <= 1;
		 or_bus_ctl_addr[DDR2_ROW_WIDTH-1:0] <= EMR1_REG_INIT_VALUE | 16'h0380;
		 ControlState <= CTRL_STATE_INIT_SETOCD1_WAIT;
	      end
	   end
	   CTRL_STATE_INIT_SETOCD1_WAIT: begin
	      // Wait until the load mode is done
	      if (or_bus_ctl_ready == 1'b1) begin
		 // The turn off OCD by writing EMR1 again
		 or_bus_ctl_cmd_req <= 1'b1;
		 or_bus_ctl_cmd <= `DDR2_CMD_LOAD_MODE;
		 or_bus_ctl_addr[DDR2_ROW_WIDTH+:DDR2_BANK_WIDTH] <= 1;
		 or_bus_ctl_addr[DDR2_ROW_WIDTH-1:0] <= EMR1_REG_INIT_VALUE;
		 ControlState <= CTRL_STATE_INIT_SETOCD2_WAIT;
	      end
	   end
	   CTRL_STATE_INIT_SETOCD2_WAIT: begin
	      // Wait until load mode is done
	      if (or_bus_ctl_ready == 1'b1) begin
		 or_bus_ctl_cmd_req <= 1'b0;
		 // Now I'll wait a few more clock cycles before I enable On Die Termination
 		 GeneralTimer <= 100;
		 ControlState <= CTRL_STATE_INIT_ODT_ENABLE;
	      end
	   end
	   CTRL_STATE_INIT_ODT_ENABLE: begin
	      // Wait for the timeout
	      if (GeneralTimer == 0) begin
		 // On Die Termination can be enabled within a few clock cycles of programming EMR1, so it should be safe now.
		 ctl_mem_odt <= ~0;
		 // Now I'll wait a few more clock cycles after enabling On Die Termination
 		 GeneralTimer <= 100;
		 ControlState <= CTRL_STATE_INIT_ODT_SETTLE;
	      end
	   end
	   CTRL_STATE_INIT_ODT_SETTLE: begin
	      // Wait for the timeout
	      if (GeneralTimer == 0) begin
		 ControlState <= CTRL_STATE_INIT_COMPLETE;//CTRL_STATE_INIT_DUMMY_WRITE;
	      end
	   end
	   CTRL_STATE_INIT_COMPLETE: begin
	      // Wait for the dummy write to complete
	      if (or_bus_ctl_ready == 1'b1) begin
		 or_bus_ctl_cmd_req <= 1'b0;
		 GeneralTimer <= 10000;
		 ControlState <= CTRL_STATE_INIT_DONE;
	      end
	   end
	   CTRL_STATE_INIT_DONE: begin
	      // Wait for the timeout
	      if (GeneralTimer == 0) begin
		 ctl_init_done <= 1'b1;
		 bus_ctl_override <= 1'b0;
		 or_bus_ctl_addr <= 0;
		 ControlState <= CTRL_STATE_CAL_SEQUENCE;
	      end
	   end
	   CTRL_STATE_CAL_SEQUENCE: begin
	      //wait for calibration sequence is completed by the altmemphy
	      if (ctl_usr_mode_rdy == 1'b1) begin
		 or_bus_ctl_addr <= 0;
		 ControlState <= CTRL_STATE_RUN_DISPATCH;
	      end
	   end				
	   CTRL_STATE_RUN_DISPATCH: begin
	   end
	 endcase
      end
   end
endmodule

