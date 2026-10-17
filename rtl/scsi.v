/* verilator lint_off UNUSED */

module scsi
(
	input      clk,

	input 	  rst,
	input 	  sys_rst,
	input 	  bus_busy,
	input 	  cd_enable,
	input 	  sel,
	input 	  atn,
	output 	  bsy,

	output 	  msg,
	output 	  cd,
	output 	  io,

	output 	  req,
	input 	  ack,

	input   [7:0] din,
	input         wr_batch,
	output  [7:0] dout,

	input         img_mounted,
	input  [31:0] img_blocks,
	output [31:0] io_lba,
	output        io_rd,
	output reg 	  io_wr,
	output  [5:0] io_blk_cnt,
	input         io_ack,

	input   [7:0] sd_buff_addr,
	input   [4:0] sd_buff_addr_hi,
	input  [15:0] sd_buff_dout,
	output [15:0] sd_buff_din,
	input         sd_buff_wr,

	output        data_holdoff,

	output signed [15:0] cd_snd_l,
	output signed [15:0] cd_snd_r
);

parameter [2:0] ID = 0;

parameter CDROM = 0;

// Ported from MacLC_MiSTer rtl/scsi.v, which uses the same value; we have ~475
// M10K free, so the depth is not fit-constrained.
parameter  RING_LOG    = 5;
localparam RING_BLOCKS = 1 << RING_LOG;
localparam BUF_AW      = 8 + RING_LOG;

wire any_rst = rst | sys_rst;

localparam PHASE_IDLE        = 3'd0;
localparam PHASE_CMD_IN      = 3'd1;
localparam PHASE_DATA_OUT    = 3'd2;
localparam PHASE_DATA_IN     = 3'd3;
localparam PHASE_STATUS_OUT  = 3'd4;
localparam PHASE_MESSAGE_OUT = 3'd5;
reg [2:0]  phase;

reg sd_buff_sel;
reg [22:0] rd_hps_blk;

wire [22:0] rd_cur_blk = data_cnt[31:9];
wire [RING_LOG-1:0] rd_hps_slot = rd_hps_blk[RING_LOG-1:0];
wire [BUF_AW-1:0] hps_addr_wr = {sd_buff_addr_hi[RING_LOG-1:0] + wr_base, sd_buff_addr};
wire [BUF_AW-1:0] hps_addr = cmd_write ? hps_addr_wr : {rd_hps_slot, sd_buff_addr};
wire [BUF_AW-1:0] mac_addr = data_cnt[BUF_AW:1];

wire [7:0] buffer0_dout;
scsi_dpram #(.ADDRWIDTH(BUF_AW)) buffer0
(
	.clock(clk),

	.address_a(hps_addr),
	.data_a(sd_buff_dout[7:0]),
	.wren_a(sd_buff_wr && !ca_io_active),
	.q_a(sd_buff_din[7:0]),

	.address_b(mac_addr),
	.data_b(din),
	.wren_b(buffer0_wr),
	.q_b(buffer0_dout)
);

wire [7:0] buffer1_dout;
scsi_dpram #(.ADDRWIDTH(BUF_AW)) buffer1
(
	.clock(clk),

	.address_a(hps_addr),
	.data_a(sd_buff_dout[15:8]),
	.wren_a(sd_buff_wr && !ca_io_active),
	.q_a(sd_buff_din[15:8]),

	.address_b(mac_addr),
	.data_b(din),
	.wren_b(buffer1_wr),
	.q_b(buffer1_dout)
);

reg old_io_ack;
always @(posedge clk) begin
	old_io_ack <= io_ack;
	if (phase == PHASE_IDLE)
		sd_buff_sel <= 0;
	else
		if (old_io_ack & ~io_ack & ~ca_io_active) sd_buff_sel <= !sd_buff_sel;

	if (phase != PHASE_DATA_OUT && phase != PHASE_DATA_IN &&
	    phase != PHASE_STATUS_OUT && phase != PHASE_MESSAGE_OUT)
		rd_hps_blk <= 23'd0;
	else if (old_io_ack & ~io_ack & cmd_read & ~ca_io_active)
		rd_hps_blk <= rd_hps_blk + 23'd1;
end

reg [7:0]  status;
`define STATUS_OK 8'h00
`define STATUS_CHECK_CONDITION 8'h02

`define MSG_CMD_COMPLETE 8'h00
	
assign msg = (phase == PHASE_MESSAGE_OUT);
assign cd = (phase == PHASE_CMD_IN) || (phase == PHASE_STATUS_OUT) || (phase == PHASE_MESSAGE_OUT);
assign io = (phase == PHASE_DATA_OUT) || (phase == PHASE_STATUS_OUT) || (phase == PHASE_MESSAGE_OUT);

reg    req_wr_d = 1'b0;
always @(posedge clk) req_wr_d <= req_wr;
wire   req_wr_rise = req_wr && !req_wr_d;
wire   rd_cur_unfilled = (rd_cur_blk >= rd_hps_blk);
wire   io_busy = (phase == PHASE_DATA_OUT && cmd_read && mounted && rd_cur_unfilled) ||
                 (phase == PHASE_DATA_IN  && (req_wr_rise | io_wr | wr_pending | (io_ack & ~ca_io_active))) ||
                 (phase != PHASE_DATA_OUT && phase != PHASE_DATA_IN && (io_rd_d | req_wr_rise | io_wr | wr_pending | (io_ack & ~ca_io_active)));

wire   data_done = data_complete || (data_len == 32'd0);
wire   data_phase_complete = ((phase == PHASE_DATA_OUT) || (phase == PHASE_DATA_IN)) && data_done;

assign req = (phase != PHASE_IDLE) && !ack && !io_busy && !data_phase_complete;

assign data_holdoff = !any_rst && ((phase == PHASE_DATA_OUT) || (phase == PHASE_DATA_IN)) && io_busy;

assign bsy = (phase != PHASE_IDLE);

assign dout = (phase == PHASE_STATUS_OUT)?status:
	 (phase == PHASE_MESSAGE_OUT)?`MSG_CMD_COMPLETE:
	 (phase == PHASE_DATA_OUT)?cmd_dout:
	 8'h00;

