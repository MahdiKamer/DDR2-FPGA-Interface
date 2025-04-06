`timescale 1ns / 1ps
// These are the commands that can be issued internally down to the bus controller.  The commands that can
//be issued is dicated by those handled in BusControl_AdvanceInputPipelineStage1ToStage2() and the stage 2
//	state machine below it.
`define DDR2_CMD_READ				0
`define DDR2_CMD_WRITE				1
`define DDR2_CMD_LOAD_MODE			2
`define DDR2_CMD_REFRESH			3
`define DDR2_CMD_PRECHARGE_ALL		4
// This is the main bus control module, which enforces DDR2 timings, generates refresh cycles, generates forced //reads to maintain calibration, handles row changes and mandatory row timeout closing.
module DDR2_Bus_Control_Module
  #(
    parameter DDR2_CLK_WIDTH = 0,		// # of clock output pairs,
    parameter DDR2_ROW_WIDTH = 0,		// # of memory row and # of addr bits,
    parameter DDR2_COL_WIDTH = 0,		// # of memory column bits
    parameter DDR2_DQS_WIDTH = 0,		// # of DQS strobes,
    parameter DDR2_DQ_WIDTH = 0,		// # of data width,
    parameter DDR2_DM_WIDTH = 0,		// # of data mask bits.  Right now the code is written so that this must equal DDR2_DQS_WIDTH
    parameter DDR2_BANK_WIDTH = 0,		// # of memory bank addr bits
    parameter DDR2_CKE_WIDTH = 0,		// # of memory clock enable outputs
    parameter DDR2_CS_WIDTH = 0,		// # of total memory chip selects
    parameter DDR2_ODT_WIDTH = 0,		// # of memory on-die term enables
    parameter DDR2_MAX_CS_BITS = 0,
    parameter DDR2_MAX_BANK_BITS = 0,
    parameter DDR2_MAX_ADDR_BITS = 0,
    parameter DQ_PER_DQS = 0,			// # of DQ pins that are associated with each DQS strobe
    parameter TIME_RP = 0,				// Precharge one bank time (in ps)
    parameter TIME_WR = 0,				// Write recovery time
    parameter CLOCKS_WR = 0,			// Clocks for the write recovery time
    parameter TIME_REFI = 0,			// Average periodic refresh interval
    parameter TIME_RFC = 0,		// REFRESH to ACTIVE or REFRESH to REFRESH command interval
    parameter CLOCKS_CL = 0,			// CAS Latency 
    parameter CLOCKS_AL = 0,			// Additive Latency
    parameter BURST_LENGTH_SELECT = 0,// Burst Length - Set to 2 for length 4 bursts, or 3 for length 8 bursts
    parameter BURST_LENGTH = 0,// The burst length in normal terms.  Note that the code is only set up to handle burst length 4.
    parameter TIME_RCD = 0,				// ACTIVE to READ or WRITE delay
    parameter TIME_RC = 0,				// ACTIVE to ACTIVE delay (same bank)
    parameter TIME_RRD = 0,				// ACTIVE bank a to ACTIVE bank b delay
    parameter TIME_RTP = 0,				// Read to Precharge delay
    parameter TIME_WTR = 0,				// Write To Read Delay
    parameter TIME_RAS_MIN = 0,			// Activate to Precharge Delay Minimum
    parameter CLOCKS_RAS_MAX = 0,// Activate to Precharge Delay Maximum (Specified in clk_mem_interface, because it overflows in picoseconds)
    parameter CLK_PERIOD = 0			// Core/Memory clock period (in ps)
    )
   (
    input wire clk_mem_interface,
    input wire rst_n,
    input wire bus_ctl_cmd_req,
    output reg bus_ctl_ready,
    input wire [2:0] bus_ctl_cmd,
    input wire [31:0] bus_ctl_addr,
    output reg ctl_mem_wdata_valid,
    output reg ctl_mem_dqs_burst,
    output reg fifo_rdreq, 
    output ctl_doing_read,
    output reg ctl_refresh_ack,
    output reg ctl_mem_ras_n,
    output reg ctl_mem_cas_n,
    output reg ctl_mem_we_n,
    output reg [DDR2_CS_WIDTH-1:0] ctl_mem_cs_n,
    output reg [DDR2_BANK_WIDTH-1:0] ctl_mem_ba,
    output reg [DDR2_ROW_WIDTH-1:0] ctl_mem_addr
    );
// Here I calculate many of the times that were given in terms of picoseconds in terms of clock cycles, rounded //up to the next whole clock cycle.
   localparam CLOCKS_RP = (TIME_RP + CLK_PERIOD - 1)/CLK_PERIOD;	//Clocks for a precharge single bank command
   localparam CLOCKS_RPA = CLOCKS_RP + 1;								// Clocks for a precharge all command
   localparam CLOCK_REFI = (TIME_REFI + CLK_PERIOD - 1)/CLK_PERIOD;//Clocks for the average periodic refresh interval
   localparam CLOCKS_RFC = (TIME_RFC + CLK_PERIOD - 1)/CLK_PERIOD;// REFRESH to ACTIVE or REFRESH to REFRESH //command interval
   localparam CLOCKS_RL = CLOCKS_AL + CLOCKS_CL;// The read latency, the number of clocks from when a read //command is issued until the data appears is defined to be the Additive Latency plus the CAS Latency.
   localparam CLOCKS_WL = CLOCKS_RL - 1;							// The write latency, defined to be read latency minus 1
   localparam CLOCKS_CCD = BURST_LENGTH/2-1;					
// CAS to CAS Latency - The time that must be waited between
//successive read/write requests, which is the burst length divided by 2.
   localparam CLOCKS_RCD = (TIME_RCD + CLK_PERIOD - 1)/CLK_PERIOD;	// ACTIVE to READ or WRITE delay
   localparam CLOCKS_RC = (TIME_RC + CLK_PERIOD - 1)/CLK_PERIOD;	// ACTIVE to ACTIVE delay (same bank)
   localparam CLOCKS_RRD = (TIME_RRD + CLK_PERIOD - 1)/CLK_PERIOD;// ACTIVE bank a to ACTIVE bank b delay
   localparam DDR2_NUM_BANKS = 2**DDR2_BANK_WIDTH;
   localparam CLOCKS_MRD = 2;											// Clocks for a load mode command
   localparam CLOCKS_RTP = (TIME_RTP + CLK_PERIOD - 1)/CLK_PERIOD;	// Read to Precharge delay
   localparam CLOCKS_WTR = (TIME_WTR + CLK_PERIOD - 1)/CLK_PERIOD;	// Write To Read Delay
   localparam CLOCKS_RAS_MIN = (TIME_RAS_MIN + CLK_PERIOD - 1)/CLK_PERIOD;//Activate to Precharge Delay Minimum
// This is the required average number of clocks between refresh commands.  There can be some slop on a per //command basis, but this needs to be the average.
   localparam CLOCKS_REFI = (TIME_REFI + CLK_PERIOD - 1)/CLK_PERIOD;
// This keeps track of which rows are currently active (open) with the flag, and if active, what row they are on.
   reg [DDR2_NUM_BANKS-1:0] 	    CurrentBankActive_H;
   reg [DDR2_ROW_WIDTH-1:0] 	    CurrentBankRow[0:DDR2_NUM_BANKS-1];
