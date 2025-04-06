module ddr2_driver(
		   input clk,
		   input rst_n,
		   input wire ready,
                         input wire rdata_valid,
		   input wire [143:0] rdata,
		   input wire wr_req_from_tmto,
		   input wire [143:0] tmto_fifo_q
                         output reg burst_begin,
		   output reg rd_req,
		   output reg wr_req,
		   output reg [31:0] cmd_addr,
		   output wire [143:0] wdata,
                         output wire tmto_fifo_rdacked
		   );
   function [31:0] LFSRAddress;
      input [31:0] 		      OldAddress;
      begin
	 LFSRAddress[31:30] = 0;
	 LFSRAddress[29:0] = OldAddress[29:0] + 32;
      end
   endfunction
   reg [31:0] NextAddress;
   reg [1:0]  BurstState;
   reg [1:0]  TestState;
   localparam TEST_STATE_INIT	= 2'd0;
   localparam TEST_STATE_WRITE	= 2'd1;
   localparam TEST_STATE_READ	= 2'd2;
   reg [3:0]  wr_rd_lat;
   assign wdata = tmto_fifo_q;
   assign  tmto_fifo_rdacked = (ready && wr_req) ? 1'b1 : 1'b0;
   always @(negedge rst_n or posedge clk) begin
      if (!rst_n) begin
	 TestState <= TEST_STATE_INIT;
	 BurstState <= 2'b00;
      end
      else begin
	 case(TestState)
	   TEST_STATE_INIT: begin
	      rd_req <= 0;
	      wr_req <= 0;
	      cmd_addr <= 0;
	      NextAddress <= 32;
	      wr_rd_lat <= 4'h0;
	      if(wr_req_from_tmto) begin
		 TestState <= TEST_STATE_WRITE;
		 burst_begin <= 1'b1;
		 BurstState <= 2'b01;
		 wr_req <= 1'b1;
	      end
	   end
	   TEST_STATE_WRITE: begin
	      rd_req <= 1'b0;
	      case(BurstState)
		2'b00: begin
		   if (wr_req_from_tmto) begin
		      burst_begin <= 1'b1;
		      BurstState <= 2'b01;
		      cmd_addr <= NextAddress;
		      NextAddress <= LFSRAddress(NextAddress);
		      wr_req <= 1'b1;
		      wr_rd_lat <= 4'h0;
		   end
		   else begin
		      burst_begin <= 1'b0;
		      BurstState <= 2'b00;
		      wr_req <= 1'b0;
		      wr_rd_lat <= wr_rd_lat + 4'h1;
		   end
		end
		2'b01: begin
		   wr_rd_lat <= 4'h0;
		   if (ready)begin
		      BurstState <= 2'b11;
		      burst_begin <= 1'b0;
		      wr_req <= 1'b1;
		   end
		   else begin
		      BurstState <= 2'b01;
		      burst_begin <= 1'b0;
		      wr_req <= 1'b1;
		   end
		end
		2'b11: begin
		   wr_rd_lat <= 4'h0;
		   if (ready)begin
		      if (wr_req_from_tmto) begin
		      	 burst_begin <= 1'b1;
			 BurstState <= 2'b01;
			 cmd_addr <= NextAddress;
			 NextAddress <= LFSRAddress(NextAddress);
			 wr_req <= 1'b1;
		      end
		      else begin
		      	 burst_begin <= 1'b0;
			 BurstState <= 2'b00;
			 wr_req <= 1'b0;
		      end
		   end
		   else begin
		      burst_begin <= 1'b0;
		      BurstState <= 2'b11;
		      wr_req <= 1'b1;
		   end
 		end
	      endcase	
	      if (ready && !wr_req_from_tmto && (wr_rd_lat == 4'hF)&&(BurstState == 2'b00)) begin
		 wr_req <= 1'b0;
		 rd_req <= 1'b1;
		 cmd_addr <=  NextAddress - 64;
		 TestState <= TEST_STATE_READ;
		 wr_rd_lat <= 4'h0;
	      end
	   end
	   TEST_STATE_READ: begin
	      if (ready && (cmd_addr == NextAddress-64)) begin
		 rd_req <= 1'b1;
		 wr_req <= 1'b0;
		 cmd_addr <= NextAddress - 32;
		 wr_rd_lat <= 4'h0;
	      end
	      else begin
		 wr_rd_lat <= 4'h0;
		 wr_req <= 1'b0;
		 if(ready)
		   rd_req <= 1'b0;
	      end
	      if (wr_req_from_tmto) begin
		 burst_begin <= 1'b1;
		 BurstState <= 2'b01;
		 cmd_addr <= NextAddress;
		 NextAddress <= LFSRAddress(NextAddress);
		 wr_req <= 1'b1;
		 wr_rd_lat <= 4'h0;
		 TestState <= TEST_STATE_WRITE;
	      end
	   end
	 endcase
      end
   end 
endmodule // ddr2_driver
