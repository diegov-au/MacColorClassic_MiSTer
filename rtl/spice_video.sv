module spice_video #(
	parameter FULL = 1
)(
	input  wire        clk,
	input  wire        reset,

	input  wire        ce_pix,
	input  wire  [9:0] hc,
	input  wire  [9:0] vc,
	input  wire        mode640,

	input  wire  [2:0] depth,

	input  wire [18:0] vram_off,
	input  wire [15:0] vram_wdata,
	input  wire  [1:0] vram_we,
	output reg  [15:0] vram_q,

	input  wire        clut_strobe,
	input  wire        clut_we,
	input  wire  [1:0] clut_off,
	input  wire        clut_sel,
	input  wire  [7:0] clut_wdata,
	output reg   [7:0] clut_rdata,

	output reg   [7:0] r,
	output reg   [7:0] g,
	output reg   [7:0] b,
	output reg         de,
	output reg         hs,
	output reg         vs
);

localparam integer RW    = FULL ? 9 : 8;
localparam integer AW    = 9 + RW;
localparam integer WORDS = 384 << RW;

(* ramstyle = "M10K,no_rw_check" *) reg [7:0] vram_hi [0:WORDS-1] /*verilator public_flat_rd*/;
(* ramstyle = "M10K,no_rw_check" *) reg [7:0] vram_lo [0:WORDS-1] /*verilator public_flat_rd*/;

wire [AW-1:0] c_idx = mode640 ? ({vram_off[18:10], 8'd0} + {vram_off[18:10], 6'd0} + vram_off[9:1])
                              : {vram_off[18:10], vram_off[RW:1]};
reg  [7:0]    cq_hi, cq_lo;

always @(posedge clk) begin
	if (vram_we[1]) vram_hi[c_idx] <= vram_wdata[15:8];
	cq_hi <= vram_hi[c_idx];
end
always @(posedge clk) begin
	if (vram_we[0]) vram_lo[c_idx] <= vram_wdata[7:0];
	cq_lo <= vram_lo[c_idx];
end
always @(*) vram_q = {cq_hi, cq_lo};

reg  [7:0] clut_r [0:255];
reg  [7:0] clut_g [0:255];
reg  [7:0] clut_b [0:255];
reg  [7:0] a_addr;
reg  [1:0] a_rgb;
reg  [7:0] a_control;

wire       pal_wr = clut_strobe && clut_we && clut_sel && clut_off == 2'd1;
always @(posedge clk) if (pal_wr && a_rgb == 2'd0) clut_r[a_addr] <= clut_wdata;
always @(posedge clk) if (pal_wr && a_rgb == 2'd1) clut_g[a_addr] <= clut_wdata;
always @(posedge clk) if (pal_wr && a_rgb == 2'd2) clut_b[a_addr] <= clut_wdata;

reg  [7:0] cpu_r, cpu_g, cpu_b;
always @(posedge clk) begin
	cpu_r <= clut_r[a_addr];
	cpu_g <= clut_g[a_addr];
	cpu_b <= clut_b[a_addr];
end

reg [7:0] clut_rdata_c;
always @(*) begin
	clut_rdata_c = 8'h00;
	if (clut_sel) case (clut_off)
		2'd0: clut_rdata_c = a_addr;
		2'd1: clut_rdata_c = (a_rgb == 2'd0) ? cpu_r : (a_rgb == 2'd1) ? cpu_g : cpu_b;
		default: clut_rdata_c = a_control;
	endcase
end
always @(posedge clk) if (clut_strobe && !clut_we) clut_rdata <= clut_rdata_c;

wire step = (a_rgb == 2'd2);
always @(posedge clk) begin
	if (reset) begin
		a_addr <= 8'd0; a_rgb <= 2'd0; a_control <= 8'd0;
	end
	else if (clut_strobe && clut_sel) begin
		case (clut_off)
			2'd0: begin
				a_rgb <= 2'd0;
				if (clut_we) a_addr <= clut_wdata;
			end
			2'd1: begin
				a_rgb <= step ? 2'd0 : a_rgb + 2'd1;
				if (step) a_addr <= a_addr + 8'd1;
			end
			default: if (clut_we) a_control <= clut_wdata;
		endcase
	end
end

wire       vis = mode640 ? (hc < 10'd640 && vc < 10'd480) : (hc < 10'd512 && vc < 10'd384);
wire       d16 = FULL && depth == 3'd4 && !mode640;
reg  [3:0] bpp_shift;
always @(*) case (depth)
	3'd0: bpp_shift = 4'd0;
	3'd1: bpp_shift = 4'd1;
	3'd2: bpp_shift = 4'd2;
	default: bpp_shift = d16 ? 4'd4 : 4'd3;
endcase

wire [13:0]   bitpos = {4'd0, hc} << bpp_shift;
wire [AW-1:0] r_idx  = mode640 ? ({vc[8:0], 8'd0} + {vc[8:0], 6'd0} + bitpos[12:4])
                               : {vc[8:0], bitpos[RW+3:4]};
reg  [7:0]  q_hi, q_lo;
reg  [3:0]  bit_in_word;
reg  [7:0]  idx;
reg  [14:0] rgb16, rgb16_2;
reg         vis1, vis2, vis3, d16_1, d16_2, d16_3;
reg  [2:0]  depth1;

always @(posedge clk) if (ce_pix) begin
	q_hi <= vram_hi[r_idx];
	q_lo <= vram_lo[r_idx];
end

wire [15:0] word = {q_hi, q_lo};
reg  [7:0]  pix_idx;
always @(*) begin
	case (depth1)
		3'd0: pix_idx = {word[15 - bit_in_word], 7'h7F};
		3'd1: pix_idx = {word[15 - bit_in_word -: 2], 6'h3F};
		3'd2: pix_idx = {word[15 - bit_in_word -: 4], 4'hF};
		default: pix_idx = bit_in_word[3] ? word[7:0] : word[15:8];
	endcase
end

reg [7:0] col_r, col_g, col_b;
always @(posedge clk) if (ce_pix) begin
	col_r <= clut_r[idx];
	col_g <= clut_g[idx];
	col_b <= clut_b[idx];
end

wire hs_now = mode640 ? (hc >= 10'd656 && hc < 10'd752) : (hc >= 10'd560 && hc < 10'd592);
wire vs_now = mode640 ? (vc >= 10'd490 && vc < 10'd492) : (vc >= 10'd390 && vc < 10'd393);
reg [2:0] hs_d, vs_d, de_d;
always @(posedge clk) begin
	if (ce_pix) begin
		bit_in_word <= bitpos[3:0];
		depth1      <= depth;
		d16_1       <= d16;
		vis1        <= vis;
		idx         <= pix_idx;
		rgb16       <= word[14:0];
		d16_2       <= d16_1;
		vis2        <= vis1;
		rgb16_2     <= rgb16;
		d16_3       <= d16_2;
		vis3        <= vis2;
		r  <= !vis3 ? 8'd0 : d16_3 ? {rgb16_2[14:10], 3'd0} : col_r;
		g  <= !vis3 ? 8'd0 : d16_3 ? {rgb16_2[9:5],   3'd0} : col_g;
		b  <= !vis3 ? 8'd0 : d16_3 ? {rgb16_2[4:0],   3'd0} : col_b;
		hs_d <= {hs_d[1:0], hs_now};
		vs_d <= {vs_d[1:0], vs_now};
		de_d <= {de_d[1:0], vis};
		hs <= hs_d[2];
		vs <= vs_d[2];
		de <= de_d[2];
	end
end

endmodule