// This is used as a FIFO to indicate to the bus drivers when write data is present in the output flip flops, //and hence when the tri-state driver should be set to drive data out.
   localparam WRITE_ENABLE_QUEUE_LEN = CLOCKS_WL+4;
   reg [WRITE_ENABLE_QUEUE_LEN-1:0] WriteCycleStarting_H;
   // The queue length for the DQS active signal is 4 longer than read latency because:
   //	- One clock cycle of delay for the Moore state machine control signal assignment
   //	- One cycle of delay because of the control signal staging registers
   //	- One cycle for the ODDR going out
   //	- Plus the queue is one longer than it needs to be because I need to put an extra pulse
   //		 into the queue for the second DQS pulse of the burst.
   // On the way back, I have
   //	- Two cycles for the IDDR coming back
   //	- One cycle for the propagation delay staging registers between the IDDR and the logic
   localparam READ_DQS_ACTIVE_QUEUE_LEN = CLOCKS_RL+4;
   reg 				    ReadDQSActiveQueue[0:READ_DQS_ACTIVE_QUEUE_LEN-1];
   
   // Do the same for the write DQS active queue
   localparam WRITE_DQS_ACTIVE_QUEUE_LEN = CLOCKS_WL+3;
   reg 				    WriteDQSActiveQueue[0:WRITE_DQS_ACTIVE_QUEUE_LEN-1];
   
