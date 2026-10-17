/*
 Per sector (x18 HD / x9 DD), from MAME upd765_dsk get_desc_mfm:
*/

/* verilator lint_off UNUSED */

module mfm_track_encoder
(
	input             clk,
	input             ready,
	input             rst,

	input             side,
	input      [6:0]  track,
	input             hd,

	output     [21:0] addr,
	input      [7:0]  idata,

	output reg [7:0]  odata,
	output reg        omark,
	output reg        ocrc0,
	output            oneeds,
	output            oindex,

	output      [4:0] osector
);

	wire [7:0] track_side = {track, side};
	wire [4:0] spt_max    = hd ? 5'd17 : 5'd8;

	wire [12:0] block_hd = {track_side, 4'b0000} + {1'b0, track_side, 1'b0};
	wire [12:0] block_dd = {1'b0, track_side, 3'b000} + {5'b0, track_side};
	wire [12:0] sector_block = (hd ? block_hd : block_dd) + {8'b0, sector};

	assign addr = {sector_block[12:0], src_offset[8:0]};

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

	localparam S_PRE_GAP  = 4'd0;
	localparam S_PRE_SYNC = 4'd1;
	localparam S_PRE_IAM  = 4'd2;
	localparam S_PRE_GAP1 = 4'd3;
	localparam S_ID_SYNC  = 4'd4;
	localparam S_ID_A1    = 4'd5;
	localparam S_ID_AM    = 4'd6;
	localparam S_ID_CHRN  = 4'd7;
	localparam S_ID_CRC   = 4'd8;
	localparam S_GAP2     = 4'd9;
	localparam S_DA_SYNC  = 4'd10;
	localparam S_DA_A1    = 4'd11;
	localparam S_DA_AM    = 4'd12;
	localparam S_DATA     = 4'd13;
	localparam S_DA_CRC   = 4'd14;
	localparam S_GAP3     = 4'd15;

	reg [3:0] state;
	reg [9:0] cnt;
	assign oneeds = (state == S_DATA);
	assign oindex = (state == S_PRE_GAP);
	reg [4:0] sector;
	assign osector = sector + 5'd1;
	reg [8:0] src_offset;
	reg [15:0] crc;

	reg [9:0] state_len_m1;
	always @(*) begin
		case (state)
			S_PRE_GAP:  state_len_m1 = 10'd79;
			S_PRE_SYNC: state_len_m1 = 10'd11;
			S_PRE_IAM:  state_len_m1 = 10'd3;
			S_PRE_GAP1: state_len_m1 = 10'd49;
			S_ID_SYNC:  state_len_m1 = 10'd11;
			S_ID_A1:    state_len_m1 = 10'd2;
			S_ID_AM:    state_len_m1 = 10'd0;
			S_ID_CHRN:  state_len_m1 = 10'd3;
			S_ID_CRC:   state_len_m1 = 10'd1;
			S_GAP2:     state_len_m1 = 10'd21;
			S_DA_SYNC:  state_len_m1 = 10'd11;
			S_DA_A1:    state_len_m1 = 10'd2;
			S_DA_AM:    state_len_m1 = 10'd0;
			S_DATA:     state_len_m1 = 10'd511;
			S_DA_CRC:   state_len_m1 = 10'd1;
			default:    state_len_m1 = 10'd107;
		endcase
	end

	reg [7:0] chrn;
	always @(*) begin
		case (cnt[1:0])
			2'd0:    chrn = {1'b0, track};
			2'd1:    chrn = {7'b0, side};
			2'd2:    chrn = {3'b0, sector + 5'd1};
			default: chrn = 8'h02;
		endcase
	end

	always @(*) begin
		omark = 1'b0;
		ocrc0 = 1'b0;
		case (state)
			S_PRE_SYNC,
			S_ID_SYNC, S_DA_SYNC: odata = 8'h00;
			S_PRE_GAP, S_PRE_GAP1,
			S_GAP2, S_GAP3:       odata = 8'h4E;
			S_PRE_IAM:            odata = (cnt == 10'd3) ? 8'hFC : 8'hC2;
			S_ID_A1, S_DA_A1: begin odata = 8'hA1; omark = 1'b1; end
			S_ID_AM:              odata = 8'hFE;
			S_DA_AM:              odata = 8'hFB;
			S_ID_CHRN:            odata = chrn;
			S_DATA:               odata = idata;
			S_ID_CRC, S_DA_CRC: begin
				odata = (cnt[0] == 1'b0) ? crc[15:8] : crc[7:0];
				ocrc0 = (cnt[0] == 1'b1);
			end
			default:              odata = 8'h4E;
		endcase
	end

	always @(posedge clk or posedge rst) begin
		if (rst) begin
			state      <= S_PRE_GAP;
			cnt        <= 10'd0;
			sector     <= 5'd0;
			src_offset <= 9'd0;
			crc        <= CRC_SEED;
		end else if (ready) begin
			if ((state == S_ID_A1 || state == S_DA_A1) && cnt == 10'd2)
				crc <= CRC_SEED;
			else if (state == S_ID_AM || state == S_ID_CHRN ||
			         state == S_DA_AM || state == S_DATA)
				crc <= crc16(crc, odata);

			if (state == S_DATA)
				src_offset <= src_offset + 9'd1;
			else if (state != S_DATA)
				src_offset <= 9'd0;

			if (cnt == state_len_m1) begin
				cnt <= 10'd0;
				if (state == S_GAP3) begin
					if (sector == spt_max) begin
						sector <= 5'd0;
						state  <= S_PRE_GAP;
					end else begin
						sector <= sector + 5'd1;
						state  <= S_ID_SYNC;
					end
				end else begin
					state <= state + 4'd1;
				end
			end else begin
				cnt <= cnt + 10'd1;
			end
		end
	end

endmodule
