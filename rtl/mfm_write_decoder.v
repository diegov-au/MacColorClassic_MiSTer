module mfm_write_decoder (
	input             clk,
	input             rst,

	input             ready,
	input      [7:0]  idata,
	input             imark,

	input             side,
	input      [6:0]  track,
	input             hd,

	input      [4:0]  anchor_sector,
	input             anchor_valid,

	output reg        sector_valid,
	output reg [4:0]  sector,
	output reg [21:0] addr,

	output reg        reject,

	output reg        amark,
	output reg [4:0]  amark_sector,
	output reg [6:0]  amark_cyl,
	output reg        amark_head,

	input      [8:0]  buf_addr,
	output reg [7:0]  buf_data
);

	function [15:0] crc16;
		input [15:0] c;
		input [7:0]  d;
		integer i;
		reg [15:0] cc;
		begin
			cc = c ^ {d, 8'h00};
			for (i = 0; i < 8; i = i + 1)
				cc = cc[15] ? ((cc << 1) ^ 16'h1021) : (cc << 1);
			crc16 = cc;
		end
	endfunction
	localparam [15:0] CRC_SEED = 16'hCDB4;

	localparam [7:0] AM_ID   = 8'hFE;
	localparam [7:0] AM_DATA = 8'hFB;
	localparam [7:0] AM_DEL  = 8'hF8;
	localparam [7:0] BYTE_A1 = 8'hA1;

	reg [7:0] buf_mem [0:511];
	always @(posedge clk) buf_data <= buf_mem[buf_addr];

	wire [7:0]  track_side = {track, side};
	wire [12:0] block_hd   = {track_side, 4'b0000} + {1'b0, track_side, 1'b0};
	wire [12:0] block_dd   = {1'b0, track_side, 3'b000} + {5'b0, track_side};
	wire [12:0] track_base = hd ? block_hd : block_dd;
	wire [4:0]  spt        = hd ? 5'd18 : 5'd9;

	localparam S_SYNC = 3'd0,
	           S_MARK = 3'd1,
	           S_ID   = 3'd2,
	           S_IDC  = 3'd3,
	           S_DATA = 3'd4,
	           S_DATC = 3'd5;
	reg [2:0] state;

	reg [15:0] crc;
	reg  [9:0] cnt;
	reg  [2:0] mark_cnt;

	reg        id_armed;
	reg  [4:0] id_sector;
	reg        id_oor, id_nsz;

	wire [4:0] use_sector = id_armed ? id_sector : anchor_sector;
	wire       use_valid  = id_armed ? 1'b1      : anchor_valid;
	wire       in_range   = (use_sector != 5'd0) && (use_sector <= spt);
	wire [12:0] block     = track_base + {8'd0, use_sector} - 13'd1;

	always @(posedge clk) begin
		sector_valid <= 1'b0;
		reject       <= 1'b0;
		amark        <= 1'b0;

		if (rst) begin
			state    <= S_SYNC;
			crc      <= 16'd0;
			cnt      <= 10'd0;
			mark_cnt <= 3'd0;
			id_armed <= 1'b0;
			id_sector <= 5'd0;
			id_oor   <= 1'b0;
			id_nsz   <= 1'b0;
			sector   <= 5'd0;
			addr     <= 22'd0;
			amark_sector <= 5'd0;
			amark_cyl    <= 7'd0;
			amark_head   <= 1'b0;
		end else if (ready) begin
			if (imark && idata == BYTE_A1) begin
				if (state != S_SYNC && state != S_MARK) reject <= 1'b1;
				state    <= S_MARK;
				mark_cnt <= (mark_cnt == 3'd7) ? mark_cnt : mark_cnt + 3'd1;
				crc      <= CRC_SEED;
				cnt      <= 10'd0;
			end else case (state)

			S_SYNC: mark_cnt <= 3'd0;

			S_MARK: begin
				mark_cnt <= 3'd0;
				if (mark_cnt < 3'd3) begin
					reject <= 1'b1;
					state  <= S_SYNC;
				end else begin
					crc <= crc16(crc, idata);
					cnt <= 10'd0;
					case (idata)
					AM_ID:            state <= S_ID;
					AM_DATA, AM_DEL:  state <= S_DATA;
					default: begin
						reject <= 1'b1;
						state  <= S_SYNC;
					end
					endcase
				end
			end

			S_ID: begin
				crc <= crc16(crc, idata);
				cnt <= cnt + 10'd1;
				case (cnt)
				10'd0: amark_cyl    <= idata[6:0];
				10'd1: amark_head   <= idata[0];
				10'd2: begin
					amark_sector <= idata[4:0];
					id_oor       <= (idata[7:5] != 3'd0);
				end
				default: id_nsz <= (idata != 8'h02);
				endcase
				if (cnt == 10'd3) begin cnt <= 10'd0; state <= S_IDC; end
			end

			S_IDC: begin
				crc <= crc16(crc, idata);
				cnt <= cnt + 10'd1;
				if (cnt == 10'd1) begin
					if (crc16(crc, idata) == 16'd0 && !id_oor && !id_nsz) begin
						id_armed  <= 1'b1;
						id_sector <= amark_sector;
						amark     <= 1'b1;
					end else begin
						id_armed <= 1'b0;
						reject   <= 1'b1;
					end
					state <= S_SYNC;
				end
			end

			S_DATA: begin
				crc <= crc16(crc, idata);
				buf_mem[cnt[8:0]] <= idata;
				cnt <= cnt + 10'd1;
				if (cnt == 10'd511) begin cnt <= 10'd0; state <= S_DATC; end
			end

			S_DATC: begin
				crc <= crc16(crc, idata);
				cnt <= cnt + 10'd1;
				if (cnt == 10'd1) begin
					if (crc16(crc, idata) == 16'd0 && use_valid && in_range) begin
						sector       <= use_sector;
						addr         <= {block, 9'd0};
						sector_valid <= 1'b1;
					end else
						reject <= 1'b1;
					id_armed <= 1'b0;
					state    <= S_SYNC;
				end
			end

			default: state <= S_SYNC;
			endcase
		end
	end

endmodule