//These registers buffer the command data as it comes in.  They introduce an extra cycle of latency, but I //needed them to allow me to run at high speeds.  It works without them at 140MHz, but not at 200MHz.
// They do not affect the resulting bandwidth, however, because you can only issue a read or write command to //the DDR every other clock cycle anyway.
   localparam INPUT_PIPELINE_LEN = 2;
   
   reg 				    InputPipeline_Valid_H[1:INPUT_PIPELINE_LEN];
   reg [2:0] 			    InputPipeline_Cmd[1:INPUT_PIPELINE_LEN];
   reg [31:0] 			    InputPipeline_CmdAddress[1:INPUT_PIPELINE_LEN];
   
   wire [DDR2_CS_WIDTH-1:0] 	    InputPipeline_ChipSelectBits[1:INPUT_PIPELINE_LEN];
   wire [DDR2_BANK_WIDTH-1:0] 	    InputPipeline_BankSelectBits[1:INPUT_PIPELINE_LEN];
   wire [DDR2_ROW_WIDTH-1:0] 	    InputPipeline_RowSelectBits[1:INPUT_PIPELINE_LEN];
   wire [DDR2_COL_WIDTH-1:0] 	    InputPipeline_ColSelectBits[1:INPUT_PIPELINE_LEN];
   
   integer 			    i;
   
   // The address format will be CHIP_SELECT:BANK_SELECT:ROW_SELECT:COLUMN_SELECT:2:0.
   //	That way I will be decoding multiple chip selects and banks within those using one big address.
   //	The address is 64-bit (8-byte) word based, because that is the size of a single transfer,
   //	which is why I skip over the lower 3 bits here.
   // Note that you should only send down addresses that fall on burst length sized boundaries anyway,
   //	or you will get wrap around effects in the data.  In other words, you will get all the data
   //	for a burst, no matter where you start within that burst sized block.  The RAM will just feed
   //	you the data starting from the address you give it and keep feeding it to you until one full
   //	burst has been sent back, which could mean wrapping around to a lower address.  It's easier just
   //	to send down an address that is aligned to a burst sized boundary.
   // The address is linear, in that it does not skip over A10 from the user's perspective.  That is
   //	done within this module automatically.
   assign InputPipeline_ChipSelectBits[1] = InputPipeline_CmdAddress[1][(DDR2_BANK_WIDTH+DDR2_ROW_WIDTH+DDR2_COL_WIDTH+3)+:DDR2_CS_WIDTH];
   assign InputPipeline_ChipSelectBits[INPUT_PIPELINE_LEN] = InputPipeline_CmdAddress[INPUT_PIPELINE_LEN][(DDR2_BANK_WIDTH+DDR2_ROW_WIDTH+DDR2_COL_WIDTH+3)+:DDR2_CS_WIDTH];
   assign InputPipeline_BankSelectBits[1] = InputPipeline_CmdAddress[1][(DDR2_ROW_WIDTH+DDR2_COL_WIDTH+3)+:DDR2_BANK_WIDTH];
   assign InputPipeline_BankSelectBits[INPUT_PIPELINE_LEN] = InputPipeline_CmdAddress[INPUT_PIPELINE_LEN][(DDR2_ROW_WIDTH+DDR2_COL_WIDTH+3)+:DDR2_BANK_WIDTH];
   assign InputPipeline_RowSelectBits[1] = InputPipeline_CmdAddress[1][(DDR2_COL_WIDTH+3)+:DDR2_ROW_WIDTH];
   assign InputPipeline_RowSelectBits[INPUT_PIPELINE_LEN] = InputPipeline_CmdAddress[INPUT_PIPELINE_LEN][(DDR2_COL_WIDTH+3)+:DDR2_ROW_WIDTH];
   assign InputPipeline_ColSelectBits[1] = InputPipeline_CmdAddress[1][3+:DDR2_COL_WIDTH];
   assign InputPipeline_ColSelectBits[INPUT_PIPELINE_LEN] = InputPipeline_CmdAddress[INPUT_PIPELINE_LEN][3+:DDR2_COL_WIDTH];
   
   // All 1's for the chip select index is used to make sure that no chip is selected, so if there are 4 real
   //chip selects, this field needs to be 3 bits wide.  If the most significant bit is a 0 and the rest are 1's
   //	then all chip selects are asserted.
   wire [DDR2_MAX_CS_BITS:0] 	    SelectAllChipSelects;
   wire [DDR2_MAX_CS_BITS:0] 	    SelectNoChipSelects;
   assign SelectAllChipSelects[DDR2_MAX_CS_BITS] = 1'b1;
   assign SelectAllChipSelects[DDR2_MAX_CS_BITS-1:0] = 0;
   assign SelectNoChipSelects = ~0;
   // This will decode the chip select index into the individual chip selects
   function [DDR2_CS_WIDTH-1:0] DecodeChipSelects;
      input [DDR2_MAX_CS_BITS:0]    Index;
      begin
	 for( i = 0; i < DDR2_CS_WIDTH; i = i + 1 ) begin
	    if (Index == i)
	      DecodeChipSelects[i] = 1'b0;
	    else
	      DecodeChipSelects[i] = 1'b1;
	 end
	 if (Index == SelectAllChipSelects)
	   DecodeChipSelects = 0;
	 else if (Index == SelectNoChipSelects)
	   DecodeChipSelects = ~0;
      end
   endfunction
   
   // These tasks are short hand for sending commands to the DDR2.  By wrapping the control signals up into a task,
   //	it is less likely that the signals will be mis-set.
   task DDR2CMD_Idle;
      begin
	 ctl_mem_cs_n <= DecodeChipSelects( SelectNoChipSelects );
	 ctl_mem_ras_n <= 1'b1;
	 ctl_mem_cas_n <= 1'b1;
	 ctl_mem_we_n <= 1'b1;
	 ctl_mem_ba <= 0;
	 ctl_mem_addr <= 0;
      end
   endtask
   
   task DDR2CMD_LoadMode;
      input [DDR2_MAX_CS_BITS-1:0] ChipSelect;
      input [DDR2_BANK_WIDTH-1:0]  ModeRegisterSelect;
      input [DDR2_ROW_WIDTH-1:0]   ModeOPCode;
      begin
	 ctl_mem_cs_n <= DecodeChipSelects( ChipSelect );
	 ctl_mem_ras_n <= 1'b0;
	 ctl_mem_cas_n <= 1'b0;
	 ctl_mem_we_n <= 1'b0;
	 ctl_mem_ba <= ModeRegisterSelect;
	 ctl_mem_addr <= ModeOPCode;
      end
   endtask
   
   task DDR2CMD_Refresh;
      input [DDR2_MAX_CS_BITS-1:0] ChipSelect;
      begin
	 ctl_mem_cs_n <= DecodeChipSelects( ChipSelect );
	 ctl_mem_ras_n <= 1'b0;
	 ctl_mem_cas_n <= 1'b0;
	 ctl_mem_we_n <= 1'b1;
      end
   endtask
   
   task DDR2CMD_SingleBankPrecharge;
      input [DDR2_MAX_CS_BITS-1:0] ChipSelect;
      input [DDR2_MAX_BANK_BITS-1:0] BankSelect;
      begin
	 ctl_mem_cs_n <= DecodeChipSelects( ChipSelect );
	 ctl_mem_ras_n <= 1'b0;
	 ctl_mem_cas_n <= 1'b1;
	 ctl_mem_we_n <= 1'b0;
	 ctl_mem_ba <= BankSelect;
	 ctl_mem_addr[10] <= 1'b0;
      end
   endtask
   
   task DDR2CMD_AllBankPrecharge;
      input [DDR2_MAX_CS_BITS-1:0] ChipSelect;
      begin
	 ctl_mem_cs_n <= DecodeChipSelects( ChipSelect );
	 ctl_mem_ras_n <= 1'b0;
	 ctl_mem_cas_n <= 1'b1;
	 ctl_mem_we_n <= 1'b0;
	 ctl_mem_addr[10] <= 1'b1;
      end
   endtask
   
   task DDR2CMD_BankActivate;
      input [DDR2_MAX_CS_BITS-1:0] ChipSelect;
      input [DDR2_MAX_BANK_BITS-1:0] BankSelect;
      input [DDR2_MAX_ADDR_BITS-1:0] RowSelect;
      begin
	 ctl_mem_cs_n <= DecodeChipSelects( ChipSelect );
	 ctl_mem_ras_n <= 1'b0;
	 ctl_mem_cas_n <= 1'b1;
	 ctl_mem_we_n <= 1'b1;
	 ctl_mem_ba <= BankSelect;
	 ctl_mem_addr <= RowSelect;
      end
   endtask
   
   task DDR2CMD_WriteNoPrecharge;
      input [DDR2_MAX_CS_BITS-1:0] ChipSelect;
      input [DDR2_MAX_BANK_BITS-1:0] BankSelect;
      input [DDR2_MAX_ADDR_BITS-1:0] ColumnSelect;
      begin
	 ctl_mem_cs_n <= DecodeChipSelects( ChipSelect );
	 ctl_mem_ras_n <= 1'b1;
	 ctl_mem_cas_n <= 1'b0;
	 ctl_mem_we_n <= 1'b0;
	 ctl_mem_ba <= BankSelect;
	 ctl_mem_addr[DDR2_ROW_WIDTH-1:11] <= ColumnSelect[DDR2_MAX_ADDR_BITS-1:11/*10*/];
	 ctl_mem_addr[10] <= 1'b0;
	 ctl_mem_addr[9:0] <= ColumnSelect[9:0];
      end
   endtask
   
   task DDR2CMD_WriteWithPrecharge;
      input [DDR2_MAX_CS_BITS-1:0] ChipSelect;
      input [DDR2_MAX_BANK_BITS-1:0] BankSelect;
      input [DDR2_MAX_ADDR_BITS-1:0] ColumnSelect;
      begin
	 ctl_mem_cs_n <= DecodeChipSelects( ChipSelect );
	 ctl_mem_ras_n <= 1'b1;
	 ctl_mem_cas_n <= 1'b0;
	 ctl_mem_we_n <= 1'b0;
	 ctl_mem_ba <= BankSelect;
	 ctl_mem_addr[DDR2_ROW_WIDTH-1:11] <= ColumnSelect[DDR2_MAX_ADDR_BITS-1:11/*10*/];
	 ctl_mem_addr[10] <= 1'b1;
	 ctl_mem_addr[9:0] <= ColumnSelect[9:0];
      end
   endtask
   
   task DDR2CMD_ReadNoPrecharge;
      input [DDR2_MAX_CS_BITS-1:0] ChipSelect;
      input [DDR2_MAX_BANK_BITS-1:0] BankSelect;
      input [DDR2_MAX_ADDR_BITS-1:0] 	       ColumnSelect;
      begin
	 ctl_mem_cs_n <= DecodeChipSelects( ChipSelect );
	 ctl_mem_ras_n <= 1'b1;
	 ctl_mem_cas_n <= 1'b0;
	 ctl_mem_we_n <= 1'b1;
	 ctl_mem_ba <= BankSelect;
	 ctl_mem_addr[DDR2_ROW_WIDTH-1:11] <= ColumnSelect[DDR2_MAX_ADDR_BITS-1:11]; //:10
	 ctl_mem_addr[10] <= 1'b0;
	 ctl_mem_addr[9:0] <= ColumnSelect[9:0];
      end
   endtask
   
   task DDR2CMD_ReadWithPrecharge;
		input [DDR2_MAX_CS_BITS-1:0] ChipSelect;
      input [DDR2_MAX_BANK_BITS-1:0] 	     BankSelect;
      input [DDR2_MAX_ADDR_BITS-1:0] 	     ColumnSelect;
      begin
	 ctl_mem_cs_n <= DecodeChipSelects( ChipSelect );
	 ctl_mem_ras_n <= 1'b1;
	 ctl_mem_cas_n <= 1'b0;
	 ctl_mem_we_n <= 1'b1;
	 ctl_mem_ba <= BankSelect;
	 ctl_mem_addr[DDR2_ROW_WIDTH-1:11] <= ColumnSelect[DDR2_MAX_ADDR_BITS-1:10];
	 ctl_mem_addr[10] <= 1'b1;
	 ctl_mem_addr[9:0] <= ColumnSelect[9:0];
      end
   endtask
   
//This will be used as the refresh timer.  It decrements on each clock cycle, and I check underflow based on //the high bit to decide when I need to refresh.  It has enough range to handle any expected RAM.
   reg [15:0] RefreshTimer;
   
   //These timers keep track of how many clock cycles I need to wait before I can issue any particular command.
   //They are loaded as commands are issued, to establish minimum spacing between commands, such as between
   //reads, or from a write until a precharge, etc.  The timers are implemented has shift registers, because
   //	this proved to be the fastest and most compact way of doing it.  There is a timer for each possible
   //	command, and in some cases for each bank, which is shifted on every clock cycle.  The last flip flop
   //in the shift register chain serves as a flag indicating when that particular command may be issued again.
   // The timers get loaded whenever commands are executed.  Where multiple timings are involved, a maximizing
   //	loads the greater of the possible values.
   // ACTIVATE and PRECHARGE both have timing parameters associated with them that are per bank.  That is, 
   //the parameter only needs to be observed for the accesses to the same bank, but not between banks.  In //order to get maximum efficiency, I keep a separate timer for each of these commands for each bank.
   localparam DDR2_CMD_TIMER_READ					= 0;
   localparam DDR2_CMD_TIMER_WRITE					= 1;
   localparam DDR2_CMD_TIMER_LOAD_MODE				= 2;
   localparam DDR2_CMD_TIMER_REFRESH				= 3;
   localparam DDR2_CMD_TIMER_PRECHARGE_ALL			= 4;
   localparam DDR2_CMD_TIMER_ACTIVATE_BASE			= 5;
   localparam DDR2_CMD_TIMER_PRECHARGE_ONE_BASE	= DDR2_CMD_TIMER_ACTIVATE_BASE + DDR2_NUM_BANKS;
   
   localparam NUM_DDR2_CMD_TIMERS = DDR2_CMD_TIMER_PRECHARGE_ONE_BASE + DDR2_NUM_BANKS;
