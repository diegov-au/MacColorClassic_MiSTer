module swim2 (
	input  wire        clk,
	input  wire        cep,
	input  wire        cen,
	input  wire        reset,

	input  wire        strobe,
	input  wire        we,
	input  wire  [2:0] reg_sel,
	input  wire  [7:0] wdata,
	output reg   [7:0] rdata,

	input  wire        hdsel,

	input  wire        insertDisk,
	input  wire        diskSides,
	input  wire        diskMFM,
	input  wire        diskHD,
	input  wire        writeProtect,
	output wire        diskEject,
	output wire        diskMotor,
	output wire        diskAct,

	output wire [21:0] dskReadAddr,
	input  wire        dskReadAck,
	input  wire  [7:0] dskReadData,

	output wire [21:0] wrSdAddr,
	output wire [15:0] wrSdData,
	output wire        wrSdReq,
	input  wire        wrSdAck,
	output wire        wrCommitDone,
	output wire [21:0] wrCommitAddr,
	output wire  [7:0] wrSdBufAddr,
	output wire [15:0] wrSdBufData,
	output wire        wrSdBufWr
);

localparam FB_MARK = 8;
localparam FB_CRC0 = 10;

reg  [7:0] mode, setup, phases, error;
reg  [7:0] param [0:3];
reg  [1:0] param_idx;
reg [15:0] fifo [0:1];
reg  [1:0] fifo_pos;
(* ramstyle = "MLAB" *) reg [15:0] stage [0:15];
reg  [3:0] stage_rd, stage_wr;
reg  [4:0] stage_cnt;
reg        mfm_synced;
reg  [4:0] anchor_sector;
reg        anchor_ok;

wire devsel   = mode[7] && mode[2:1] == 2'b01;
wire rd_arm   = mode[3] && !mode[4];
wire wr_arm   = mode[3] &&  mode[4];
wire mfm_rd   = rd_arm && !setup[2];
wire gcr_rd   = rd_arm &&  setup[2];
wire mfm_wr   = wr_arm && !setup[6];
wire gcr_wr   = wr_arm &&  setup[6];

wire  [7:0] drv_data;
wire        drv_byte;
wire  [7:0] mfm_byte;
wire  [4:0] mfm_sector;
wire        mfm_mark, mfm_crc0, mfm_stb;
wire  [7:0] drv_status;
wire        wbusy;
wire  [7:0] mfm_wr_byte;
wire        mfm_wr_mark, mfm_wr_stb;
reg   [7:0] gcr_byte;
reg         gcr_req;

