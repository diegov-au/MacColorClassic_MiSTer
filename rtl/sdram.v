// sdram.v
//
// Copyright (c) 2015 Till Harbaum <till@harbaum.org> 
// 
// This source file is free software: you can redistribute it and/or modify 
// it under the terms of the GNU General Public License as published 
// by the Free Software Foundation, either version 3 of the License, or 
// (at your option) any later version. 
// 
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of 
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the 
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License 
// along with this program.  If not, see <http://www.gnu.org/licenses/>. 

module sdram 
(
	output              sd_clk,
`ifdef TB_NO_TRISTATE
	output reg [15:0]   sd_data,
	input      [15:0]   sd_data_in,
`else
	inout  reg [15:0]   sd_data,
`endif
	output reg [12:0]   sd_addr,
	output     [1:0]    sd_dqm,
	output reg [1:0]    sd_ba,
	output              sd_cs,
	output              sd_we,
	output              sd_ras,
	output              sd_cas,

	input               init,
	input               clk_64,
	input               clk_8,

	input [15:0]        din,
	output reg [15:0]   dout,
	input [23:0]        addr,
	input [1:0]         ds,
	input               oe,
	input               we,

	input               flp_win,
	input  [23:0]       flp_addr,
	input               flp_guard,

	input               dl_req,
	input               dl_slot,
	input  [23:0]       dl_addr,
	input  [15:0]       dl_din,
	output reg          dl_ack,

	input               eth_req,
	input               eth_we,
	input  [23:0]       eth_addr,
	input  [15:0]       eth_din,
	output reg          eth_ack,
	output reg [15:0]   eth_dout,

	output reg          cpu_done,
	output reg [15:0]   cpu_dout
);

localparam RASCAS_DELAY   = 3'd2;
localparam BURST_LENGTH   = 3'b000;
localparam ACCESS_TYPE    = 1'b0;
localparam CAS_LATENCY    = 3'd2;
localparam OP_MODE        = 2'b00;
localparam NO_WRITE_BURST = 1'b1;

localparam MODE = { 3'b000, NO_WRITE_BURST, OP_MODE, CAS_LATENCY, ACCESS_TYPE, BURST_LENGTH}; 

localparam STATE_FIRST     = 3'd0;
localparam STATE_CMD_START = 3'd0;
localparam STATE_CMD_CONT  = STATE_CMD_START  + RASCAS_DELAY;
localparam STATE_READ      = STATE_CMD_CONT + CAS_LATENCY + 4'd3;
localparam STATE_LAST      = 3'd7;

reg [2:0] t;
always @(posedge clk_64) begin
	if(((t == STATE_LAST)  && ( clk_8 == 0)) ||
		((t == STATE_FIRST) && ( clk_8 == 1)) ||
		((t != STATE_LAST) && (t != STATE_FIRST)))
			t <= t + 3'd1;
end

reg [9:0] reset;
always @(posedge clk_64) begin
	if(init)	reset <= 10'h3ff;
	else if((t == STATE_LAST) && (reset != 0))
		reset <= reset - 10'd1;
end

initial reset = 10'h3FF;
initial t     = 3'd0;

localparam CMD_INHIBIT         = 4'b1111;
localparam CMD_NOP             = 4'b0111;
localparam CMD_ACTIVE          = 4'b0011;
localparam CMD_READ            = 4'b0101;
localparam CMD_WRITE           = 4'b0100;
localparam CMD_BURST_TERMINATE = 4'b0110;
localparam CMD_PRECHARGE       = 4'b0010;
localparam CMD_AUTO_REFRESH    = 4'b0001;
localparam CMD_LOAD_MODE       = 4'b0000;

reg [3:0] sd_cmd;

assign sd_cs  = sd_cmd[3];
assign sd_ras = sd_cmd[2];
assign sd_cas = sd_cmd[1];
assign sd_we  = sd_cmd[0];
assign sd_dqm = sd_addr[12:11];

reg oe_latch, we_latch;

reg [2:0]  seq;
reg        seq_busy;
reg        src_cpu;
reg        src_eth;
reg [15:0] din_q;
reg [1:0]  ds_q;
reg [8:0]  col_q;
reg        flp_served;
reg        dl_served;
reg        ref_busy;
reg [2:0]  ref_cnt;
reg [9:0]  ref_due;
localparam REF_OPP   = 10'd300;
localparam REF_FORCE = 10'd480;

`ifdef TB_NO_TRISTATE
wire [15:0] sd_data_rd = sd_data_in;
`else
wire [15:0] sd_data_rd = sd_data;
`endif

reg [15:0] sd_data_q;
reg [15:0] sd_data_r;
reg        flp_cap;
always @(negedge clk_64) sd_data_q <= sd_data_rd;
always @(negedge clk_64) sd_data_r <= sd_data_q;
always @(negedge clk_64) if (flp_cap) dout <= sd_data_q;

wire req_flp   = flp_win && !flp_served;
wire req_dl    = dl_req && dl_slot && !dl_served;
wire req_cpu   = (oe || we) && !flp_win && !flp_guard && t[0]
                 && !cpu_done && (ref_due < REF_FORCE);
wire req_eth   = eth_req && !eth_ack && !(oe || we) && !flp_win && !flp_guard
                 && t[0] && (ref_due < REF_FORCE);

always @(posedge clk_64) begin
	sd_cmd <= CMD_INHIBIT;
`ifndef TB_NO_TRISTATE
	sd_data <= 16'bZZZZZZZZZZZZZZZZ;
`endif
	flp_cap <= seq_busy && (seq == STATE_READ - 3'd1) && !src_cpu && !src_eth && oe_latch;

	if(reset != 0) begin
		seq_busy   <= 0;
		ref_busy   <= 0;
		ref_due    <= 0;
		cpu_done   <= 0;
		flp_served <= 0;
		dl_served  <= 0;
		dl_ack     <= 0;
		eth_ack    <= 0;
		src_eth    <= 0;
		if(t == STATE_CMD_START) begin

			if(reset == 64) begin
				sd_cmd <= CMD_PRECHARGE;
				sd_addr[10] <= 1'b1;
			end

			if(reset >= 28 && reset <= 56 && reset[1:0] == 2'b00)
				sd_cmd <= CMD_AUTO_REFRESH;

			if(reset == 2) begin
				sd_cmd <= CMD_LOAD_MODE;
				sd_addr <= MODE;
			end

		end
	end else begin

		if (!(oe || we)) cpu_done <= 0;
		if (!flp_win)    flp_served <= 0;
		if (!dl_req)   begin dl_served <= 0; dl_ack <= 0; end
		if (!eth_req)    eth_ack <= 0;
		if (ref_due != 10'h3FF) ref_due <= ref_due + 10'd1;

		if (seq_busy) begin
			seq <= seq + 3'd1;
			if (seq == STATE_CMD_CONT) begin
				sd_cmd <= we_latch ? CMD_WRITE : CMD_READ;
				if (we_latch) sd_data <= din_q;
				sd_addr <= { we_latch ? ~ds_q : 2'b00, 2'b10, col_q };
			end
`ifdef SDRAM_NO_DONE_LEVEL_FIX
			if (seq == STATE_CMD_CONT + 3'd1 && src_cpu && oe_latch) cpu_done <= 1;
`else
			if (seq == STATE_CMD_CONT + 3'd1 && src_cpu && oe_latch && oe) cpu_done <= 1;
`endif
			if (seq == STATE_READ) begin
				if (src_cpu) begin
					if (oe_latch) cpu_dout <= sd_data_r;
				end else if (src_eth) begin
					if (oe_latch && eth_req) begin
						eth_dout <= sd_data_r;
						eth_ack  <= 1;
					end
				end
			end
			if (seq == 3'd7) seq_busy <= 0;
		end else if (ref_busy) begin
			ref_cnt <= ref_cnt + 3'd1;
			if (ref_cnt == 3'd4) ref_busy <= 0;
		end else if (req_flp || req_dl || req_cpu || req_eth) begin
			sd_cmd  <= CMD_ACTIVE;
			sd_addr <= req_flp ? { 1'b0, flp_addr[19:8] } :
			           req_dl  ? { 1'b0, dl_addr[19:8]  } :
			           req_cpu ? { 1'b0, addr[19:8] }     : { 1'b0, eth_addr[19:8] };
			sd_ba   <= req_flp ? flp_addr[21:20]          :
			           req_dl  ? dl_addr[21:20]           :
			           req_cpu ? addr[21:20]              : eth_addr[21:20];
			din_q   <= req_dl ? dl_din : req_cpu ? din : eth_din;
			ds_q    <= req_dl ? 2'b11  : req_cpu ? ds  : 2'b11;
			col_q   <= req_flp ? { flp_addr[22], flp_addr[7:0] } :
			           req_dl  ? { dl_addr[22],  dl_addr[7:0]  } :
			           req_cpu ? { addr[22],     addr[7:0] }
			                   : { eth_addr[22], eth_addr[7:0] };
			seq      <= 3'd1;
			seq_busy <= 1;
			src_cpu  <= !req_flp && !req_dl && req_cpu;
			src_eth  <= !req_flp && !req_dl && !req_cpu && req_eth;
			we_latch <= req_flp ? 1'b0 : req_dl ? 1'b1 : req_cpu ? we : eth_we;
			oe_latch <= req_flp ? 1'b1 : req_dl ? 1'b0 : req_cpu ? oe : !eth_we;
			if (req_flp) begin
				flp_served <= 1;
			end else if (req_dl) begin
				dl_served <= 1;
				dl_ack    <= 1;
			end else if (req_cpu) begin
				if (we) cpu_done <= 1;
			end else begin
				if (eth_we) eth_ack <= 1;
			end
		end else if (ref_due >= REF_OPP && !flp_guard && !flp_win && !(dl_req && dl_slot)) begin
			sd_cmd   <= CMD_AUTO_REFRESH;
			ref_busy <= 1;
			ref_cnt  <= 0;
			ref_due  <= 0;
		end
	end
end

altddio_out
#(
	.extend_oe_disable("OFF"),
	.intended_device_family("Cyclone V"),
	.invert_output("OFF"),
	.lpm_hint("UNUSED"),
	.lpm_type("altddio_out"),
	.oe_reg("UNREGISTERED"),
	.power_up_high("OFF"),
	.width(1)
)
sdramclk_ddr
(
	.datain_h(1'b0),
	.datain_l(1'b1),
	.outclock(clk_64),
	.dataout(sd_clk),
	.aclr(1'b0),
	.aset(1'b0),
	.oe(1'b1),
	.outclocken(1'b1),
	.sclr(1'b0),
	.sset(1'b0)
);

endmodule