//For the bit width, 4 would be sufficient for 4 banks, since that would be 8+5 = 13, but with 8 banks that //becomes 16+5 = 21, so I'll allow 5 bits for the indicies into this array.
   localparam NUM_DDR2_CMD_TIMERS_WIDTH = 5;
   // I can make these shift registers really long because the tools will optimize any excess away for me.
   // Allowing 64 time steps here should be sufficient for speeds up to 300MHz
   localparam DDR2_TIMER_LEN = 64;
   localparam DDR2_TIMER_LEN_LOG2 = 6;
   reg [DDR2_TIMER_LEN-1:0] CommandReadyShiftTimers[0:NUM_DDR2_CMD_TIMERS-1];
   
//These timers keep track of the time since the last ACTIVATE command was issued to each open bank row.  This //is important because there is a maximum ACTIVE to PRECHARGE time, on tRAS, typically 70,000ns, which is about //21,000 clock cycles at 300MHz, so I made these timers 18-bits wide.
   reg [17:0] 		    CloseBankTimers[0:DDR2_NUM_BANKS-1];
   reg 			    CloseBankTimerFlags[0:DDR2_NUM_BANKS-1];
   reg [DDR2_BANK_WIDTH-1:0] CloseBankNumber;
   
//There are actually two state machines in the controller, and three stages.  Stage 0 handles the user //interface and flow control.  Stage 1 watches the refresh, calibration and row closing timers and keeps track //of which	rows are currently active.  Stage 2 enforces timing constraints and actually issues commands on the //DDR2external bus.
   
   // These are the states for the stage 1 and stage 2 state machines.
   reg [1:0] 		     Stage1State;
   reg 			     Stage1BankActive_H;
   reg [DDR2_ROW_WIDTH-1:0]  Stage1CurrentBankRow;
   localparam STAGE1_STATE_IDLE		= 2'd0;
   localparam STAGE1_STATE_CLOSE_BANK	= 2'd1;
   localparam STAGE1_STATE_REFRESH	= 2'd2;
   localparam STAGE1_STATE_USER_COMMAND	= 2'd3;
   
   reg [3:0] 		     Stage2State;
   localparam STAGE2_STATE_IDLE		    = 4'd0;
   localparam STAGE2_STATE_LOAD_MODE	    = 4'd1;
   localparam STAGE2_STATE_REFRESH	    = 4'd2;
   localparam STAGE2_STATE_PRECHARGE_ONE    = 4'd3;
   localparam STAGE2_STATE_PRECHARGE_ALL    = 4'd4;
   localparam STAGE2_STATE_RW_PRECHARGE_ONE = 4'd5;
   localparam STAGE2_STATE_RW_ACTIVATE	    = 4'd6;
   localparam STAGE2_STATE_READ		    = 4'd7;
   localparam STAGE2_STATE_WRITE	    = 4'd8;
   
  //I created this task because XST won't correctly infer a state machine if I just put all of these statements
   //at the beginning of the always() block.  It likes to see the case() as the first thing, so I had to put
   //	this stuff into a task and just call the task at the beginning of every state.
   task BusControl_DefaultActions;
      begin