wire [7:0] cmd_dout =
		cmd_read?(data_cnt[0] ? buffer1_dout : buffer0_dout):
		cmd_inquiry?inquiry_dout:
		cmd_read_capacity?read_capacity_dout:
		cmd_mode_sense?mode_sense_dout:
		cmd_request_sense?request_sense_dout:
		cmd_cd_toc?cd_toc_dout:
		(cmd_cd_t43f2 || cmd_cd_t43f1)?cd_toc2_dout:
		cmd_cd_toc43?cd_toc43_dout:
		cmd_cd_subq?cd_subq_dout:
		cmd_cd_subq43?cd_subq43_dout:
		cmd_cd_astat?cd_astat_dout:
		cmd_cd_hdr?cd_hdr_byte(data_cnt, cd_hdr_addr_r):
		8'h00;

wire [7:0] request_sense_dout =
		(data_cnt == 32'd0 )?8'h70:
		(data_cnt == 32'd2 )?{4'd0, sense_key}:
		(data_cnt == 32'd7 )?8'h0a:
		(data_cnt == 32'd12)?sense_asc:
		8'h00;

// CDROM INQUIRY: a SONY CDU-8004, byte-exact from MAME's
// nscsi_cdrom_apple_device (data taken from an AppleCD 150 ROM). This is not a
function [7:0] cd_inquiry_byte;
	input [31:0] cnt;
	begin
		cd_inquiry_byte =
			(cnt == 32'd0 )?8'h05:
			(cnt == 32'd1 )?8'h80:
			(cnt == 32'd2 )?8'h02:
			(cnt == 32'd3 )?8'h02:
			(cnt == 32'd4 )?8'h31:
			(cnt == 32'd8 )?"S":(cnt == 32'd9 )?"O":
			(cnt == 32'd10)?"N":(cnt == 32'd11)?"Y":
			((cnt >= 32'd12) && (cnt <= 32'd15))?" ":
			(cnt == 32'd16)?"C":(cnt == 32'd17)?"D":
			(cnt == 32'd18)?"-":(cnt == 32'd19)?"R":
			(cnt == 32'd20)?"O":(cnt == 32'd21)?"M":
			(cnt == 32'd22)?" ":(cnt == 32'd23)?"C":
			(cnt == 32'd24)?"D":(cnt == 32'd25)?"U":
			(cnt == 32'd26)?"-":(cnt == 32'd27)?"8":
			(cnt == 32'd28)?"0":(cnt == 32'd29)?"0":
			(cnt == 32'd30)?"4":(cnt == 32'd31)?" ":
			(cnt == 32'd32)?"1":(cnt == 32'd33)?".":
			(cnt == 32'd34)?"9":(cnt == 32'd35)?"a":
			(cnt == 32'd39)?8'hd0:(cnt == 32'd40)?8'h90:
			(cnt == 32'd41)?8'h27:(cnt == 32'd42)?8'h3e:
			(cnt == 32'd43)?8'h01:(cnt == 32'd44)?8'h04:
			(cnt == 32'd45)?8'h91:(cnt == 32'd47)?8'h18:
			(cnt == 32'd48)?8'h06:(cnt == 32'd49)?8'hf0:
			(cnt == 32'd50)?8'hfe:
			8'h00;
	end
endfunction

wire [7:0] inquiry_dout = (CDROM != 0) ? cd_inquiry_byte(data_cnt) : hd_inquiry_dout;
wire [7:0] hd_inquiry_dout =
		(data_cnt == 32'd4 )?8'd32:

		(data_cnt == 32'd8 )?" ":(data_cnt == 32'd9 )?"S":
		(data_cnt == 32'd10)?"E":(data_cnt == 32'd11)?"A":
		(data_cnt == 32'd12)?"G":(data_cnt == 32'd13)?"A":
		(data_cnt == 32'd14)?"T":(data_cnt == 32'd15)?"E":
		(data_cnt == 32'd16)?" ":(data_cnt == 32'd17)?" ":
		(data_cnt == 32'd18)?" ":(data_cnt == 32'd19)?" ":
		(data_cnt == 32'd20)?" ":(data_cnt == 32'd21)?" ":
		(data_cnt == 32'd22)?" ":(data_cnt == 32'd23)?" ":
		(data_cnt == 32'd24)?" ":(data_cnt == 32'd25)?" ":

		(data_cnt == 32'd26)?"S":(data_cnt == 32'd27)?"T":
		(data_cnt == 32'd28)?"2":(data_cnt == 32'd29)?"2":
		(data_cnt == 32'd30)?"5":(data_cnt == 32'd31)?"N" + {5'd0, ID}:
		8'h00;

reg [31:0] capacity = 32'd0;
reg        mounted = 0;
always @(posedge clk) begin
	if (img_mounted) begin
		if (|img_blocks) begin
			capacity <= (CDROM != 0) ? ({2'b00, img_blocks[31:2]} - 1'd1)
			                         : (img_blocks - 1'd1);
			if (!mounted) $display("Image mounted on target %d, size: %d", ID, img_blocks);
			mounted <= 1;
		end else
			mounted <= 0;
	end else if ((CDROM != 0) && cd_eject_pulse)
		mounted <= 0;
end

wire [7:0] read_capacity_dout =
		(data_cnt == 32'd0 )?capacity[31:24]:
		(data_cnt == 32'd1 )?capacity[23:16]:
		(data_cnt == 32'd2 )?capacity[15:8]:
		(data_cnt == 32'd3 )?capacity[7:0]:
		(data_cnt == 32'd6 )?((CDROM != 0)?8'h08:8'd2):
		8'h00;

// block length 0x000800 = 2048. A page 0x30 request additionally appends the
// 24-byte "magic Apple page" (0x30, 0x00, "APPLE COMPUTER, INC   "), byte-exact
// from MAME's apple_magic, which some Apple drivers probe even on CD drives.
function [7:0] cd_mode_sense_byte;
	input [31:0] cnt;
	input [5:0]  page;
	input [31:0] cap;
	begin
		cd_mode_sense_byte =
			(cnt == 32'd0 )?((page == 6'h30) ? 8'd35 :
			                 (page == 6'h0E) ? 8'd27 :
			                 (page == 6'h2A) ? 8'd37 : 8'd11):
			(cnt == 32'd2 )?8'h80:
			(cnt == 32'd3 )?8'd8:
			(cnt == 32'd5 )?cap[23:16]:
			(cnt == 32'd6 )?cap[15:8]:
			(cnt == 32'd7 )?cap[7:0]:
			(cnt == 32'd10)?8'h08:
			(page == 6'h30)?(
			   (cnt == 32'd12)?8'h30:
			   (cnt == 32'd14)?"A":(cnt == 32'd15)?"P":
			   (cnt == 32'd16)?"P":(cnt == 32'd17)?"L":
			   (cnt == 32'd18)?"E":(cnt == 32'd19)?" ":
			   (cnt == 32'd20)?"C":(cnt == 32'd21)?"O":
			   (cnt == 32'd22)?"M":(cnt == 32'd23)?"P":
			   (cnt == 32'd24)?"U":(cnt == 32'd25)?"T":
			   (cnt == 32'd26)?"E":(cnt == 32'd27)?"R":
			   (cnt == 32'd28)?",":(cnt == 32'd29)?" ":
			   (cnt == 32'd30)?"I":(cnt == 32'd31)?"N":
			   (cnt == 32'd32)?"C":
			   ((cnt >= 32'd33) && (cnt <= 32'd35))?" ":8'h00):
			(page == 6'h0E)?(
			   (cnt == 32'd12)?8'h0E:
			   (cnt == 32'd13)?8'h0E:
			   (cnt == 32'd14)?8'h04:
			   (cnt == 32'd18)?8'd75:
			   (cnt == 32'd19)?8'd75:
			   (cnt == 32'd20)?8'h01:(cnt == 32'd21)?8'hff:
			   (cnt == 32'd22)?8'h02:(cnt == 32'd23)?8'hff:
			   8'h00):
			(page == 6'h2A)?(
			   (cnt == 32'd12)?8'h2A:
			   (cnt == 32'd13)?8'h18:
			   (cnt == 32'd16)?8'h71:
			   (cnt == 32'd18)?8'h28:
			   (cnt == 32'd19)?8'h03:
			   (cnt == 32'd22)?8'h01:
			   8'h00):
			8'h00;
	end
endfunction

wire [7:0] mode_sense_dout =
		(CDROM == 0) ? hd_mode_sense_dout :
		cd_mode_sense_byte(data_cnt, cd_page_r, capacity);
wire [7:0] hd_mode_sense_dout =
		(data_cnt == 32'd3 )?8'd8:
		(data_cnt == 32'd5 )?capacity[23:16]:
		(data_cnt == 32'd6 )?capacity[15:8]:
		(data_cnt == 32'd7 )?capacity[7:0]:
		(data_cnt == 32'd10 )?8'd2:
		8'h00;

reg [1:0]  c1_op_r        = 2'b00;
reg [7:0]  c1_trk_r       = 8'd0;
reg [7:0]  t43_start_r    = 8'd0;
reg [7:0]  t43_fmt_r      = 8'd0;
reg [5:0]  cd_page_r      = 6'd0;
reg        cd_astat_vol_r = 1'b0;
reg [31:0] cd_alloc10_r   = 32'd0;
reg [31:0] cd_hdr_addr_r  = 32'd0;

localparam [7:0] CD_AST_STOPPED = 8'h13;

function [7:0] cd_bin2bcd;
	input [7:0] v;
	reg [3:0] tens;
	reg [3:0] units;
	begin
		tens  = (v >= 8'd90) ? 4'd9 : (v >= 8'd80) ? 4'd8 :
		        (v >= 8'd70) ? 4'd7 : (v >= 8'd60) ? 4'd6 :
		        (v >= 8'd50) ? 4'd5 : (v >= 8'd40) ? 4'd4 :
		        (v >= 8'd30) ? 4'd3 : (v >= 8'd20) ? 4'd2 :
		        (v >= 8'd10) ? 4'd1 : 4'd0;
		units = v - ({4'd0, tens} * 8'd10);
		cd_bin2bcd = {tens, units};
	end
endfunction

function [7:0] cd_subq_byte;
	input [31:0] cnt;
	input [7:0]  trk;
	input [7:0]  rm, rs, rf;
	input [7:0]  am, as_, af;
	begin
		cd_subq_byte = (cnt == 32'd1) ? cd_bin2bcd(trk) :
		               (cnt == 32'd2) ? 8'h01 :
		               (cnt == 32'd3) ? cd_bin2bcd(rm) :
		               (cnt == 32'd4) ? cd_bin2bcd(rs) :
		               (cnt == 32'd5) ? cd_bin2bcd(rf) :
		               (cnt == 32'd6) ? cd_bin2bcd(am) :
		               (cnt == 32'd7) ? cd_bin2bcd(as_) :
		               (cnt == 32'd8) ? cd_bin2bcd(af) : 8'h00;
	end
endfunction

function [7:0] cd_subq43_byte;
	input [31:0] cnt;
	input [7:0]  ast;
	input [7:0]  ctrl, trk;
	input [7:0]  am, as_, af;
	input [7:0]  rm, rs, rf;
	begin
		cd_subq43_byte =
			(cnt == 32'd1 )?ast:
			(cnt == 32'd3 )?8'd12:
			(cnt == 32'd4 )?8'h01:
			(cnt == 32'd5 )?ctrl:
			(cnt == 32'd6 )?trk:
			(cnt == 32'd7 )?8'h01:
			(cnt == 32'd9 )?am:
			(cnt == 32'd10)?as_:
			(cnt == 32'd11)?af:
			(cnt == 32'd13)?rm:
			(cnt == 32'd14)?rs:
			(cnt == 32'd15)?rf:
			8'h00;
	end
endfunction

function [7:0] cd_astat_byte;
	input [31:0] cnt;
	input        vol_form;
	input [7:0]  ast_raw;
	input [7:0]  ctrl;
	input [7:0]  am, as_, af;
	begin
		if (vol_form)
			cd_astat_byte = ((cnt == 32'd4) || (cnt == 32'd5)) ? 8'hff : 8'h00;
		else
			cd_astat_byte = (cnt == 32'd0) ? ast_raw :
			                (cnt == 32'd2) ? ctrl :
			                (cnt == 32'd3) ? cd_bin2bcd(am) :
			                (cnt == 32'd4) ? cd_bin2bcd(as_) :
			                (cnt == 32'd5) ? cd_bin2bcd(af) : 8'h00;
	end
endfunction

function [7:0] cd_hdr_byte;
	input [31:0] cnt;
	input [31:0] addr;
	begin
		cd_hdr_byte = (cnt == 32'd0) ? 8'h01 :
		              (cnt == 32'd4) ? addr[31:24] :
		              (cnt == 32'd5) ? addr[23:16] :
		              (cnt == 32'd6) ? addr[15:8]  :
		              (cnt == 32'd7) ? addr[7:0]   : 8'h00;
	end
endfunction

reg [3:0]  cmd_cnt;
reg [7:0]  cmd [9:0];

assign io_lba = ca_io_active ? ca_io_lba : lba;

wire [22:0] rd_blk_total  = {7'd0, tlen};
wire        rd_blk_remain = (rd_hps_blk < rd_blk_total);
wire        rd_ring_space = ((rd_hps_blk - rd_cur_blk) < RING_BLOCKS);
wire req_rd = (phase == PHASE_DATA_OUT) && cmd_read && (data_len != 32'd0) &&
              !data_complete && rd_blk_remain && rd_ring_space && !cmd_aborted;

wire req_wr = ((((phase == PHASE_DATA_IN) && (wr_batch ? (data_cnt[BUF_AW:0] == 0) : (data_cnt[8:0] == 0)) && (data_cnt != 0)) ||
                ((phase == PHASE_STATUS_OUT) && data_in_seen))
               && cmd_write && (data_len != 32'd0) && !cmd_aborted);

reg data_in_seen;
always @(posedge clk) begin
	if((phase == PHASE_IDLE) || (phase == PHASE_CMD_IN)) data_in_seen <= 0;
	else if(phase == PHASE_DATA_IN) data_in_seen <= 1;
end

reg wr_pending;

reg io_rd_d;
assign io_rd = io_rd_d | ca_io_rd_w;

reg [RING_LOG-1:0] wr_blks_m1 = 0;
reg [RING_LOG-1:0] wr_base = 0;
assign io_blk_cnt = cmd_write ? {{(6-RING_LOG){1'b0}}, wr_blks_m1} : 6'd0;

always @(posedge clk) begin
	reg old_wr;
	reg rd_busy;

	if(any_rst || wdog_abort) begin
		io_rd_d    <= 1'b0;
		io_wr      <= 1'b0;
		wr_pending <= 1'b0;
		old_wr     <= 1'b0;
		rd_busy    <= 1'b0;
	end else begin
		old_wr <= req_wr;
		if(~old_wr & req_wr) wr_pending <= 1;

		if(io_ack) io_rd_d <= 1'b0;
		else if(req_rd && !io_rd && !rd_busy) begin io_rd_d <= 1'b1; rd_busy <= 1'b1; end
		if(old_io_ack & ~io_ack) rd_busy <= 1'b0;

		if(io_ack) io_wr <= 1'b0;
		else if(wr_pending && !io_wr) begin
			io_wr <= 1'b1; wr_pending <= 0;
			wr_blks_m1 <= wr_batch ? data_cnt[BUF_AW:9] - 1'd1 : {RING_LOG{1'b0}};
			wr_base    <= wr_batch ? {RING_LOG{1'b0}} : data_cnt[BUF_AW:9] - 1'd1;
		end
	end
end

reg  stb_ack;
reg  stb_adv;
always @(posedge clk) begin
	reg old_ack;
	
	old_ack <= ack;
	stb_ack <= (~old_ack & ack);
	stb_adv <= (old_ack & ~ack);
end

reg buffer0_wr, buffer1_wr;

always @(posedge clk) begin
	buffer0_wr <= 0;
	buffer1_wr <= 0;
	if(stb_ack) begin
		if(phase == PHASE_CMD_IN)  cmd[cmd_cnt] <= din;
		if(phase == PHASE_DATA_IN) begin
			buffer0_wr <= ~data_cnt[0];
			buffer1_wr <=  data_cnt[0];
		end
	end
end

always @(posedge clk) begin
	if(phase == PHASE_IDLE) cmd_cnt <= 4'd0;
	else if(stb_adv && (phase == PHASE_CMD_IN) && (cmd_cnt != 15)) cmd_cnt <= cmd_cnt + 4'd1;
end

reg [31:0] data_cnt;
reg        data_complete;

wire [31:0] alloc_len = (tlen == 16'd256) ? 32'd0 : {16'd0, tlen};
wire [31:0] sense_len = (tlen == 16'd256) ? 32'd4 : {16'd0, tlen};
localparam [31:0] INQUIRY_LEN = (CDROM != 0) ? 32'd54 : 32'd36;

wire [31:0] data_len =
		 cmd_read_capacity?32'd8:
		 cmd_read?{ 7'd0, tlen, 9'd0 }:
		 cmd_write?{ 7'd0, tlen, 9'd0 }:
		 cmd_inquiry?((alloc_len < INQUIRY_LEN) ? alloc_len : INQUIRY_LEN):
		 cmd_request_sense?((sense_len < 32'd18) ? sense_len : 32'd18):
		 cmd_cd_toc?cd_alloc10_r:
		 cmd_cd_toc43?cd_alloc10_r:
		 cmd_cd_subq43?cd_alloc10_r:
		 cmd_cd_subq?cd_alloc10_r:
		 cmd_cd_astat?cd_alloc10_r:
		 cmd_cd_hdr?cd_alloc10_r:
		 cmd_cd_actl?cd_alloc10_r:
		 ((CDROM != 0) && cmd_mode_select)?alloc_len:
		 ((CDROM != 0) && cmd_mode_sense)?alloc_len:
		 { 16'd0, tlen };

always @(posedge clk) begin
	if((phase != PHASE_DATA_OUT) && (phase != PHASE_DATA_IN) && (phase != PHASE_STATUS_OUT) && (phase != PHASE_MESSAGE_OUT)) begin
		data_cnt <= 0;
		data_complete <= 0;
	end else begin	
		if(stb_adv)begin	
			if(!data_complete) data_cnt <= data_cnt + 1'd1;
			data_complete <= (data_len - 1'd1) == data_cnt;
		end
	end
end

reg status_sent;
always @(posedge clk) begin
	if(phase != PHASE_STATUS_OUT) status_sent <= 0;
	else if(stb_adv) status_sent <= 1;
end

reg message_sent;
always @(posedge clk) begin
	if(phase != PHASE_MESSAGE_OUT) message_sent <= 0;
	else if(stb_adv) message_sent <= 1;
end

reg status_done;
always @(posedge clk) begin
	if(phase == PHASE_IDLE) status_done <= 0;
	else if((phase == PHASE_STATUS_OUT) && stb_adv) status_done <= 1;
end

reg cmd_aborted;
always @(posedge clk) begin
	if(any_rst || (phase == PHASE_IDLE)) cmd_aborted <= 0;
	else if(wdog_abort) cmd_aborted <= 1;
end

wire [7:0] op_code = cmd[0];
wire [2:0] cmd_group = op_code[7:5];

wire       cmd_cpl = cmd6_cpl || cmd10_cpl || cmd12_cpl;
wire       cmd6_cpl = (cmd_group == 3'b000) && (cmd_cnt == 6);
wire       cmd_apple_cd_op = (CDROM != 0) && (op_code[7:4] == 4'hc);
wire       cmd10_cpl = (((cmd_group == 3'b010) || (cmd_group == 3'b001)) && (cmd_cnt == 10))
                       || (cmd_apple_cd_op && (cmd_cnt == 10));
wire       cmd12_cpl = (cmd_group == 3'b101) && (cmd_cnt == 12);

// https://en.wikipedia.org/wiki/SCSI_command
wire       cmd_read = cmd_read6 || cmd_read10;
wire       cmd_read6 = (op_code == 8'h08);
wire       cmd_read10 = (op_code == 8'h28);
wire       cmd_write = cmd_write6 || cmd_write10;
wire       cmd_write6 = (op_code == 8'h0a);
wire       cmd_write10 = (op_code == 8'h2a);
wire       cmd_inquiry = (op_code == 8'h12);
wire       cmd_format = (op_code == 8'h04);
wire       cmd_mode_select = (op_code == 8'h15);
wire       cmd_mode_sense = (op_code == 8'h1a);
wire       cmd_test_unit_ready = (op_code == 8'h00);
wire       cmd_read_capacity = (op_code == 8'h25);
wire       cmd_read_buffer = (op_code == 8'h3b);
wire       cmd_write_buffer = (op_code == 8'h3c);
wire       cmd_verify6 = (op_code == 8'h13);
wire       cmd_verify10 = (op_code == 8'h2f);
wire       cmd_request_sense = (op_code == 8'h03);

wire       cmd_cd_eject     = (CDROM != 0) && (op_code == 8'hc0);
wire       cmd_cd_toc       = (CDROM != 0) && (op_code == 8'hc1);
wire       cmd_cd_subq      = (CDROM != 0) && (op_code == 8'hc2);
wire       cmd_cd_astat     = (CDROM != 0) && (op_code == 8'hcc);
wire       cmd_cd_actl      = (CDROM != 0) && (op_code == 8'hce);
wire       cmd_cd_toc43     = (CDROM != 0) && (op_code == 8'h43);
wire       cmd_cd_t43f2     = cmd_cd_toc43 && (t43_fmt_r == 8'h80);
wire       cmd_cd_t43f1     = cmd_cd_toc43 && (t43_fmt_r == 8'h40);
wire       cmd_cd_subq43    = (CDROM != 0) && (op_code == 8'h42);
wire       cmd_cd_hdr       = (CDROM != 0) && (op_code == 8'h44);
wire       cmd_cd_prevent   = (CDROM != 0) && (op_code == 8'h1e);
wire       cmd_cd_startstop = (CDROM != 0) && (op_code == 8'h1b);
wire       cmd_cd_setspeed  = (CDROM != 0) && (op_code == 8'hbb);
wire       cmd_cd_audio_nop = (CDROM != 0) && ((op_code == 8'hc8) || (op_code == 8'hc9) ||
                                               (op_code == 8'hca) || (op_code == 8'hcb) ||
                                               (op_code == 8'hcd) ||
                                               (op_code == 8'h47) || (op_code == 8'h48) ||
                                               (op_code == 8'h4b) || (op_code == 8'h4e) ||
                                               (op_code == 8'h01) ||
                                               (op_code == 8'h0b) || (op_code == 8'h2b) ||
                                               (op_code == 8'h45) || (op_code == 8'ha5));
wire       cmd_cd_eject_any = cmd_cd_eject ||
                              (cmd_cd_startstop && cmd[4][1] && !cmd[4][0]);

wire  cmd_ok_hd = cmd_read || cmd_write || cmd_inquiry || cmd_test_unit_ready ||
		  cmd_read_capacity || cmd_mode_select || cmd_format || cmd_mode_sense ||
		  cmd_read_buffer || cmd_write_buffer || cmd_verify6 || cmd_verify10 ||
		  cmd_request_sense;

wire  cmd_ok_cd = cmd_read || cmd_inquiry || cmd_test_unit_ready ||
		  cmd_read_capacity || cmd_mode_select || cmd_mode_sense ||
		  cmd_request_sense || cmd_cd_eject || cmd_cd_toc || cmd_cd_subq ||
		  cmd_cd_astat || cmd_cd_actl || cmd_cd_audio_nop ||
		  cmd_cd_toc43 || cmd_cd_subq43 || cmd_cd_hdr ||
		  cmd_cd_prevent || cmd_cd_startstop || cmd_cd_setspeed;

// Our answer to a command against an empty drive: SK_NOT_READY + the vendor
// ASC 0xB0, from MAME's return_no_cd. MacOS demonstrably BRANCHES on this
wire [3:0] cd_nomedia_key = 4'h2;
wire [7:0] cd_nomedia_asc = 8'hb0;
wire  cmd_ok = (CDROM != 0) ? cmd_ok_cd : cmd_ok_hd;

wire  cd_needs_media = cmd_test_unit_ready || cmd_read || cmd_read_capacity ||
		  cmd_cd_toc || cmd_cd_subq || cmd_cd_astat || cmd_cd_actl ||
		  cmd_cd_toc43 || cmd_cd_subq43 || cmd_cd_hdr || cmd_cd_audio_nop;
wire  cd_no_media = (CDROM != 0) && (!mounted || !ca_toc_ready) && cd_needs_media;

reg   cd_unit_attn = 1'b0;
wire  cd_unit_attn_rej = (CDROM != 0) && cd_unit_attn
                         && !cmd_inquiry && !cmd_request_sense;
always @(posedge clk) begin
	if (any_rst)                          cd_unit_attn <= (CDROM != 0);
	else if (new_cmd && cd_unit_attn_rej) cd_unit_attn <= 1'b0;
end

reg  [SPINUP_LOG:0] cd_spinup = 0;
wire cd_spinning_up = (CDROM != 0) && !cd_spinup[SPINUP_LOG];
wire cd_spinup_rej  = cd_spinning_up && cd_needs_media;
always @(posedge clk) begin
	if (any_rst)                     cd_spinup <= 0;
	else if (!cd_spinup[SPINUP_LOG]) cd_spinup <= cd_spinup + 1'd1;
end

wire  cd_hdr_msf_rej = cmd_cd_hdr && cmd[1][1];

wire [31:0] cdb_lba  = cmd6_cpl ? {11'd0, lba6} : lba10;
wire [16:0] cdb_blks = cmd6_cpl ? {8'd0, tlen6} : {1'b0, tlen10};
wire [32:0] cdb_end  = {1'b0, cdb_lba} + {16'd0, cdb_blks};
wire  lba_out_of_range = (cmd_read || cmd_write) && mounted && (cdb_blks != 0) &&
                         (cdb_end > ({1'b0, capacity} + 33'd1));

reg [3:0] sense_key = 4'd0;
reg [7:0] sense_asc = 8'd0;
reg       cd_prevent = 1'b0;

reg  cmd_cpl_d = 1'b0;
always @(posedge clk) cmd_cpl_d <= (phase == PHASE_CMD_IN) && cmd_cpl;
wire new_cmd = (phase == PHASE_CMD_IN) && cmd_cpl && !cmd_cpl_d;

wire cd_eject_pulse = new_cmd && cmd_cd_eject_any && !cd_prevent;

wire frontier_breach = stb_ack && (phase == PHASE_DATA_OUT) && cmd_read
                       && mounted && rd_cur_unfilled && !data_phase_complete;

reg frontier_violated = 1'b0;
always @(posedge clk) begin
	if (any_rst || new_cmd)   frontier_violated <= 1'b0;
	else if (frontier_breach) frontier_violated <= 1'b1;
end

always @(posedge clk) begin
	if (any_rst) begin
		sense_key  <= 4'd0;
		sense_asc  <= 8'd0;
		cd_prevent <= 1'b0;
	end else if (wdog_abort) begin
		sense_key <= 4'hB;
		sense_asc <= op_code;
	end else if (frontier_breach) begin
		sense_key <= 4'hB;
		sense_asc <= 8'h4b;
	end else if (new_cmd) begin
		if (cd_unit_attn_rej) begin
			sense_key <= 4'h6;
			sense_asc <= 8'h29;
		end else if (cd_spinup_rej) begin
			sense_key <= 4'h2;
			sense_asc <= 8'h04;
		end else if (!cmd_ok) begin
			sense_key <= 4'h5;
			sense_asc <= 8'h20;
		end else if (cd_no_media) begin
			sense_key <= cd_nomedia_key;
			sense_asc <= cd_nomedia_asc;
		end else if (lba_out_of_range) begin
			sense_key <= 4'h5;
			sense_asc <= 8'h21;
		end else if (cd_hdr_msf_rej) begin
			sense_key <= 4'h5;
			sense_asc <= 8'h24;
		end else if (cmd_cd_eject_any) begin
			if (cd_prevent) begin
				sense_key <= 4'h5;
				sense_asc <= 8'h80;
			end else begin
				sense_key <= 4'h2;
				sense_asc <= 8'h3a;
			end
		end else if (cmd_cd_prevent) begin
			cd_prevent <= cmd[4][0];
			sense_key  <= 4'd0;
			sense_asc  <= 8'd0;
		end else if (!cmd_request_sense) begin
			sense_key <= 4'd0;
			sense_asc <= 8'd0;
		end
	end
end

reg [31:0] lba;
reg [15:0] tlen;

always @(posedge clk) begin
	if (old_io_ack & ~io_ack) lba <= lba + (cmd_write ? {{(32-RING_LOG){1'b0}}, wr_blks_m1} + 32'd1 : 32'd1);
	if(cmd_cpl && (phase == PHASE_CMD_IN)) begin
		if ((CDROM != 0) && cmd_read) begin
			lba  <= (cmd6_cpl?{11'd0, lba6}:lba10) << 2;
			tlen <= (cmd6_cpl?{7'd0, tlen6}:tlen10) << 2;
		end else begin
			lba <= cmd6_cpl?{11'd0, lba6}:lba10;
			tlen <= cmd6_cpl?{7'd0, tlen6}:tlen10;
		end

		c1_op_r        <= cmd[9][7:6];
		c1_trk_r       <= cmd[5];
		t43_start_r    <= cmd[6];
		t43_fmt_r      <= cmd[9];
		cd_page_r      <= cmd[2][5:0];
		cd_astat_vol_r <= (cmd[3] == 8'h01);
		cd_alloc10_r   <= {16'd0, cmd[7], cmd[8]};
		cd_hdr_addr_r  <= {cmd[2], cmd[3], cmd[4], cmd[5]};
	end
end
   
wire [7:0] cmd1 = cmd[1];
wire [20:0] lba6 = { cmd1[4:0], cmd[2], cmd[3] };
wire [31:0] lba10 = { cmd[2], cmd[3], cmd[4], cmd[5] };

wire [8:0]  tlen6 = (cmd[4] == 0)?9'd256:{1'b0,cmd[4]};
wire [15:0] tlen10 = { cmd[7], cmd[8] };

parameter SPINUP_LOG = 27;
parameter WDOG_LOG = 22;

parameter IOWDOG_LOG = 24;
reg [IOWDOG_LOG-1:0] iowdog = 0;
wire iowdog_expired = &iowdog;
wire iostall_abort  = iowdog_expired;
always @(posedge clk) begin
	if (any_rst || !io_busy || (phase == PHASE_IDLE) || iostall_abort)
		iowdog <= 0;
	else
		iowdog <= iowdog + 1'd1;
end
reg [WDOG_LOG-1:0] wdog = 0;
wire wdog_expired = &wdog;
wire wdog_abort   = (wdog_expired && (phase != PHASE_IDLE)) || iostall_abort;

always @(posedge clk) begin
	if (any_rst || (phase == PHASE_IDLE) || stb_ack || stb_adv || io_busy || wdog_abort)
		wdog <= 0;
	else if (!wdog_expired)
		wdog <= wdog + 1'd1;
end

always @(posedge clk) begin
	ca_cmd_stb <= 1'b0; ca_read_stb <= 1'b0; ca_eject_stb <= 1'b0;
	if(any_rst) begin
		phase <= PHASE_IDLE;
	end else if (wdog_abort) begin
		if (status_done || cmd_aborted)
			phase <= PHASE_IDLE;
		else begin
			status <= `STATUS_CHECK_CONDITION;
			phase  <= PHASE_STATUS_OUT;
		end
	end else begin
		if(phase == PHASE_IDLE) begin
			if(sel && din[ID] && ((CDROM != 0) ? cd_enable : mounted) && !bus_busy)
				phase <= PHASE_CMD_IN;
		end

		else if(phase == PHASE_CMD_IN) begin
			if(cmd_cpl) begin
				$display("New command on target %d: %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x", ID, cmd[0], cmd[1], cmd[2], cmd[3], cmd[4], cmd[5], cmd[6], cmd[7], cmd[8], cmd[9]);
				if(cmd_ok && !cd_no_media && !cd_audio_read_rej && !cd_hdr_msf_rej && !lba_out_of_range && !cd_unit_attn_rej && !cd_spinup_rej) begin
					status <= (cmd_cd_eject_any && cd_prevent) ? `STATUS_CHECK_CONDITION : `STATUS_OK;

					ca_cmd_stb   <= cmd_cd_audio_nop;
					ca_read_stb  <= cmd_read && (CDROM != 0);
					ca_eject_stb <= cmd_cd_eject_any && !cd_prevent;

					if(cmd_read || cmd_inquiry || cmd_read_capacity || cmd_mode_sense || cmd_read_buffer || cmd_request_sense ||
					   cmd_cd_toc || cmd_cd_toc43 || cmd_cd_subq || cmd_cd_subq43 || cmd_cd_astat || cmd_cd_hdr) phase <= PHASE_DATA_OUT;
					else if(cmd_write || cmd_mode_select || cmd_write_buffer || cmd_cd_actl) phase <= PHASE_DATA_IN;
					else phase <= PHASE_STATUS_OUT;
				end else begin
					status <= `STATUS_CHECK_CONDITION;
					phase <= PHASE_STATUS_OUT;
				end
			end
		end

		else if(phase == PHASE_DATA_OUT) begin
			if(data_done) begin
				if(frontier_violated) status <= `STATUS_CHECK_CONDITION;
				phase <= PHASE_STATUS_OUT;
			end
		end

		else if(phase == PHASE_DATA_IN) begin
			if(data_done) phase <= PHASE_STATUS_OUT;
		end

		else if(phase == PHASE_STATUS_OUT) begin
			if(status_sent) phase <= PHASE_MESSAGE_OUT;
		end

		else if(phase == PHASE_MESSAGE_OUT) begin
			if(message_sent) phase <= PHASE_IDLE;
		end
		
		else
			phase <= PHASE_IDLE;
	end
end
   
wire        ca_io_active, ca_io_rd_w;
wire [31:0] ca_io_lba;
wire  [7:0] ca_ast_code, ca_cur_ctrl, ca_cur_trk;
wire  [7:0] ca_abs_m, ca_abs_s, ca_abs_f, ca_rel_m, ca_rel_s, ca_rel_f;
wire  [7:0] ca_toc_q0, ca_toc_q1, ca_toc_q2, ca_toc_q3;
wire        ca_toc_ready;
wire  [7:0] ca_t43_q0, ca_t43_q1, ca_t43_q2, ca_t43_q3;
wire  [9:0] ca_t43_len;
wire  [7:0] ca_t2_q0, ca_t2_q1, ca_t2_q2, ca_t2_q3;
wire  [9:0] ca_t2_len;
wire        ca_disc_audio;

function [7:0] cd_bcd2bin;
	input [7:0] v;
	cd_bcd2bin = (v[7:4] * 8'd10) + {4'd0, v[3:0]};
endfunction

wire  [7:0] ca_toc_trk_bin = cd_bcd2bin(c1_trk_r);
wire  [8:0] ca_toc_trk_k   = (ca_toc_trk_bin == 8'd0)  ? 9'd0  :
                             (ca_toc_trk_bin >  8'd99) ? 9'd98 :
                             {1'b0, ca_toc_trk_bin} - 9'd1;
wire  [8:0] ca_toc_base    = (c1_op_r == 2'b01) ? 9'd4 :
                             (c1_op_r == 2'b10) ? (9'd8 + {ca_toc_trk_k[6:0], 2'b00}) :
                                                  9'd0;
wire  [8:0] ca_toc_raw     = ca_toc_base + data_cnt[8:0];
wire  [8:0] ca_toc_addr    = (ca_toc_raw < 9'd404) ? ca_toc_raw
                                                   : (9'd400 + {7'd0, ca_toc_raw[1:0]});
wire  [7:0] cd_toc_dout    = ca_toc_ready ? ca_toc_q0 : 8'h00;

wire  [6:0] ca_t43_nreal = (ca_t43_len >= 10'd14) ? ((ca_t43_len - 10'd14) >> 3) + 7'd1 : 7'd1;
wire  [6:0] ca_t43_soff  =
	(t43_start_r == 8'h00 || t43_start_r == 8'h01) ? 7'd0 :
	(t43_start_r == 8'hAA)                          ? ca_t43_nreal :
	(t43_start_r >  {1'b0, ca_t43_nreal})           ? ca_t43_nreal :
	                                                  t43_start_r[6:0] - 7'd1;
wire  [9:0] ca_t43_flen  = {(7'd1 + ca_t43_nreal - ca_t43_soff), 3'b000} + 10'd2;
wire  [9:0] ca_t43_tot   = ca_t43_flen + 10'd2;
wire  [8:0] ca_t43_addr  = (data_cnt < 32'd4) ? data_cnt[8:0]
                         : (9'd4 + {ca_t43_soff, 3'b000} + (data_cnt[8:0] - 9'd4));
function [7:0] t43_hdr_fix;
	input [31:0] cnt;
	input [9:0]  tot;
	input [9:0]  flen;
	input [7:0]  raw;
	t43_hdr_fix = (cnt >= {22'd0, tot}) ? 8'h00 :
	              (cnt == 32'd0) ? {6'd0, flen[9:8]} :
	              (cnt == 32'd1) ? flen[7:0] : raw;
endfunction
wire  [7:0] cd_toc43_dout = ca_toc_ready
                          ? t43_hdr_fix(data_cnt, ca_t43_tot, ca_t43_flen, ca_t43_q0)
                          : 8'h00;

wire  [8:0] ca_t2_addr = (cmd_cd_t43f1 ? 9'd496 : 9'd0) + data_cnt[8:0];
function [7:0] t2_fix;
	input [31:0] cnt;
	input [9:0]  len;
	input [7:0]  raw;
	t2_fix = (cnt >= {22'd0, len}) ? 8'h00 : raw;
endfunction
function [7:0] sess_fix;
	input [31:0] cnt;
	input [7:0]  raw;
	sess_fix = (cnt >= 32'd12) ? 8'h00 : raw;
endfunction
wire  [7:0] cd_toc2_dout = !ca_toc_ready ? 8'h00 :
                           cmd_cd_t43f1 ? sess_fix(data_cnt, ca_t2_q0)
                                        : t2_fix(data_cnt, ca_t2_len, ca_t2_q0);

wire  [7:0] ca_ast_std  = (ca_ast_code == 8'd0) ? 8'h11 :
                          (ca_ast_code == 8'd1) ? 8'h12 : CD_AST_STOPPED;

wire  [7:0] cd_subq_dout   = cd_subq_byte(data_cnt, ca_cur_trk,
                                          ca_rel_m, ca_rel_s, ca_rel_f,
                                          ca_abs_m, ca_abs_s, ca_abs_f);
wire  [7:0] cd_subq43_dout = cd_subq43_byte(data_cnt, ca_ast_std,
                                            ca_cur_ctrl, ca_cur_trk,
                                            ca_abs_m, ca_abs_s, ca_abs_f,
                                            ca_rel_m, ca_rel_s, ca_rel_f);
wire  [7:0] cd_astat_dout  = cd_astat_byte(data_cnt, cd_astat_vol_r,
                                           ca_ast_code, ca_cur_ctrl,
                                           ca_abs_m, ca_abs_s, ca_abs_f);

wire        cd_audio_read_rej = (CDROM != 0) && mounted && cmd_read && ca_disc_audio;

reg         ca_cmd_stb   = 1'b0;
reg         ca_read_stb  = 1'b0;
reg         ca_eject_stb = 1'b0;

wire  [7:0] cd_ap_ch0 = 8'h01, cd_ap_vol0 = 8'hff;
wire  [7:0] cd_ap_ch1 = 8'h02, cd_ap_vol1 = 8'hff;

wire ca_grant = (phase == PHASE_IDLE || (cmd_read && phase == PHASE_DATA_OUT))
                && !io_rd_d && !io_wr && !io_ack && mounted;

generate if (CDROM != 0) begin : g_cd_audio
	cd_audio #(.CLK_HZ(32'd32_500_000)) cd_audio_i (
		.clk(clk), .rst(sys_rst), .bus_rst(rst),
		.mounted(mounted), .img_mounted(img_mounted), .img_blocks(img_blocks),
		.cmd_stb(ca_cmd_stb), .cmd_op(cmd[0]),
		.cdb1(cmd[1]), .cdb2(cmd[2]), .cdb3(cmd[3]), .cdb4(cmd[4]),
		.cdb5(cmd[5]), .cdb6(cmd[6]), .cdb7(cmd[7]), .cdb8(cmd[8]), .cdb9(cmd[9]),
		.read_stb(ca_read_stb), .eject_stb(ca_eject_stb),
		.ap_ch0(cd_ap_ch0), .ap_vol0(cd_ap_vol0),
		.ap_ch1(cd_ap_ch1), .ap_vol1(cd_ap_vol1),
		.ch_grant(ca_grant),
		.ca_io_active(ca_io_active), .ca_io_rd(ca_io_rd_w), .ca_io_lba(ca_io_lba),
		.io_ack(io_ack),
		.sd_buff_addr(sd_buff_addr), .sd_buff_addr_hi(sd_buff_addr_hi),
		.sd_buff_dout(sd_buff_dout), .sd_buff_wr(sd_buff_wr),
		.ast_code(ca_ast_code), .cur_ctrl(ca_cur_ctrl), .cur_trk(ca_cur_trk),
		.abs_m(ca_abs_m), .abs_s(ca_abs_s), .abs_f(ca_abs_f),
		.rel_m(ca_rel_m), .rel_s(ca_rel_s), .rel_f(ca_rel_f),
		.toc_base(ca_toc_addr),
		.toc_q0(ca_toc_q0), .toc_q1(ca_toc_q1), .toc_q2(ca_toc_q2), .toc_q3(ca_toc_q3),
		.toc_ready(ca_toc_ready),
		.toc43_base(ca_t43_addr),
		.toc43_q0(ca_t43_q0), .toc43_q1(ca_t43_q1),
		.toc43_q2(ca_t43_q2), .toc43_q3(ca_t43_q3),
		.toc43_len(ca_t43_len),
		.toc2_base(ca_t2_addr),
		.toc2_q0(ca_t2_q0), .toc2_q1(ca_t2_q1),
		.toc2_q2(ca_t2_q2), .toc2_q3(ca_t2_q3),
		.toc2_len(ca_t2_len),
		.disc_audio(ca_disc_audio),
		.snd_l(cd_snd_l), .snd_r(cd_snd_r)
	);
end else begin : g_no_cd_audio
	assign ca_io_active = 1'b0;
	assign ca_io_rd_w   = 1'b0;
	assign ca_io_lba    = 32'd0;
	assign ca_ast_code  = 8'h05;
	assign ca_cur_ctrl  = 8'd0;
	assign ca_cur_trk   = 8'd0;
	assign {ca_abs_m, ca_abs_s, ca_abs_f} = 24'd0;
	assign {ca_rel_m, ca_rel_s, ca_rel_f} = 24'd0;
	assign {ca_toc_q0, ca_toc_q1, ca_toc_q2, ca_toc_q3} = 32'd0;
	assign ca_toc_ready = 1'b0;
	assign {ca_t43_q0, ca_t43_q1, ca_t43_q2, ca_t43_q3} = 32'd0;
	assign ca_t43_len   = 10'd0;
	assign {ca_t2_q0, ca_t2_q1, ca_t2_q2, ca_t2_q3} = 32'd0;
	assign ca_t2_len    = 10'd0;
	assign ca_disc_audio = 1'b0;
	assign cd_snd_l     = 16'sd0;
	assign cd_snd_r     = 16'sd0;
end
endgenerate

`ifdef VERILATOR
reg [2:0] dbg_phase_d = 3'd0;
always @(posedge clk) begin
	dbg_phase_d <= phase;
	if (phase == PHASE_STATUS_OUT && dbg_phase_d != PHASE_STATUS_OUT)
		$display("SCSI %0d end: op %02x lba %02x%02x%02x%02x len %02x%02x data_cnt %0d data_len %0d aborted %0d",
		         ID, cmd[0], cmd[2], cmd[3], cmd[4], cmd[5], cmd[7], cmd[8], data_cnt, data_len, cmd_aborted);
end
`endif

endmodule

module scsi_dpram #(parameter DATAWIDTH=8, ADDRWIDTH=9)
(
	input	                clock,

	input	[ADDRWIDTH-1:0] address_a,
	input	[DATAWIDTH-1:0] data_a,
	input	                wren_a,
	output reg [DATAWIDTH-1:0] q_a,

	input	[ADDRWIDTH-1:0] address_b,
	input	[DATAWIDTH-1:0] data_b,
	input	                wren_b,
	output reg [DATAWIDTH-1:0] q_b
);

reg [DATAWIDTH-1:0] ram[0:(1<<ADDRWIDTH)-1];

always @(posedge clock) begin
	if(wren_a) begin
		ram[address_a] <= data_a;
		q_a <= data_a;
	end else begin
		q_a <= ram[address_a];
	end
end

always @(posedge clock) begin
	if(wren_b) begin
		ram[address_b] <= data_b;
		q_b <= data_b;
	end else begin
		q_b <= ram[address_b];
	end
end

endmodule
