`define DRIVE_REG_DIRTN		0
`define DRIVE_REG_CSTIN		1
`define DRIVE_REG_STEP		2
`define DRIVE_REG_WRTPRT	3
`define DRIVE_REG_MOTORON	4
`define DRIVE_REG_TK0		5
`define DRIVE_REG_EJECT		6
`define DRIVE_REG_TACH		7
`define DRIVE_REG_RDDATA0	8
`define DRIVE_REG_RDDATA1	9
`define DRIVE_REG_SUPERDR	10
`define DRIVE_REG_SIDES		12
`define DRIVE_REG_READY		13
`define DRIVE_REG_INSTALLED	14
`define DRIVE_REG_DRVIN		15

module floppy
#(
	parameter WRITE_SUPPORT = 1,

	// synthesised instance overrides these; same technique as
	parameter [8:0] MFM_PERIOD_HD = 9'd129,
	parameter [8:0] MFM_PERIOD_DD = 9'd259
)
(
	input clk,
	input cep,
	input cen,

	input _reset,
	input ca0,
	input ca1,
	input ca2,
	input SEL,
	input lstrb,
	input _enable, 			
	input [7:0] writeData,		
	output [7:0] readData,

	input        writeReq,
	input        writeProtect,
	input        writeMode,
	output       writeBusy,
	output       writeUnderrun,
	output        wrSecValid,
	output [4:0]  wrSecNum,
	output [21:0] wrSecAddr,
	output [21:0] wrSdAddr,
	output [15:0] wrSdData,
	output        wrSdReq,
	input         wrSdAck,
	output        wrCommitDone,
	output [21:0] wrCommitAddr,
	output  [7:0] wrSdBufAddr,
	output [15:0] wrSdBufData,
	output        wrSdBufWr,
	
	input advanceDriveHead,
	output reg newByteReady,
	input insertDisk,
	input diskSides,
	input mediaSides,
	output diskEject,

	output motor,
	output act,

	output [21:0] dskReadAddr,
	input dskReadAck,
	input [7:0] dskReadData,

	input            ism_active,
	input            ism_action,
	input            ism_sel,
	input            mfm_disk,
	input            mfm_hd,
	output reg [7:0] mfm_byte,
	output reg       mfm_mark,
	output reg       mfm_crc0,
	output reg       mfm_stb,
	output reg [4:0] mfm_sector,

	input      [7:0] mfm_wr_byte,
	input            mfm_wr_mark,
	input            mfm_wr_stb,
	input      [4:0] mfm_wr_anchor,
	input            mfm_wr_anchor_ok,

	// Ported from lbmactwo_MiSTer ac44312 (the debug deck that root-caused its
	// 800K "unreadable" bug). Counters wrap; the host reads deltas over a window.
	output reg  [15:0] dbg_byte_cnt,
	output reg  [15:0] dbg_miss_cnt,
	output wire [7:0]  dbg_disk_image_data,
	output wire [6:0]  dbg_drive_track,
	output wire        dbg_drive_side,
	output reg  [15:0] dbg_step_cnt,
	output wire        dbg_byte_stb,
	output wire [7:0]  dbg_raw_byte,
	output wire [21:0] dbg_gcr_addr,
	output reg  [31:0] dbg_media,
	output reg  [15:0] dbg_strb_cnt,
	output reg  [15:0] dbg_strb_en_cnt,
	output reg  [23:0] dbg_strb_last,
	output reg  [8:0]  dbg_rej_step,
	output wire [7:0]  dbg_status,
	output reg  [15:0] dbg_mfm_stall_us,
	output reg  [7:0]  dbg_mfm_stall_cnt
);
	assign dbg_disk_image_data = diskImageData;
	assign dbg_drive_track     = driveTrack;
	assign dbg_drive_side      = driveSide;
	assign dbg_raw_byte        = dskReadDataLatch;
	assign dbg_gcr_addr        = gcrReadAddr;

	assign motor = ~driveRegs[`DRIVE_REG_MOTORON];
	assign dbg_status = {mfm_spinning, motor, ism_sel,
	                     driveRegs[`DRIVE_REG_MOTORON], driveSide, ism_active,
	                     ism_action, ~driveRegs[`DRIVE_REG_CSTIN]};
	assign act = lstrbEdge;

	reg [15:0] driveRegs;
	reg [6:0] driveTrack;
	reg driveSide;
	reg [7:0] diskDataIn;
	
	wire [15:0] driveRegsAsRead = {
		(~driveRegs[`DRIVE_REG_CSTIN] & ~mfm_hd),
		1'b0,
		1'b0,
		1'b1,
		m_mfm,
		1'b1,
		1'b1,
		1'b0,
		driveRegs[`DRIVE_REG_TACH],
		disk_switched,
		~(driveTrack == 7'h00),
		driveRegs[`DRIVE_REG_MOTORON],
		~writeProtect,
		1'b1,
		driveRegs[`DRIVE_REG_CSTIN],
		driveRegs[`DRIVE_REG_DIRTN]
	};

	reg m_mfm;
	wire [3:0] strobeCmd = {SEL, ca2, ca1, ca0};
	always @(posedge clk or negedge _reset) begin
		if (!_reset)
			m_mfm <= 1'b1;
		else if (cep && _enable == 1'b0 && lstrbEdge == 1'b1) begin
			if (strobeCmd == 4'h9) m_mfm <= 1'b1;
			if (strobeCmd == 4'hD) m_mfm <= 1'b0;
		end
	end

	reg disk_switched;
	reg insertDisk_d;
	always @(posedge clk or negedge _reset) begin
		if (!_reset) begin
			disk_switched <= 1'b0;
			insertDisk_d  <= 1'b0;
		end
		else if (cep) begin
			insertDisk_d <= insertDisk;
			if (insertDisk_d && !insertDisk)
				disk_switched <= 1'b1;
			else if (_enable == 1'b0 && lstrbEdge && strobeCmd == 4'hC) begin
				disk_switched <= 1'b0;
`ifdef SIMULATION
				$display("FLOPPY %m DskchgClear strobe (switched %b->0) @%0t",
				         disk_switched, $time);
`endif
			end
`ifdef SIMULATION
			if (insertDisk_d && !insertDisk)
				$display("FLOPPY %m media REMOVED -> disk_switched=1 @%0t", $time);
`endif
		end
	end

	reg dskReadAckD;
	always @(posedge clk) if(cen) dskReadAckD <= dskReadAck;

	reg [7:0] dskReadDataLatch;
	always @(posedge clk) if(cep && dskReadAckD) dskReadDataLatch <= dskReadData;
		
	wire [7:0] dskReadDataEnc;
	wire [21:0] gcrReadAddr;
	wire [21:0] mfmReadAddr;

	reg old_newByteReady;
	always @(posedge clk) old_newByteReady <= newByteReady;

	wire       wrRelayByte;
	wire       wrRelayMark;
	wire [3:0] wrRelayMarkSector;
	wire       wrRelayEnd;

	floppy_track_encoder enc
	(

		.clk		( clk ),
		.ready	( ~old_newByteReady & newByteReady ),

		.rst     ( !_reset ),

		.side    ( driveSide ),
		.sides   ( doubleSidedDisk ),
		.track   ( driveTrack ),

		.addr    ( gcrReadAddr ),
		.idata   ( dskReadDataLatch ),
		.odata   ( dskReadDataEnc ),

		.wr_byte        ( wrRelayByte ),
		.wr_mark        ( wrRelayMark ),
		.wr_mark_sector ( wrRelayMarkSector ),
		.wr_end         ( wrRelayEnd )
	);

	wire [7:0] mfm_odata;
	wire       mfm_omark, mfm_ocrc0, mfm_needs_data, mfm_index;
	wire [4:0] mfm_osector;
	reg        mfm_ready_pulse;

	mfm_track_encoder menc
	(
		.clk    ( clk ),
		.ready  ( mfm_ready_pulse ),
		.rst    ( !_reset ),
		.side   ( driveSide ),
		.track  ( driveTrack ),
		.hd     ( mfm_hd ),
		.addr   ( mfmReadAddr ),
		.idata  ( dskReadDataLatch ),
		.odata  ( mfm_odata ),
		.omark  ( mfm_omark ),
		.osector( mfm_osector ),
		.ocrc0  ( mfm_ocrc0 ),
		.oneeds ( mfm_needs_data ),
		.oindex ( mfm_index )
	);

	wire       mfm_spinning = mfm_disk && (motor || ism_sel) &&
	                          ~driveRegs[`DRIVE_REG_CSTIN];
	wire [8:0] mfm_period   = mfm_hd ? MFM_PERIOD_HD : MFM_PERIOD_DD;
	reg  [8:0] mfm_timer;
	reg        mfm_fresh;
	reg        mfm_ack_skip;
	always @(posedge clk or negedge _reset) begin
		if (_reset == 1'b0) begin
			mfm_timer       <= 9'd0;
			mfm_fresh       <= 1'b0;
			mfm_ack_skip    <= 1'b0;
			mfm_ready_pulse <= 1'b0;
			mfm_stb         <= 1'b0;
			mfm_byte        <= 8'h00;
			mfm_mark        <= 1'b0;
			mfm_sector      <= 5'd1;
			mfm_crc0        <= 1'b0;
		end else begin
			mfm_ready_pulse <= 1'b0;
			if (cep) begin
				mfm_stb <= 1'b0;
				if (dskReadAckD) begin
					if (mfm_ack_skip) mfm_ack_skip <= 1'b0;
					else              mfm_fresh    <= 1'b1;
				end
				if (!mfm_spinning) begin
					mfm_timer <= mfm_period;
				end
				else if (mfm_timer != 0) begin
					mfm_timer <= mfm_timer - 9'd1;
				end
				else if (!mfm_needs_data || mfm_fresh) begin
					mfm_byte        <= mfm_odata;
					mfm_mark        <= mfm_omark;
					mfm_crc0        <= mfm_ocrc0;
					mfm_sector      <= mfm_osector;
					mfm_stb         <= 1'b1;
					mfm_ready_pulse <= 1'b1;
					mfm_fresh       <= 1'b0;
					mfm_ack_skip    <= 1'b1;
					mfm_timer       <= mfm_period;
				end
			end
		end
	end

	wire mfm_stalled = mfm_spinning && (mfm_timer == 9'd0) &&
	                   mfm_needs_data && !mfm_fresh;
	reg [2:0]  mfm_stall_pre;
	reg [15:0] mfm_stall_run;
	always @(posedge clk or negedge _reset) begin
		if (_reset == 1'b0) begin
			mfm_stall_pre    <= 3'd0;
			mfm_stall_run    <= 16'd0;
			dbg_mfm_stall_us  <= 16'd0;
			dbg_mfm_stall_cnt <= 8'd0;
		end
		else if (cep) begin
			if (mfm_stalled) begin
				mfm_stall_pre <= mfm_stall_pre + 3'd1;
				if (mfm_stall_pre == 3'd7 && mfm_stall_run != 16'hFFFF) begin
					mfm_stall_run <= mfm_stall_run + 16'd1;
					if (mfm_stall_run == 16'd0 && dbg_mfm_stall_cnt != 8'hFF)
						dbg_mfm_stall_cnt <= dbg_mfm_stall_cnt + 8'd1;
					if (mfm_stall_run >= dbg_mfm_stall_us)
						dbg_mfm_stall_us <= mfm_stall_run + 16'd1;
				end
			end
			else begin
				mfm_stall_pre <= 3'd0;
				mfm_stall_run <= 16'd0;
			end
		end
	end

`ifdef SIMULATION
	reg [13:0] dbgsim_strobe_cnt = 0;
	reg [13:0] dbgsim_dlv_cnt = 0;
	reg        dbgsim_spin_d = 0;
	reg        dbgsim_idx_d = 0;
	reg [3:0]  dbgsim_sns_addr = 4'hF;
	reg        dbgsim_sns_val = 1'b1;
	reg [15:0] dbgsim_sns_rpt = 0;
	reg [11:0] dbgsim_sns_cnt = 0;
	wire       dbgsim_sns_now = readData[7];
	always @(posedge clk) begin
		if (cep && _enable == 1'b0) begin
			if (driveReadAddr != dbgsim_sns_addr || dbgsim_sns_now != dbgsim_sns_val) begin
				if (dbgsim_sns_cnt < 12'd800) begin
					dbgsim_sns_cnt <= dbgsim_sns_cnt + 1'd1;
					$display("FLOPPY %m sense[%x]=%b (prev[%x]=%b x%0d) SEL=%b @%0t",
					         driveReadAddr, dbgsim_sns_now, dbgsim_sns_addr,
					         dbgsim_sns_val, dbgsim_sns_rpt, SEL, $time);
				end
				dbgsim_sns_addr <= driveReadAddr;
				dbgsim_sns_val  <= dbgsim_sns_now;
				dbgsim_sns_rpt  <= 16'd1;
			end else if (dbgsim_sns_rpt != 16'hFFFF)
				dbgsim_sns_rpt <= dbgsim_sns_rpt + 1'd1;
		end
	end
	always @(posedge clk) begin
		if (cep && _enable == 1'b0 && lstrbEdge && dbgsim_strobe_cnt < 14'd8000) begin
			dbgsim_strobe_cnt <= dbgsim_strobe_cnt + 1'd1;
			$display("FLOPPY %m strobe(fall) cmd=%x track=%0d mfm=%b motor(reg)=%b @%0t",
			         {SEL, ca2, ca1, ca0}, driveTrack, m_mfm, driveRegs[`DRIVE_REG_MOTORON], $time);
		end
		if (cep && _enable == 1'b0 && lstrb && !lstrbPrev && dbgsim_strobe_cnt < 14'd8000)
			$display("FLOPPY %m strobe(rise) cmd=%x track=%0d @%0t",
			         {SEL, ca2, ca1, ca0}, driveTrack, $time);
		if (cep) begin
			dbgsim_spin_d <= mfm_spinning;
			if (mfm_spinning != dbgsim_spin_d)
				$display("FLOPPY %m mfm_spinning -> %b (motor=%b ism_sel=%b cstin=%b) trk=%0d side=%b @%0t",
				         mfm_spinning, motor, ism_sel, driveRegs[`DRIVE_REG_CSTIN], driveTrack, driveSide, $time);
			dbgsim_idx_d <= mfm_index;
			if (mfm_spinning && mfm_index && !dbgsim_idx_d)
				$display("FLOPPY %m index pulse trk=%0d side=%b @%0t", driveTrack, driveSide, $time);
			if (mfm_stb && dbgsim_dlv_cnt < 14'd8000) begin
				dbgsim_dlv_cnt <= dbgsim_dlv_cnt + 1'd1;
				$display("FLOPPY %m mfm dlv %02x m=%b c0=%b trk=%0d side=%b needs=%b addr=%0d latch=%02x @%0t",
				         mfm_byte, mfm_mark, mfm_crc0, driveTrack, driveSide,
				         mfm_needs_data, mfmReadAddr, dskReadDataLatch, $time);
			end
		end
	end
`endif

	assign dskReadAddr = mfm_disk ? mfmReadAddr : gcrReadAddr;

	wire mfm_idx_sense = mfm_spinning ? ~mfm_index : 1'b1;
	
	// Double-sided = drive mechanism AND file size AND the medium. Ported from
	// MacPlus floppy.v; the drive term is a constant here, as the LC has a
	// SuperDrive and nothing else. Three ceilings, each load-bearing:
	wire doubleSidedDisk;
	
	wire [3:0] driveReadAddr = {ca2,ca1,ca0,SEL};
	
	reg [6:0] diskDataByteTimer; 
	reg [7:0] diskImageData;	
	reg readyToAdvanceHead;
	always @(posedge clk or negedge _reset) begin
		if (_reset == 0) begin		
			driveSide <= 0;
			diskImageData <= 8'h00;
			diskDataIn <= 8'hFF;
			diskDataByteTimer <= 0;
			readyToAdvanceHead <= 1;
			newByteReady <= 1'b0;
		end 
		else begin			
			if(cep) begin
			if (diskDataByteTimer == 0 && readyToAdvanceHead && diskImageData != 0) begin
				diskDataIn <= diskImageData;
				newByteReady <= 1;
				diskDataByteTimer <= 1;

				diskImageData <= 0;

				readyToAdvanceHead <= 1'b1;
			end

			else begin
				diskDataByteTimer <= diskDataByteTimer + 1'b1;

				newByteReady <= 1'b0;

				if (dskReadAck) begin
					diskImageData <= dskReadDataEnc;
 				end

				if (advanceDriveHead) begin
					readyToAdvanceHead <= 1'b1;
				end
			end

			if (ism_active ? ism_action : 1'b1) begin
				if (driveReadAddr == `DRIVE_REG_RDDATA0 && lstrb == 1'b0) begin
`ifdef SIMULATION
					if (driveSide != 1'b0)
						$display("FLOPPY %m driveSide 1->0 (ism=%b act=%b) @%0t", ism_active, ism_action, $time);
`endif
					driveSide <= 0;
				end
				if (driveReadAddr == `DRIVE_REG_RDDATA1 && lstrb == 1'b0) begin
`ifdef SIMULATION
					if (driveSide != 1'b1)
						$display("FLOPPY %m driveSide 0->1 (ism=%b act=%b) @%0t", ism_active, ism_action, $time);
`endif
					driveSide <= 1;
				end
			end
		end
	end
	end

	wire dbg_read_sel = (driveReadAddr == `DRIVE_REG_RDDATA0 ||
	                     driveReadAddr == `DRIVE_REG_RDDATA1) && (_enable == 1'b0);
	assign dbg_byte_stb = cep && diskDataByteTimer == 0 && dbg_read_sel &&
	                      readyToAdvanceHead && (diskImageData != 0);
	always @(posedge clk or negedge _reset) begin
		if (_reset == 1'b0) begin
			dbg_byte_cnt <= 16'd0;
			dbg_miss_cnt <= 16'd0;
		end
		else if (cep && diskDataByteTimer == 0 && dbg_read_sel) begin
			if (readyToAdvanceHead && diskImageData != 0)
				dbg_byte_cnt <= dbg_byte_cnt + 16'd1;
			else
				dbg_miss_cnt <= dbg_miss_cnt + 16'd1;
		end
	end

	reg lstrbPrev;
	always @(posedge clk) if(cep) lstrbPrev <= lstrb;

	wire lstrbEdge = lstrb == 1'b0 && lstrbPrev == 1'b1;

	always @(posedge clk or negedge _reset) begin
		if (_reset == 1'b0) begin
			dbg_strb_cnt    <= 16'd0;
			dbg_strb_en_cnt <= 16'd0;
			dbg_strb_last   <= 24'd0;
			dbg_rej_step    <= 9'd0;
		end else if (cep && lstrbEdge) begin
			if (_enable == 1'b1 && ca2 == 1'b0 &&
			    {ca1, ca0, SEL} == `DRIVE_REG_STEP) begin
				dbg_rej_step[8] <= 1'b1;
				if (dbg_rej_step[7:0] != 8'hFF)
					dbg_rej_step[7:0] <= dbg_rej_step[7:0] + 8'd1;
			end
			if (dbg_strb_cnt != 16'hFFFF) dbg_strb_cnt <= dbg_strb_cnt + 16'd1;
			if (_enable == 1'b0 && dbg_strb_en_cnt != 16'hFFFF)
				dbg_strb_en_cnt <= dbg_strb_en_cnt + 16'd1;
			dbg_strb_last <= {dbg_strb_last[17:0],
			                  _enable, ca2, ca1, ca0, SEL, ism_active};
		end
	end

	wire dbg_park1 = (_enable == 1'b0) && (driveReadAddr == `DRIVE_REG_CSTIN);
	wire dbg_park6 = (_enable == 1'b0) && (driveReadAddr == `DRIVE_REG_EJECT);
	reg  dbg_park1_d, dbg_park6_d, dbg_cstin_d;
	always @(posedge clk or negedge _reset) begin
		if (_reset == 1'b0) begin
			dbg_media   <= 32'd0;
			dbg_park1_d <= 1'b0;
			dbg_park6_d <= 1'b0;
			dbg_cstin_d <= 1'b1;
		end
		else if (cep) begin
			dbg_media[31] <= driveRegs[`DRIVE_REG_CSTIN];
			dbg_media[30] <= disk_switched;
			dbg_media[29] <= insertDisk;
			dbg_media[28] <= ism_active;
			dbg_park1_d <= dbg_park1;
			dbg_park6_d <= dbg_park6;
			dbg_cstin_d <= driveRegs[`DRIVE_REG_CSTIN];
			if (_enable == 1'b0 && (!ism_active || ism_sel) && lstrbEdge &&
			    driveWriteAddr == `DRIVE_REG_EJECT && ca2 == 1'b1 &&
			    dbg_media[27:24] != 4'hF)
				dbg_media[27:24] <= dbg_media[27:24] + 4'd1;
			if (_enable == 1'b0 && lstrbEdge && strobeCmd == 4'hC &&
			    dbg_media[23:20] != 4'hF)
				dbg_media[23:20] <= dbg_media[23:20] + 4'd1;
			if (dbg_cstin_d != driveRegs[`DRIVE_REG_CSTIN] &&
			    dbg_media[19:16] != 4'hF)
				dbg_media[19:16] <= dbg_media[19:16] + 4'd1;
			if (dbg_park1 && !dbg_park1_d)
				dbg_media[15:8] <= dbg_media[15:8] + 8'd1;
			if (dbg_park6 && !dbg_park6_d)
				dbg_media[7:0] <= dbg_media[7:0] + 8'd1;
		end
	end

	assign readData = _enable ? 8'hFF :
	                  (driveReadAddr == `DRIVE_REG_RDDATA0 || driveReadAddr == `DRIVE_REG_RDDATA1) ?
	                      (mfm_disk ? {mfm_idx_sense, 7'h00} : diskDataIn) :
							{ driveRegsAsRead[driveReadAddr], 7'h00 };
		
	wire [2:0] driveWriteAddr = {ca1,ca0,SEL};

	generate
	if (WRITE_SUPPORT) begin : wrpath

	// GCR write path. Ported from MacPlus_MiSTer rtl/floppy.v; the LC-specific
	// parts are marked below. It lives here, below driveWriteAddr/lstrbEdge,
	reg        writeBusyReg;
	reg [6:0]  writeByteTimer;
	reg [7:0]  pendingWriteByte;
	reg        writeUnderrunReg;
	reg        decReady;

	assign writeBusy     = writeBusyReg;
	assign writeUnderrun = writeUnderrunReg;

	// Quartus infer a latch.
	reg insertDiskPrev;
	always @(posedge clk or negedge _reset)
		if (!_reset)   insertDiskPrev <= 1'b1;
		else if (cep)  insertDiskPrev <= insertDisk;
	wire insertDiskEdge = insertDisk && !insertDiskPrev;
	wire insertDiskFall = !insertDisk && insertDiskPrev;

	wire ejectPulse = cep && _enable == 1'b0 && (!ism_active || ism_sel) &&
	                  lstrbEdge == 1'b1 &&
	                  driveWriteAddr == `DRIVE_REG_EJECT && ca2 == 1'b1;

	wire writePathReset = ejectPulse || (cep && (insertDiskEdge || insertDiskFall));

	always @(posedge clk or negedge _reset) begin
		if (_reset == 1'b0) begin
			writeBusyReg     <= 1'b0;
			writeByteTimer   <= 7'd0;
			pendingWriteByte <= 8'd0;
			writeUnderrunReg <= 1'b0;
			decReady         <= 1'b0;
		end else if (writePathReset) begin
			writeBusyReg     <= 1'b0;
			writeByteTimer   <= 7'd0;
			decReady         <= 1'b0;
		end else begin
			decReady <= 1'b0;

			if (cep && writeBusyReg) begin
				if (_enable == 1'b1) begin
					writeBusyReg     <= 1'b0;
					writeUnderrunReg <= 1'b1;
				end else if (writeByteTimer == 7'd127) begin
					writeBusyReg <= 1'b0;
					decReady     <= 1'b1;
				end else begin
					writeByteTimer <= writeByteTimer + 1'b1;
				end
			end

			if (writeReq && _enable == 1'b0 && !writeProtect && !writeBusyReg &&
			    !driveRegs[`DRIVE_REG_CSTIN] && insertDisk) begin
				pendingWriteByte <= writeData;
				writeBusyReg     <= 1'b1;
				writeByteTimer   <= 7'd0;
				writeUnderrunReg <= 1'b0;
			end
		end
	end

	reg  wrBusyPrev, wrEndD1;
	reg  wrEnd;
	wire wrBusy = (writeMode && _enable == 1'b0) || writeBusyReg;
	always @(posedge clk or negedge _reset) begin
		if (_reset == 1'b0) begin
			wrBusyPrev <= 1'b0;
			wrEndD1    <= 1'b0;
			wrEnd      <= 1'b0;
		end else begin
			if (cep) wrBusyPrev <= wrBusy;
			wrEndD1 <= (cep && wrBusyPrev && !wrBusy) || writePathReset;
			wrEnd   <= wrEndD1;
		end
	end

	wire wrSecAmark, wrSecFmtMark, wrSecFmtDs;
	wire [3:0] wrSecAmarkSector;
	wire [8:0] wrBufAddr;

	assign wrRelayByte       = decReady;
	assign wrRelayMark       = wrSecAmark;
	assign wrRelayMarkSector = wrSecAmarkSector;
	assign wrRelayEnd        = wrEnd;

	reg fmtSeen;
	reg fmtDs;
	always @(posedge clk) begin
		if (!_reset || writePathReset) begin
			fmtSeen <= 1'b0;
			fmtDs   <= 1'b0;
		end
		else if (wrSecFmtMark) begin
			fmtSeen <= 1'b1;
			fmtDs   <= wrSecFmtDs;
		end
	end

	assign doubleSidedDisk = diskSides && (fmtSeen ? fmtDs : mediaSides);

	wire        gcrSecValid, mfmSecValid;
	wire  [3:0] gcrSecNum;
	wire  [4:0] mfmSecNum;
	wire [21:0] gcrSecAddr,  mfmSecAddr;
	wire  [7:0] gcrBufData,  mfmBufData;
	wire        gcrSecReject, mfmSecReject;

	wire        wrIsMfm   = mfm_disk;
	wire        wrSecValidMux = wrIsMfm ? mfmSecValid : gcrSecValid;
	wire [21:0] wrSecAddrMux  = wrIsMfm ? mfmSecAddr  : gcrSecAddr;
	wire  [7:0] wrBufData     = wrIsMfm ? mfmBufData  : gcrBufData;

	assign wrSecValid = wrSecValidMux;
	assign wrSecAddr  = wrSecAddrMux;
	assign wrSecNum   = wrIsMfm ? mfmSecNum : {1'b0, gcrSecNum};
	wire        wrSecReject   = wrIsMfm ? mfmSecReject : gcrSecReject;

	mfm_write_decoder mdec
	(
		.clk           ( clk ),
		.rst           ( !_reset || writePathReset ),

		.ready         ( mfm_wr_stb ),
		.idata         ( mfm_wr_byte ),
		.imark         ( mfm_wr_mark ),

		.side          ( driveSide ),
		.track         ( driveTrack ),
		.hd            ( mfm_hd ),

		.anchor_sector ( mfm_wr_anchor ),
		.anchor_valid  ( mfm_wr_anchor_ok ),

		.sector_valid  ( mfmSecValid ),
		.sector        ( mfmSecNum ),
		.addr          ( mfmSecAddr ),
		.reject        ( mfmSecReject ),

		.amark         (  ),
		.amark_sector  (  ),
		.amark_cyl     (  ),
		.amark_head    (  ),

		.buf_addr      ( wrBufAddr ),
		.buf_data      ( mfmBufData )
	);

	floppy_track_decoder dec
	(
		.clk          ( clk ),
		.ready        ( decReady ),
		.rst          ( !_reset || writePathReset ),

		.side         ( driveSide ),
		.sides        ( doubleSidedDisk ),
		.track        ( driveTrack ),

		.idata        ( pendingWriteByte ),

		.sector_valid ( gcrSecValid ),
		.sector       ( gcrSecNum ),
		.addr         ( gcrSecAddr ),
		.reject       ( gcrSecReject ),
		.amark        ( wrSecAmark ),
		.amark_sector ( wrSecAmarkSector ),
		.fmt_mark     ( wrSecFmtMark ),
		.fmt_ds       ( wrSecFmtDs ),

		.buf_addr     ( wrBufAddr ),
		.buf_data     ( gcrBufData )
	);

	wire        wrCommitBusy;

	floppy_write_committer wc
	(
		.clk            ( clk ),
		.rst            ( !_reset || writePathReset ),

		.sector_valid   ( wrSecValidMux ),
		.sector_addr    ( wrSecAddrMux ),
		.buf_addr       ( wrBufAddr ),
		.buf_data       ( wrBufData ),

		.wr_addr        ( wrSdAddr ),
		.wr_data        ( wrSdData ),
		.wr_req         ( wrSdReq ),
		.wr_ack         ( wrSdAck ),

		.busy           ( wrCommitBusy ),
		.done           ( wrCommitDone ),
		.committed_addr ( wrCommitAddr ),

		.sd_buf_addr    ( wrSdBufAddr ),
		.sd_buf_data    ( wrSdBufData ),
		.sd_buf_wr      ( wrSdBufWr )
	);

	reg [7:0] wr_sec_cnt, wr_rej_cnt;
	always @(posedge clk or negedge _reset) begin
		if (!_reset) begin
			wr_sec_cnt <= 8'd0;
			wr_rej_cnt <= 8'd0;
		end else begin
			if (wrSecValid)    wr_sec_cnt <= wr_sec_cnt + 8'd1;
			if (wrSecReject)   wr_rej_cnt <= wr_rej_cnt + 8'd1;
		end
	end

	(* preserve, noprune *) reg [31:0] wr_anchor0, wr_anchor1, wr_anchor2;
	always @(posedge clk) begin
		wr_anchor0 <= {wr_sec_cnt, wr_rej_cnt[6:0], wrSecNum,
		               writeBusyReg, writeUnderrunReg, writeProtect, insertDisk,
		               driveSide, driveTrack[6:0]};
		wr_anchor1 <= {2'b0, wrSecValid, wrSecAmark, wrSecFmtMark, wrSecFmtDs,
		               wrSecAmarkSector, wrSecAddr};
		wr_anchor2 <= {wrCommitBusy, wrCommitDone, wrBufData, wrCommitAddr};
	end

	end else begin : no_wrpath
		assign writeBusy     = 1'b0;
		assign writeUnderrun = 1'b0;
		assign wrSecValid    = 1'b0;
		assign wrSecNum      = 4'd0;
		assign wrSecAddr     = 22'd0;
		assign wrSdAddr      = 22'd0;
		assign wrSdData      = 16'd0;
		assign wrSdReq       = 1'b0;
		assign wrCommitDone  = 1'b0;
		assign wrCommitAddr  = 22'd0;
		assign wrSdBufAddr   = 8'd0;
		assign wrSdBufData   = 16'd0;
		assign wrSdBufWr     = 1'b0;
		assign doubleSidedDisk = diskSides && mediaSides;
		assign wrRelayByte       = 1'b0;
		assign wrRelayMark       = 1'b0;
		assign wrRelayMarkSector = 4'd0;
		assign wrRelayEnd        = 1'b0;
	end
	endgenerate

	always @(posedge clk or negedge _reset) begin
		if (_reset == 1'b0) begin		
			driveRegs[`DRIVE_REG_DIRTN] <= 1'b0;
		end 
		else if(cep && _enable == 1'b0 && lstrbEdge == 1'b1 && driveWriteAddr == `DRIVE_REG_DIRTN) begin
			driveRegs[`DRIVE_REG_DIRTN] <= ca2;
		end
	end

	reg [23:0] ejectIndicatorTimer;
	assign diskEject = (ejectIndicatorTimer != 0);
	
	always @(posedge clk or negedge _reset) begin
		if (_reset == 1'b0) begin
			driveRegs[`DRIVE_REG_CSTIN] <= 1'b1;
			ejectIndicatorTimer <= 24'd0;
		end
		else if(cep) begin
			if (_enable == 1'b0 && (!ism_active || ism_sel) && lstrbEdge == 1'b1 && driveWriteAddr == `DRIVE_REG_EJECT && ca2 == 1'b1) begin
				driveRegs[`DRIVE_REG_CSTIN] <= 1'b1;
				ejectIndicatorTimer <= 24'hFFFFFF;
`ifdef SIMULATION
				$display("FLOPPY %m EJECT accepted (ism=%b sel=%b) @%0t",
				         ism_active, ism_sel, $time);
`endif
			end
			else begin
				driveRegs[`DRIVE_REG_CSTIN] <= ~insertDisk;
				if (ejectIndicatorTimer != 0)
					ejectIndicatorTimer <= ejectIndicatorTimer - 1'b1;
			end
		end
	end
									
	always @(posedge clk or negedge _reset) begin
		if (_reset == 1'b0) begin
			driveTrack   <= 0;
			dbg_step_cnt <= 16'd0;
		end
		else if(cep && _enable == 1'b0 && lstrbEdge == 1'b1 && driveWriteAddr == `DRIVE_REG_STEP && ca2 == 1'b0) begin
			dbg_step_cnt <= dbg_step_cnt + 16'd1;
			if (driveRegs[`DRIVE_REG_DIRTN] == 1'b0 && driveTrack != 7'h4F) begin
				driveTrack <= driveTrack + 1'b1;
			end
			if (driveRegs[`DRIVE_REG_DIRTN] == 1'b1 && driveTrack != 0) begin
				driveTrack <= driveTrack - 1'b1;
			end
		end
	end
	
	always @(posedge clk or negedge _reset) begin
		if (_reset == 1'b0) begin		
			driveRegs[`DRIVE_REG_MOTORON] <= 1'b1;
		end 
		else if (cep && _enable == 1'b0 && lstrbEdge == 1'b1 && driveWriteAddr == `DRIVE_REG_MOTORON) begin
			driveRegs[`DRIVE_REG_MOTORON] <= ca2;
		end
	end

	reg [14:0] driveTachTimer;
	reg [14:0] driveTachPeriod;

	always @(*) begin
		if (mfm_disk) begin
			driveTachPeriod <= 15'd16660;
		end
		else case (driveTrack[6:4])
			0:
				driveTachPeriod <= 9996;
			1:
				driveTachPeriod <= 9122;
			2:
				driveTachPeriod <= 8292;
			3:
				driveTachPeriod <= 7463;
			default:
				driveTachPeriod <= 6634;
		endcase
	end
	
	always @(posedge clk or negedge _reset) begin
		if (_reset == 1'b0) begin		
			driveRegs[`DRIVE_REG_TACH] <= 1'b0;
			driveTachTimer <= 0;
		end 
		else if(cep) begin
			if (driveTachTimer == driveTachPeriod) begin
				driveTachTimer <= 0;
				driveRegs[`DRIVE_REG_TACH] <= ~driveRegs[`DRIVE_REG_TACH];
			end
			else begin
				driveTachTimer <= driveTachTimer + 1'b1;
			end
		end
	end	
endmodule