// Shift all timer registers down one position by default.  Bit 0 of each is the current value of the
//	respective ready flag.
	 for( i = 0; i < NUM_DDR2_CMD_TIMERS; i = i + 1 ) begin
	    CommandReadyShiftTimers[i] <= { 1'b1, CommandReadyShiftTimers[i][DDR2_TIMER_LEN-1:1] };
	 end
	 
	 // Decrement the maximum RAS (tRAS) timers, if they haven't already expired
	 for( i = 0; i < DDR2_NUM_BANKS; i = i + 1 ) begin
	    if (CloseBankTimers[i] != 0) begin
	       CloseBankTimers[i] <= CloseBankTimers[i] - 1;
	       CloseBankTimerFlags[i] <= 1'b0;
	    end
	    else
	      CloseBankTimerFlags[i] <= 1'b1;
	 end
	 RefreshTimer <= RefreshTimer - 1;
	 ctl_refresh_ack <= 1'b0;
	 
	 // Move the data in the output queue forward.  Note that some of this may be
	 //	overwritten below if a new write command is issue, but because of the
	 //	observance of CLOCKS_CCD and so on, no good data should get overwritten.
	 WriteCycleStarting_H[WRITE_ENABLE_QUEUE_LEN-1] <= 1'b0;
	 for( i = 0; i < WRITE_ENABLE_QUEUE_LEN-1; i = i + 1 ) 
	   WriteCycleStarting_H[i] <= WriteCycleStarting_H[i+1];
	 
	 // Advance the DQSActive Queue, which gives me a flag to say when DQS will
	 //	be actively driven from the DDR.  I use that to sample for timing acquistion.
	 // Again, this can be overridden below.
	 ReadDQSActiveQueue[READ_DQS_ACTIVE_QUEUE_LEN-1] <= 1'b0;
	 for( i = 0; i < READ_DQS_ACTIVE_QUEUE_LEN-1; i = i + 1 ) 
	   ReadDQSActiveQueue[i] <= ReadDQSActiveQueue[i+1];
	 
	 WriteDQSActiveQueue[WRITE_DQS_ACTIVE_QUEUE_LEN-1] <= 1'b0;
	 for( i = 0; i < WRITE_DQS_ACTIVE_QUEUE_LEN-1; i = i + 1 )
	   WriteDQSActiveQueue[i] <= WriteDQSActiveQueue[i+1];
	 
// I used to have this call here, but the Xilinx XST synthesizer claimed that I am multi-driving the Staged_A
//	bus because I was doing a task within a task.  So, I had to move this call back to the always block.
	 ctl_mem_dqs_burst <= |WriteCycleStarting_H[2:1];
	 ctl_mem_wdata_valid <= |WriteCycleStarting_H[3:2];
	 fifo_rdreq <= |WriteCycleStarting_H[4:3];
	       end
   endtask
 
// This task is called when I know that it is ok for a new command to be accepted from the user.  That would be
   //	the case when stage 1 is empty, or I know that it is advancing.
   task BusControl_AdvanceInputPipelineStage0ToStage1;
      begin
	 
// Stage 0 Processing - Just latch the data locally in order to avoid timing problems getting the data here.
	 // Look for a new request at the module inputs.  The acknowledge will be high unless input pipeline
	 //	position 1 is already full.
	 if (bus_ctl_cmd_req == 1'b1 && bus_ctl_ready == 1'b1) begin
	 // Look for a new request at the module inputs.  The acknowledge will be high unless input pipeline
	 //	position 1 is already full and it's not advancing on this cycle.
	    InputPipeline_Valid_H[1] <= 1'b1;
	    InputPipeline_Cmd[1] <= bus_ctl_cmd;
	    InputPipeline_CmdAddress[1] <= bus_ctl_addr;
	    // Stop acknowledging on the next cycle because it should have already been acknowledged
	    bus_ctl_ready <= 1'b0;
	 end
	 else begin
	    InputPipeline_Valid_H[1] <= 1'b0;
	    bus_ctl_ready <= 1'b1;
	 end
      end
   endtask
   
   
//This subroutine is called when stage 2 is empty, or when it knows that it is advancing.  The purpose here is 
//to perform memory reads and accesses to start processing for stage 1.  The results of that are then passed to //the stage 1 state machine where the appropriate command is issued to stage 2.  Previously, stage 1 was a //single clock cycle operation, but I was having trouble making timing at 200MHz, so now stage 1 takes 2 clock //cycles to complete.  This is ok, since the minimum spacing for commands leaving stage 2 is also 2 clock //cycles.
   task BusControl_AdvanceInputPipelineStage1ToStage2;
      begin
	 // If I need to close a bank that has been open for too long (precharge it)
	 if (CurrentBankActive_H[CloseBankNumber] == 1'b1 && CloseBankTimerFlags[CloseBankNumber] == 1'b1) begin
	    Stage1State <= STAGE1_STATE_CLOSE_BANK;
	 end
	 // Check to see if the refresh timer has expired, by checking underflow on this 16-bit register
	 else if (RefreshTimer[15] == 1'b1) begin
	    // If all banks are precharged (or closed), I can issue the refresh
	    if (|CurrentBankActive_H == 1'b0) begin
	       Stage1State <= STAGE1_STATE_REFRESH;
	    end
// I need to precharge any open banks to close them.  If I just do a precharge all, I seem to get
//	read errors, as I have experienced when inserting extra precharges before.  So, I need to go
//	through each of the banks and issue individual precharges for each one that is active before
//	I can do the actual precharge.  I'll use CloseBankNumber to do that.
	    else if (CurrentBankActive_H[CloseBankNumber] == 1'b1) begin
	       Stage1State <= STAGE1_STATE_CLOSE_BANK;
	    end
	  // If I know that a refresh is needed, and not all banks have been closed, advance the bank number
	  //	so that I will find the one that is still open.
	    else
	      CloseBankNumber <= CloseBankNumber + 1;
	 end
	 else begin
// Advance this so that on the next call I will check the next bank's expiration timer and see if it needs to //be closed
	    CloseBankNumber <= CloseBankNumber + 1;
	    
	    // Now see if there is a user command waiting for me
	    if (InputPipeline_Valid_H[1] == 1'b1) begin
	       Stage1BankActive_H <= CurrentBankActive_H[InputPipeline_BankSelectBits[1]];
	       Stage1CurrentBankRow <= CurrentBankRow[InputPipeline_BankSelectBits[1]];
	       Stage1State <= STAGE1_STATE_USER_COMMAND;
	       
// Also at this point, I need to start acknowledging the next command that will come from the user.
//	I know that on the next cycle I will be sending stage 1 to stage 2, which means that I will be
//	able to accept a new user command at the end of the next cycle as well (transfer it from stage 0
//	to stage 1).  That can only happen if bus_ctl_cmd_req == 1'b1 && bus_ctl_ready == 1'b1, so I
//	need to set that up now.
	       bus_ctl_ready <= 1'b1;
	    end
	 end
	 
// Always put stage 2 into the IDLE state when it first asks for a new command.  I don't want stage 2
//	doing anything until the stage 1 state machine has a chance to issue the new command.
	 InputPipeline_Valid_H[2] <= 1'b0;
	 Stage2State <= STAGE2_STATE_IDLE;
      end
   endtask
   
   
   // These tasks allow me to load a new value into the command timers if the new value would set
   //	it to a higher value2.  The timers keep track of the earliest possible time that each command
   //	can be issued to the DDR.
   // I need to load the value - 1 because the timer is supposed to be decrementing on the clock
   //	cycle where these are called.  Also, I need to be careful to do all comparisons before
   //	doing the decrement, in case any of the values are zero.
   function [DDR2_TIMER_LEN_LOG2-1:0] ShiftTimerMax2;
      input [DDR2_TIMER_LEN_LOG2-1:0] Value1;
      input [DDR2_TIMER_LEN_LOG2-1:0] Value2;
      begin
	 if (Value1 > Value2)
	   ShiftTimerMax2 = Value1;
	 else
	   ShiftTimerMax2 = Value2;
      end
   endfunction
   function [DDR2_TIMER_LEN-1:0] ShiftTimerDelayVector;
      input [DDR2_TIMER_LEN_LOG2-1:0] DelayValue;
      integer 			      i;
      begin
	 // In order to avoid errors resulting from "non-constant" array ranges, I had to re-write
	 //	the code as shown below.  In reality, the ranges are always constant, but I guess the
	 //	Modelsim compiler only looks skin deep.
	 
	 for( i = 0; i < DDR2_TIMER_LEN; i = i + 1 ) begin
	    // Here I only insert 0's up to DelayValue-1 because I am loading a flag that won't be
	    //	read until the end of the next clock cycle.  So, I need to anticipate the load a bit.
	    if (DelayValue > 0 && i < (DelayValue-1))
	      ShiftTimerDelayVector[i] = 1'b0;
	    else
	      ShiftTimerDelayVector[i] = 1'b1;
	 end
      end
   endfunction
   task MaximizeTimerLoad1;
      input [NUM_DDR2_CMD_TIMERS_WIDTH-1:0] TimerIndex;
      input [DDR2_TIMER_LEN_LOG2-1:0] 	    DelayValue1;
      begin
       	 CommandReadyShiftTimers[TimerIndex] <=
					       { 1'b1, CommandReadyShiftTimers[TimerIndex][DDR2_TIMER_LEN-1:1] } &
					       ShiftTimerDelayVector(DelayValue1);
      end
   endtask
   task MaximizeTimerLoad2;
      input [NUM_DDR2_CMD_TIMERS_WIDTH-1:0] TimerIndex;
      input [DDR2_TIMER_LEN_LOG2-1:0] 	    DelayValue1;
      input [DDR2_TIMER_LEN_LOG2-1:0] 	    DelayValue2;
      begin
	 CommandReadyShiftTimers[TimerIndex] <=
					       { 1'b1, CommandReadyShiftTimers[TimerIndex][DDR2_TIMER_LEN-1:1] } &
					       ShiftTimerDelayVector(ShiftTimerMax2(DelayValue1,DelayValue2));
      end
   endtask
   
   reg push_Stage2toStage1;
   
   // This always block contains the stage 1 and stage 2 state machines of the pipeline.
   always @(negedge rst_n or posedge clk_mem_interface) begin
      if (rst_n == 1'b0) begin 
	 Stage1State <= STAGE1_STATE_IDLE;
	 Stage1BankActive_H <= 0;
	 Stage1CurrentBankRow <= 0;
	 
	 for( i = 0; i < DDR2_NUM_BANKS; i = i + 1 ) begin
	    CurrentBankActive_H[i] <= 1'b0;
	    CurrentBankRow[i] <= 0;
	    CloseBankTimers[i] <= CLOCKS_RAS_MAX;
	 end
	 CloseBankNumber <= 0;
	 RefreshTimer <= CLOCKS_REFI;
	 
	 bus_ctl_ready <= 1'b0;
	 ctl_mem_wdata_valid <= 1'b0;
	 ctl_mem_dqs_burst <= 1'b0;
	 ctl_refresh_ack <= 1'b0;
	 
	 for( i = 0; i < NUM_DDR2_CMD_TIMERS; i = i + 1 )
	   CommandReadyShiftTimers[i] <= ~0;
	 
	 for( i = 0; i < WRITE_ENABLE_QUEUE_LEN; i = i + 1 )
	   WriteCycleStarting_H[i] <= 1'b0;
	 
	 for( i = 0; i < READ_DQS_ACTIVE_QUEUE_LEN; i = i + 1 )
	   ReadDQSActiveQueue[i] <= 1'b0;
	 
	 for( i = 0; i < WRITE_DQS_ACTIVE_QUEUE_LEN; i = i + 1 )
	   WriteDQSActiveQueue[i] <= 1'b0;
	 
	 for( i = 1; i <= INPUT_PIPELINE_LEN; i = i + 1 ) begin
	    InputPipeline_Valid_H[i] <= 0;
	    InputPipeline_Cmd[i] <= 0;
	    InputPipeline_CmdAddress[i] <= 0;
	 end
	 
	 Stage2State <= STAGE2_STATE_IDLE;
	 DDR2CMD_Idle();
      end
      else begin
	 BusControl_DefaultActions();
	 
	 // If stage 1 is empty, try to advance stage 0 to 1
	 if (InputPipeline_Valid_H[1] == 1'b0) begin
	    BusControl_AdvanceInputPipelineStage0ToStage1();
	 end
	 if (push_Stage2toStage1) begin
	    InputPipeline_Valid_H[1] <= InputPipeline_Valid_H[2];
	    InputPipeline_Cmd[1] <= InputPipeline_Cmd[2];
	    InputPipeline_CmdAddress[1] <= InputPipeline_CmdAddress[2];
	    Stage1State <= STAGE1_STATE_USER_COMMAND;
	    push_Stage2toStage1 <= 1'b0;
	 end	
	 
// Stage 1 Processing - Look at the request and issue one or more commands as appropriate to stage 2.
//For reads/writes this could include closing the current row and activating a new one.  I also handle
//refresh operations from this point as well as closing rows that have been open for too long.
// Note that there is no jump out of the idle state.  This is handled by a all to
//BusControl_AdvanceInputPipelineStage1ToStage2() from the stage 2 state machine.  When a command
//completes, it jumps back to idle.  However, the assignment of Stage1State <= STAGE1_STATE_IDLE can
//be overridden by the state 2 state machine below, since it comes after this state machine in the
//code flow.
	 case(Stage1State)
	   
	   STAGE1_STATE_IDLE: begin
	   end
	   
	   STAGE1_STATE_CLOSE_BANK: begin
	      InputPipeline_Valid_H[2] <= 1'b1;
	      CurrentBankActive_H[CloseBankNumber] <= 1'b0;
	      InputPipeline_CmdAddress[2] <= { CloseBankNumber[DDR2_BANK_WIDTH-1:0], {(DDR2_ROW_WIDTH+DDR2_COL_WIDTH+3){1'b0}} };
	      Stage2State <= STAGE2_STATE_PRECHARGE_ONE;
	      
// Since this command is internally generated, and not a command from the user, I can't advance
//Stage 0 to Stage 1 here, or I might drop a user command.  Instead, I'll just transition
//back to idle so that the next call to BusControl_AdvanceInputPipelineStage1ToStage2() will
//process the user command.
	      Stage1State <= STAGE1_STATE_IDLE;
	   end
	   
	   STAGE1_STATE_REFRESH: begin
	      InputPipeline_Valid_H[2] <= 1'b1;
	      RefreshTimer <= RefreshTimer + CLOCKS_REFI;
	      Stage2State <= STAGE2_STATE_REFRESH;
	      ctl_refresh_ack <= 1'b1;
	      push_Stage2toStage1 <= 1'b1;
	      
// Since this command is internally generated, and not a command from the user, I can't advance
//Stage 0 to Stage 1 here, or I might drop a user command.  Instead, I'll just transition
//back to idle so that the next call to BusControl_AdvanceInputPipelineStage1ToStage2() will process the user //command.
	      Stage1State <= STAGE1_STATE_IDLE;
	   end
	   
	   STAGE1_STATE_USER_COMMAND: begin
	      
	      InputPipeline_Valid_H[2] <= InputPipeline_Valid_H[1];
	      InputPipeline_Cmd[2] <= InputPipeline_Cmd[1];
	      InputPipeline_CmdAddress[2] <= InputPipeline_CmdAddress[1];
	      
	      if (InputPipeline_Cmd[1] == `DDR2_CMD_READ || InputPipeline_Cmd[1] == `DDR2_CMD_WRITE) begin
		 // If the bank is not active, jump to the activate state
		 if (Stage1BankActive_H == 1'b0) begin
		    CurrentBankActive_H[InputPipeline_BankSelectBits[1]] <= 1'b1;
		    CurrentBankRow[InputPipeline_BankSelectBits[1]] <= InputPipeline_RowSelectBits[1];
		    // Reset the bank close timer, since I'm going to activate it now
		    CloseBankTimers[InputPipeline_BankSelectBits[1]] <= CLOCKS_RAS_MAX;
		    Stage2State <= STAGE2_STATE_RW_ACTIVATE;
		 end
// If the bank is active, but on a different row, jump to the precharge state to close it and reopen on the //right one
		 else if (Stage1CurrentBankRow != InputPipeline_RowSelectBits[1]) begin
		    CurrentBankRow[InputPipeline_BankSelectBits[1]] <= InputPipeline_RowSelectBits[1];
		    // Reset the bank close timer, since I'm going to activate it now
		    CloseBankTimers[InputPipeline_BankSelectBits[1]] <= CLOCKS_RAS_MAX;
		    Stage2State <= STAGE2_STATE_RW_PRECHARGE_ONE;
		 end
		 // If the bank is active and on the same row
		 else begin
		    if (InputPipeline_Cmd[1] == `DDR2_CMD_READ)
		      Stage2State <= STAGE2_STATE_READ;
		    else
		      Stage2State <= STAGE2_STATE_WRITE;
		 end
	      end
	      else if (InputPipeline_Cmd[1] == `DDR2_CMD_LOAD_MODE) begin
		 Stage2State <= STAGE2_STATE_LOAD_MODE;
	      end
	     // This is included only because you have to force a refresh during the initialization sequence
	     // Note that I don't jump to the state that will force a precharge all first, because I want to
                //obey the initialization procedure precisely.  Therefore, the initialization sequence issues
	     //	an explicit precharge all before doing the two required refresh commands.
	      else if (InputPipeline_Cmd[1] == `DDR2_CMD_REFRESH) begin
		 Stage2State <= STAGE2_STATE_REFRESH;
	      end
	      else if (InputPipeline_Cmd[1] == `DDR2_CMD_PRECHARGE_ALL) begin
		 for( i = 0; i < DDR2_NUM_BANKS; i = i + 1 )
		   CurrentBankActive_H[i] <= 1'b0;
		 Stage2State <= STAGE2_STATE_PRECHARGE_ALL;
	      end
	      else begin
		 InputPipeline_Valid_H[2] <= 1'b0;
		 Stage2State <= STAGE2_STATE_IDLE;
	      end
	      BusControl_AdvanceInputPipelineStage0ToStage1();
	      Stage1State <= STAGE1_STATE_IDLE;
	   end
	 endcase
	 
// Stage 2 Processing - The states are set up as chains of command sequences for different operations.
//A call to BusControl_AdvanceInputPipelineStage1ToStage2() will jump to the first state in a sequence
//and then that sequence will run until completion at which time it will advance itself by another call
//to BusControl_AdvanceInputPipelineStage1ToStage2().
// Evident here is the use of the command shift timers to hold the state machine back until a given
//command is allowed to be issued by the DDR2 timing parameters.  Also, the timers are loaded as each
//command is issued to create "blackout" periods during which a following command of the given type
//	may not be issued.
	 case(Stage2State)
	   
	   STAGE2_STATE_IDLE: begin
// I know that stage 2 is empty, so try to advance stage 1 to stage 2.  I only want to bump it this way
//if stage 1 is in the IDLE state.  If stage 1 is not in idle, then there is already something coming
//down the pipe for stage 2.
	      if (InputPipeline_Valid_H[2] == 1'b0 && Stage1State == STAGE1_STATE_IDLE) begin
		 BusControl_AdvanceInputPipelineStage1ToStage2();
	      end
	      DDR2CMD_Idle();
	   end
	   
	   STAGE2_STATE_LOAD_MODE: begin
	      if (CommandReadyShiftTimers[DDR2_CMD_TIMER_LOAD_MODE][0] == 1'b1) begin
		 // I'm loading all chip selects at the same time here.
		 DDR2CMD_LoadMode( SelectAllChipSelects, InputPipeline_CmdAddress[2][DDR2_ROW_WIDTH+:DDR2_BANK_WIDTH], InputPipeline_CmdAddress[2][DDR2_ROW_WIDTH-1:0] );
		 MaximizeTimerLoad1( DDR2_CMD_TIMER_READ, CLOCKS_MRD );
		 MaximizeTimerLoad1( DDR2_CMD_TIMER_WRITE, CLOCKS_MRD );
		 MaximizeTimerLoad1( DDR2_CMD_TIMER_LOAD_MODE, CLOCKS_MRD );
		 MaximizeTimerLoad1( DDR2_CMD_TIMER_REFRESH, CLOCKS_MRD );
		 MaximizeTimerLoad1( DDR2_CMD_TIMER_PRECHARGE_ALL, CLOCKS_MRD );
		 for( i = 0; i < DDR2_NUM_BANKS; i = i + 1 ) begin
		    MaximizeTimerLoad1( DDR2_CMD_TIMER_PRECHARGE_ONE_BASE + i, CLOCKS_MRD );
		    MaximizeTimerLoad1( DDR2_CMD_TIMER_ACTIVATE_BASE + i, CLOCKS_MRD );
		 end
		 BusControl_AdvanceInputPipelineStage1ToStage2();
	      end
	      else
		DDR2CMD_Idle();
	   end
	   
	   STAGE2_STATE_REFRESH: begin
	      if (CommandReadyShiftTimers[DDR2_CMD_TIMER_REFRESH][0] == 1'b1) begin
		 // This will do all banks of all chip selects
		 DDR2CMD_Refresh( SelectAllChipSelects );
		 MaximizeTimerLoad1( DDR2_CMD_TIMER_LOAD_MODE, CLOCKS_RFC );
		 MaximizeTimerLoad1( DDR2_CMD_TIMER_REFRESH, CLOCKS_RFC );
		 for( i = 0; i < DDR2_NUM_BANKS; i = i + 1 ) begin
		    MaximizeTimerLoad1( DDR2_CMD_TIMER_ACTIVATE_BASE + i, CLOCKS_RFC );
		 end
		 BusControl_AdvanceInputPipelineStage1ToStage2();
	      end
	      else
		DDR2CMD_Idle();
	   end
	   
	   STAGE2_STATE_PRECHARGE_ONE: begin
	      if (CommandReadyShiftTimers[DDR2_CMD_TIMER_PRECHARGE_ONE_BASE + InputPipeline_BankSelectBits[2]][0] == 1'b1) begin
		 DDR2CMD_SingleBankPrecharge( InputPipeline_ChipSelectBits[2], InputPipeline_BankSelectBits[2] );
		 MaximizeTimerLoad1( DDR2_CMD_TIMER_ACTIVATE_BASE + InputPipeline_BankSelectBits[2], CLOCKS_RP );
// I had to add these constraints when I started doing individual precharge commands before a refresh
//cycle.  It turned out that I couldn't just do one precharge all whether or not all the banks
//were activated, as this caused read errors.  Instead, I go through and check each bank to see
//if it is active, and only then to I issue a precharge to it.  When all banks are precharged,
//I issue the refresh command.
		 MaximizeTimerLoad1( DDR2_CMD_TIMER_REFRESH, CLOCKS_RP );
		 MaximizeTimerLoad1( DDR2_CMD_TIMER_PRECHARGE_ONE_BASE + InputPipeline_BankSelectBits[2], CLOCKS_RP );
		 MaximizeTimerLoad1( DDR2_CMD_TIMER_PRECHARGE_ALL, CLOCKS_RP );
		 BusControl_AdvanceInputPipelineStage1ToStage2();
	      end
	      else
		DDR2CMD_Idle();
	   end
	   
	   STAGE2_STATE_PRECHARGE_ALL: begin
	      if (CommandReadyShiftTimers[DDR2_CMD_TIMER_PRECHARGE_ALL][0] == 1'b1) begin
		 // This will do all banks of all chip selects
		 DDR2CMD_AllBankPrecharge( SelectAllChipSelects );
		 MaximizeTimerLoad1( DDR2_CMD_TIMER_LOAD_MODE, CLOCKS_RPA );
		 MaximizeTimerLoad1( DDR2_CMD_TIMER_REFRESH, CLOCKS_RPA );
		 for( i = 0; i < DDR2_NUM_BANKS; i = i + 1 ) begin
		    MaximizeTimerLoad1( DDR2_CMD_TIMER_ACTIVATE_BASE + i, CLOCKS_RPA );
		 end
		 BusControl_AdvanceInputPipelineStage1ToStage2();
	      end
	      else
		DDR2CMD_Idle();
	   end
	   
	   STAGE2_STATE_RW_PRECHARGE_ONE: begin
	      if (CommandReadyShiftTimers[DDR2_CMD_TIMER_PRECHARGE_ONE_BASE + InputPipeline_BankSelectBits[2]][0] == 1'b1) begin
		 DDR2CMD_SingleBankPrecharge( InputPipeline_ChipSelectBits[2], InputPipeline_BankSelectBits[2] );
		 MaximizeTimerLoad1( DDR2_CMD_TIMER_ACTIVATE_BASE + InputPipeline_BankSelectBits[2], CLOCKS_RP );
		 Stage2State <= STAGE2_STATE_RW_ACTIVATE;
	      end
	      else
		DDR2CMD_Idle();
	   end
	   
	   STAGE2_STATE_RW_ACTIVATE: begin
	      if (CommandReadyShiftTimers[DDR2_CMD_TIMER_ACTIVATE_BASE + InputPipeline_BankSelectBits[2]][0] == 1'b1) begin
		 // I will assume that it is precharged, and start the ACTIVATE command
		 DDR2CMD_BankActivate( InputPipeline_ChipSelectBits[2], InputPipeline_BankSelectBits[2], InputPipeline_RowSelectBits[2] );
		 // tRC is only between activates within the same bank
		 for( i = 0; i < DDR2_NUM_BANKS; i = i + 1 ) begin
		    if (i == InputPipeline_BankSelectBits[2])
		      MaximizeTimerLoad2( DDR2_CMD_TIMER_ACTIVATE_BASE + i, CLOCKS_RC, CLOCKS_RRD );
		    else
		      MaximizeTimerLoad1( DDR2_CMD_TIMER_ACTIVATE_BASE, CLOCKS_RRD );
		 end
		 MaximizeTimerLoad1( DDR2_CMD_TIMER_READ, CLOCKS_RCD );
		 MaximizeTimerLoad1( DDR2_CMD_TIMER_WRITE, CLOCKS_RCD );
		 MaximizeTimerLoad1( DDR2_CMD_TIMER_PRECHARGE_ALL, CLOCKS_RAS_MIN );
		 for( i = 0; i < DDR2_NUM_BANKS; i = i + 1 )
		   MaximizeTimerLoad1( DDR2_CMD_TIMER_PRECHARGE_ONE_BASE + i, CLOCKS_RAS_MIN );
		 if (InputPipeline_Cmd[2] == `DDR2_CMD_READ)
		   Stage2State <= STAGE2_STATE_READ;
		 else
		   Stage2State <= STAGE2_STATE_WRITE;
	      end
	      else
		DDR2CMD_Idle();
	   end
	   
	   STAGE2_STATE_READ: begin
	      if (CommandReadyShiftTimers[DDR2_CMD_TIMER_READ][0] == 1'b1) begin
		 DDR2CMD_ReadNoPrecharge( InputPipeline_ChipSelectBits[2], InputPipeline_BankSelectBits[2], InputPipeline_ColSelectBits[2] );
		 // Put a flag in the queue for each DQS pulse that will be coming back
		 ReadDQSActiveQueue[READ_DQS_ACTIVE_QUEUE_LEN-2] <= 1'b1;
		 ReadDQSActiveQueue[READ_DQS_ACTIVE_QUEUE_LEN-1] <= 1'b1;
		 MaximizeTimerLoad1( DDR2_CMD_TIMER_READ, CLOCKS_CCD );
		 // For Read To Write timing, I need to make sure that the data coming back from the
		 //read has finished it's last transfer, and then allow one extra clock cycle for the
		 //DDR2 data bus to turn around before I try to stuff write data onto it.  So, the read
		 //latency (RL) is the time from read command to the first read data on the bus.  If I
		 //add the burst length to that, I will be to the first clock cycle after the last read
		 //transfer is complete.  Add one more to allow for bus turn around, and that will be the
		//first clock cycle that I can put write data onto the DDR2 data bus.  So that looks like
	 //this: CLOCKS_RL + BURST_LENGTH/2 + 1
	 //Then I need to subtract the write latency (WL), which is the time from the write command
		//to when the write data is put onto the bus.  Once I do that, I have the total number of
		 //clock cycles that I need to allow after a read before I can issue a write command, or:
		 //CLOCKS_RL + BURST_LENGTH/2 + 1 - CLOCKS_WL
		 //In addition, I will observe the normal CLOCKS_CCD timing, though this is guaranteed to
		 //always be less than the Read To Write timing.
		 MaximizeTimerLoad2( DDR2_CMD_TIMER_WRITE, CLOCKS_CCD, CLOCKS_RL + BURST_LENGTH/2 + 1 - CLOCKS_WL );
		 // The Read to Precharge timing has two rules.  I have to observe the analog tRTP, but
		 //there is also another timing constraint that is based on tRTP and some other stuff.
		 MaximizeTimerLoad2( DDR2_CMD_TIMER_PRECHARGE_ALL, CLOCKS_RTP, CLOCKS_AL + BURST_LENGTH/2 + ShiftTimerMax2(CLOCKS_RTP, 2) - 2 );
		 MaximizeTimerLoad2( DDR2_CMD_TIMER_PRECHARGE_ONE_BASE + InputPipeline_BankSelectBits[2], CLOCKS_RTP, CLOCKS_AL + BURST_LENGTH/2 + ShiftTimerMax2(CLOCKS_RTP, 2) - 2 );
		 BusControl_AdvanceInputPipelineStage1ToStage2();
	      end
	      else
		DDR2CMD_Idle();
	   end
	   
	   STAGE2_STATE_WRITE: begin
	      if (CommandReadyShiftTimers[DDR2_CMD_TIMER_WRITE][0] == 1'b1) begin
		 DDR2CMD_WriteNoPrecharge( InputPipeline_ChipSelectBits[2], InputPipeline_BankSelectBits[2], InputPipeline_ColSelectBits[2] );
	//This will appear at the DQ and DM pins as outputs once it shifts to index 0 in each of these
	//arrays.  Normally, the write latency is 5, so CLOCKS_WL-5 means that it will get clocked into
	//the shifter on the next rising edge, and appear on the ODDR output pins on the positive edge
	//after that.  I have to skew it across the queue like this because of the strange way that
	//data is clocked through the ODDR itself.
	// I have to be selective about loading the queue because there could be remains of the last
	//transfer at WriteDataOutputQueue[CLOCKS_WL-2][2*DDR2_DQ_WIDTH-1:DDR2_DQ_WIDTH]
		 WriteCycleStarting_H[WRITE_ENABLE_QUEUE_LEN-1] <= 1'b1;
		 
		 // Put a flag in the queue for each DQS pulse that I will be generating
		 WriteDQSActiveQueue[WRITE_DQS_ACTIVE_QUEUE_LEN-2] <= 1'b1;
		 WriteDQSActiveQueue[WRITE_DQS_ACTIVE_QUEUE_LEN-1] <= 1'b1;
		 // This is the write to read delay
		 // WTRTimer <= CLOCKS_WL + BURST_LENGTH/2 + CLOCKS_WTR - CLOCKS_AL - 1;
		 MaximizeTimerLoad2( DDR2_CMD_TIMER_READ, CLOCKS_CCD, CLOCKS_WL + BURST_LENGTH/2 + CLOCKS_WTR - CLOCKS_AL );
		 MaximizeTimerLoad1( DDR2_CMD_TIMER_WRITE, CLOCKS_CCD );
		 // The write recovery time is actually tWL + Burst Cycles + tWR
		 // WRTimer <= CLOCKS_WL + BURST_LENGTH/2 + CLOCKS_WR - 1;
		 MaximizeTimerLoad1( DDR2_CMD_TIMER_PRECHARGE_ALL, CLOCKS_WL + BURST_LENGTH/2 + CLOCKS_WR );
		 MaximizeTimerLoad1( DDR2_CMD_TIMER_PRECHARGE_ONE_BASE + InputPipeline_BankSelectBits[2], CLOCKS_WL + BURST_LENGTH/2 + CLOCKS_WR );
		 BusControl_AdvanceInputPipelineStage1ToStage2();
	      end
	      else
		DDR2CMD_Idle();
	   end
	 endcase
      end
   end
   assign ctl_doing_read =  ReadDQSActiveQueue[READ_DQS_ACTIVE_QUEUE_LEN-1] | ReadDQSActiveQueue[READ_DQS_ACTIVE_QUEUE_LEN-2];
endmodule