floppy drive
(
	.clk(clk),
	.cep(cep),
	.cen(cen),
	._reset(!reset),

	.ca0(phases[0]),
	.ca1(phases[1]),
	.ca2(phases[2]),
	.lstrb(phases[3]),
	.SEL(hdsel),
	._enable(!devsel),

	.writeData(gcr_byte),
	.writeReq(cen && gcr_req),
	.writeMode(gcr_wr),
	.writeProtect(writeProtect),
	.writeBusy(wbusy),
	.writeUnderrun(),
	.wrSecValid(),
	.wrSecNum(),
	.wrSecAddr(),
	.wrSdAddr(wrSdAddr),
	.wrSdData(wrSdData),
	.wrSdReq(wrSdReq),
	.wrSdAck(wrSdAck),
	.wrCommitDone(wrCommitDone),
	.wrCommitAddr(wrCommitAddr),
	.wrSdBufAddr(wrSdBufAddr),
	.wrSdBufData(wrSdBufData),
	.wrSdBufWr(wrSdBufWr),

	.readData(drv_data),
	.advanceDriveHead(1'b0),
	.newByteReady(drv_byte),
	.insertDisk(insertDisk),
	.diskSides(diskSides),
	.mediaSides(1'b1),
	.diskEject(diskEject),
	.motor(diskMotor),
	.act(diskAct),

	.dskReadAddr(dskReadAddr),
	.dskReadAck(dskReadAck),
	.dskReadData(dskReadData),

	.ism_active(1'b1),
	.ism_action(mode[3]),
	.ism_sel(devsel),
	.mfm_disk(diskMFM),
	.mfm_hd(diskHD),
	.mfm_byte(mfm_byte),
	.mfm_sector(mfm_sector),
	.mfm_wr_byte(mfm_wr_byte),
	.mfm_wr_mark(mfm_wr_mark),
	.mfm_wr_stb(mfm_wr_stb),
	.mfm_wr_anchor(anchor_sector),
	.mfm_wr_anchor_ok(anchor_ok),
	.mfm_mark(mfm_mark),
	.mfm_crc0(mfm_crc0),
	.mfm_stb(mfm_stb),

	.dbg_byte_cnt(), .dbg_miss_cnt(), .dbg_disk_image_data(), .dbg_drive_track(),
	.dbg_drive_side(), .dbg_step_cnt(), .dbg_byte_stb(), .dbg_raw_byte(),
	.dbg_gcr_addr(), .dbg_media(), .dbg_strb_cnt(), .dbg_strb_en_cnt(),
	.dbg_strb_last(), .dbg_rej_step(), .dbg_status(drv_status),
	.dbg_mfm_stall_us(), .dbg_mfm_stall_cnt()
);

reg        acc_pend;
reg        acc_rd;
reg  [2:0] acc_reg;
reg  [7:0] acc_data;
reg        acc_empty;
wire       acc = acc_pend && !strobe;

wire [15:0] newest = (fifo_pos == 2'd2) ? fifo[1] : fifo[0];
reg   [7:0] rdata_c;
always @(*) begin
	case (reg_sel)
		3'd0, 3'd1: rdata_c = (fifo_pos == 0) ? 8'hFF : fifo[0][7:0];
		3'd2: rdata_c = error;
		3'd3: rdata_c = param[param_idx];
		3'd4: rdata_c = phases;
		3'd5: rdata_c = setup;
		3'd6: rdata_c = mode;
		default: rdata_c = {
			mode[4] ? (fifo_pos == 0 ? 2'b11 : fifo_pos == 1 ? 2'b10 : 2'b00)
			        : (fifo_pos == 2 ? 2'b11 : fifo_pos == 1 ? 2'b10 : 2'b00),
			error != 0, 1'b0,
			drv_data[7],
			1'b0,
			fifo_pos != 0 && !newest[FB_CRC0],
			fifo_pos != 0 &&  newest[FB_MARK] };
	endcase
end

always @(posedge clk) begin
	if (reset) acc_pend <= 1'b0;
	else if (strobe) begin
		acc_pend  <= 1'b1;
		acc_rd    <= !we;
		acc_reg   <= reg_sel;
		acc_data  <= wdata;
		acc_empty <= fifo_pos == 0;
		if (!we) rdata <= rdata_c;
	end
	else if (cen) acc_pend <= 1'b0;
end

reg        mfm_stb_d;
always @(posedge clk) mfm_stb_d <= mfm_stb;
wire       mfm_turning = drv_status[7] && devsel;
reg  [8:0] void_timer;
reg        void_tick;
always @(posedge clk) begin
	void_tick <= 1'b0;
	if (!mfm_wr || mfm_turning)
		void_timer <= setup[3] ? 9'd259 : 9'd129;
	else if (cep) begin
		if (void_timer != 0) void_timer <= void_timer - 1'd1;
		else begin
			void_timer <= setup[3] ? 9'd259 : 9'd129;
			void_tick  <= 1'b1;
		end
	end
end
wire mfm_tick = mfm_wr && ((mfm_turning && mfm_stb && !mfm_stb_d) || void_tick);

wire mfm_pop, mfm_unr;
ism_write_engine mfm_engine (
	.clk(clk), .rst(reset),
	.active(mfm_wr),
	.tick(mfm_tick),
	.q_word(fifo[0]),
	.q_empty(fifo_pos == 2'd0),
	.q_pop(mfm_pop),
	.o_byte(mfm_wr_byte), .o_mark(mfm_wr_mark), .o_stb(mfm_wr_stb),
	.underrun(mfm_unr)
);

reg  [6:0] gcr_timer;
reg        gcr_tick;
always @(posedge clk) begin
	gcr_tick <= 1'b0;
	if (!gcr_wr) gcr_timer <= 7'd0;
	else if (cep) begin
		if (gcr_timer == 0) begin gcr_tick <= 1'b1; gcr_timer <= 7'd127; end
		else gcr_timer <= gcr_timer - 1'd1;
	end
end

reg mfm_pop_p, mfm_unr_p, gcr_tick_p;
always @(posedge clk) begin
	mfm_pop_p  <= cen ? 1'b0 : (mfm_pop_p  | mfm_pop);
	mfm_unr_p  <= cen ? 1'b0 : (mfm_unr_p  | mfm_unr);
	gcr_tick_p <= cen ? 1'b0 : (gcr_tick_p | gcr_tick);
end
wire gcr_due  = gcr_wr && (gcr_tick || gcr_tick_p);
wire gcr_pop  = gcr_due && fifo_pos != 0;
wire wr_pop   = mfm_pop || mfm_pop_p || gcr_pop;
wire wr_unr   = mfm_unr || mfm_unr_p || (gcr_due && fifo_pos == 0);

wire        gen_push = devsel &&
                       ((mfm_rd && mfm_stb && (mfm_synced || mfm_mark)) ||
                        (gcr_rd && drv_byte && drv_data[7]));
wire [15:0] gen_word = gcr_rd ? {8'h00, drv_data}
                              : {mfm_sector, mfm_crc0, 1'b0, mfm_mark, mfm_byte};
wire        stage_push  = gen_push && stage_cnt != 5'd16;
wire        cpu_pop     = acc && acc_rd && (acc_reg == 3'd0 || acc_reg == 3'd1);
wire        cpu_push    = acc && !acc_rd && acc_reg <= 3'd2;
wire [15:0] cpu_word    = (acc_reg == 3'd2) ? 16'h0200 : {7'd0, acc_reg == 3'd1, acc_data};
wire        stage_drain = stage_cnt != 0 && fifo_pos < 2'd2 && !acc && !wr_arm;

wire [7:0]  mode_pre = wr_unr ? (mode & ~8'h08) : mode;
wire [7:0]  mode_clr = (mode_pre & ~acc_data) | 8'h40;
wire [7:0]  mode_set = mode_pre | acc_data;
wire [7:0]  mode_new = (acc && !acc_rd && acc_reg == 3'd6) ? mode_clr :
                       (acc && !acc_rd && acc_reg == 3'd7) ? mode_set : mode_pre;
reg         rd_arm_d, wr_arm_d;

always @(posedge clk) begin
	if (reset) begin
		mode <= 8'h40; setup <= 8'h00; phases <= 8'h00; error <= 8'h00;
		param[0] <= 0; param[1] <= 0; param[2] <= 0; param[3] <= 0;
		param_idx <= 0; fifo_pos <= 0;
		stage_rd <= 0; stage_wr <= 0; stage_cnt <= 0;
		mfm_synced <= 1'b0; anchor_sector <= 5'd1; anchor_ok <= 1'b0;
		rd_arm_d <= 1'b0; wr_arm_d <= 1'b0;
		gcr_req <= 1'b0; gcr_byte <= 8'h00;
	end
	else if (cen) begin
		if (gcr_req && !wbusy) gcr_req <= 1'b0;

		if (wr_unr) begin
			if (error == 0) error <= 8'h01;
			mode[3] <= 1'b0;
		end

		stage_cnt <= stage_cnt + {4'd0, stage_push} - {4'd0, stage_drain};
		if (stage_push) begin
			stage[stage_wr] <= gen_word;
			stage_wr <= stage_wr + 4'd1;
		end
		if (gen_push && stage_cnt == 5'd16 && error == 0) error <= 8'h01;
		if (stage_drain) begin
			fifo[fifo_pos[0]] <= stage[stage_rd];
			fifo_pos <= fifo_pos + 2'd1;
			stage_rd <= stage_rd + 4'd1;
		end

		if (cpu_pop) begin
			if (acc_empty || fifo_pos == 0) begin
				if (error == 0) error <= 8'h04;
			end else begin
				fifo[0]  <= fifo[1];
				fifo_pos <= fifo_pos - 2'd1;
				anchor_sector <= fifo[0][15:11];
				anchor_ok     <= 1'b1;
				if (acc_reg == 3'd0 && fifo[0][FB_MARK] && error == 0) error <= 8'h02;
			end
		end
		else if (wr_pop && cpu_push) begin
			fifo[0] <= fifo[1];
			fifo[fifo_pos - 2'd1] <= cpu_word;
		end
		else if (wr_pop) begin
			fifo[0]  <= fifo[1];
			fifo_pos <= fifo_pos - 2'd1;
		end
		else if (cpu_push) begin
			if (fifo_pos == 2'd2) begin
				if (error == 0) error <= 8'h04;
			end else begin
				fifo[fifo_pos[0]] <= cpu_word;
				fifo_pos <= fifo_pos + 2'd1;
			end
		end
		if (gcr_pop) begin
			gcr_byte <= fifo[0][7:0];
			gcr_req  <= 1'b1;
		end

		if (mfm_rd && devsel && mfm_stb && mfm_mark) mfm_synced <= 1'b1;

		if (acc) begin
			if (acc_rd) case (acc_reg)
				3'd2: error <= 8'h00;
				3'd3: param_idx <= param_idx + 2'd1;
				default: ;
			endcase
			else case (acc_reg)
				3'd3: begin param[param_idx] <= acc_data; param_idx <= param_idx + 2'd1; end
				3'd4: phases <= acc_data;
				3'd5: setup <= acc_data;
				3'd6: begin mode <= mode_clr; param_idx <= 2'd0; end
				3'd7: mode <= mode_set;
				default: ;
			endcase
			if (!acc_rd && mode_new[0]) begin
				fifo_pos <= 2'd0;
				stage_rd <= 0; stage_wr <= 0; stage_cnt <= 0;
			end
		end

		rd_arm_d <= rd_arm;
		wr_arm_d <= wr_arm;
		if (rd_arm != rd_arm_d || wr_arm != wr_arm_d) begin
			stage_rd <= 0; stage_wr <= 0; stage_cnt <= 0;
		end
		if (rd_arm && !rd_arm_d) begin
			mfm_synced <= 1'b0;
			anchor_ok  <= 1'b0;
		end
	end
end

`ifdef VERILATOR
reg       sl_on = 0;
reg [7:0] sl_hs_last = 8'h00;
reg [31:0] sl_hs_rpt = 0;
initial sl_on = $test$plusargs("swimlog");
always @(posedge clk) if (sl_on && strobe) begin
	if (!we && reg_sel == 3'd7) begin
		if (rdata_c != sl_hs_last) begin
			$display("SWIM2 hs %02x (x%0d) -> %02x  mode %02x setup %02x fifo %0d ring %0d @%0t",
			         sl_hs_last, sl_hs_rpt, rdata_c, mode, setup, fifo_pos, stage_cnt, $time);
			sl_hs_last <= rdata_c;
			sl_hs_rpt  <= 1;
		end else sl_hs_rpt <= sl_hs_rpt + 1;
	end
	else if (!(!we && reg_sel <= 3'd1))
		$display("SWIM2 %s r%0d %02x  mode %02x setup %02x err %02x fifo %0d @%0t",
		         we ? "W" : "R", reg_sel, we ? wdata : rdata_c, mode, setup, error, fifo_pos, $time);
end
`endif

endmodule

module ism_write_engine (
	input             clk,
	input             rst,

	input             active,
	input             tick,

	input      [15:0] q_word,
	input             q_empty,
	output            q_pop,

	output reg  [7:0] o_byte,
	output reg        o_mark,
	output reg        o_stb,

	output reg        underrun
);

	localparam Q_B_MARK = 8;
	localparam Q_B_CRC  = 9;
	localparam [15:0] CRC_SEED = 16'hCDB4;

	function [15:0] crc16;
		input [15:0] c;
		input  [7:0] d;
		integer i;
		reg [15:0] cc;
		begin
			cc = c ^ {d, 8'h00};
			for (i = 0; i < 8; i = i + 1)
				cc = cc[15] ? ((cc << 1) ^ 16'h1021) : (cc << 1);
			crc16 = cc;
		end
	endfunction

	reg [15:0] crc;
	reg        crc_2nd;

	reg q_pop_r;
	assign q_pop = q_pop_r;
	wire consume = active && tick && !crc_2nd && !q_empty;

	always @(posedge clk) begin
		o_stb    <= 1'b0;
		underrun <= 1'b0;
		q_pop_r  <= consume;

		if (rst) begin
			q_pop_r <= 1'b0;
			crc     <= CRC_SEED;
			crc_2nd <= 1'b0;
			o_byte  <= 8'h00;
			o_mark  <= 1'b0;
		end else if (!active) begin
			crc     <= CRC_SEED;
			crc_2nd <= 1'b0;
		end else if (tick) begin
			if (crc_2nd) begin
				o_byte  <= crc[15:8];
				o_mark  <= 1'b0;
				o_stb   <= 1'b1;
				crc     <= crc16(crc, crc[15:8]);
				crc_2nd <= 1'b0;
			end else if (q_empty) begin
				underrun <= 1'b1;
			end else if (q_word[Q_B_CRC]) begin
				o_byte  <= crc[15:8];
				o_mark  <= 1'b0;
				o_stb   <= 1'b1;
				crc     <= crc16(crc, crc[15:8]);
				crc_2nd <= 1'b1;
			end else if (q_word[Q_B_MARK]) begin
				o_byte <= q_word[7:0];
				o_mark <= 1'b1;
				o_stb  <= 1'b1;
				crc    <= CRC_SEED;
			end else begin
				o_byte <= q_word[7:0];
				o_mark <= 1'b0;
				o_stb  <= 1'b1;
				crc    <= crc16(crc, q_word[7:0]);
			end
		end
	end

endmodule
