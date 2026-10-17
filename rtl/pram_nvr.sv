// Adapted from the MacLC core's PRAM FSM (docs/reference/maclc_mister/MacLC.sv,
// VD_PRAM), the user's reference for anything HPS-facing. One 512-byte sector at

module pram_nvr
(
	input             clk,
	input             reset,
	input             rom_loaded,
	input             mac_reset,

	input             img_mounted,
	input      [63:0] img_size,

	output     [31:0] sd_lba,
	output reg        sd_rd,
	output reg        sd_wr,
	input             sd_ack,
	input       [7:0] sd_buff_addr,
	input      [15:0] sd_buff_dout,
	output     [15:0] sd_buff_din,
	input             sd_buff_wr,

	input             osd_status,
	input             save_req,

	output reg  [7:0] ext_addr,
	output reg        ext_we,
	output reg  [7:0] ext_wdata,
	input             ext_ready,
	input       [7:0] ext_q,
	input             pram_wr,

	output reg        ready,
	output reg        restart,
	output            loaded
);

localparam [26:0] T_SETTLE   = 27'd65_000_000;
localparam [26:0] T_BACKSTOP = 27'd65_000_000;
localparam [26:0] T_WATCHDOG = 27'd32_500_000;
localparam [28:0] T_LOADWAIT = 29'd325_000_000;
localparam [24:0] T_EARLY    = 25'd32_500_000;

assign sd_lba = 32'd0;

reg  [7:0] buf_mem[0:255];
assign sd_buff_din = sd_buff_addr[7] ? 16'h0000 :
                     {buf_mem[{sd_buff_addr[6:0], 1'b1}], buf_mem[{sd_buff_addr[6:0], 1'b0}]};

localparam [2:0] P_IDLE = 3'd0, P_LD_RD = 3'd1, P_LD_DAT = 3'd2, P_LD_CPY = 3'd3,
                 P_FILL = 3'd4, P_SV_WR = 3'd5, P_SV_DAT = 3'd6,
                 P_LD_WAIT = 3'd7;
reg  [2:0] pst;
reg  [8:0] pcnt;
reg  [1:0] fph;
reg        ena;
assign loaded = ena;
reg        dirty;
reg        load_pending, flush_pending, restart_after;
reg [26:0] settle, backstop;
reg [28:0] wd;
reg        old_ack, old_mnt, old_osd, old_save;

reg [24:0] run_t;
always @(posedge clk) begin
	if (reset || mac_reset) run_t <= 25'd0;
	else if (run_t != T_EARLY) run_t <= run_t + 1'd1;
end
wire mac_running = ready && !mac_reset;
wire too_late    = mac_running && run_t == T_EARLY;

always @(posedge clk) begin
	restart <= 1'b0;

	if (reset) begin
		pst <= P_IDLE; sd_rd <= 0; sd_wr <= 0; ext_we <= 0;
		ena <= 0; dirty <= 0; load_pending <= 0; flush_pending <= 0; restart_after <= 0;
		settle <= 0; backstop <= 0; wd <= 0; ready <= 0;
		old_ack <= 0; old_mnt <= 0; old_osd <= 0; old_save <= 0;
	end else begin
		old_ack  <= sd_ack;
		old_mnt  <= img_mounted;
		old_osd  <= osd_status;
		old_save <= save_req;

		if (sd_ack && sd_buff_wr && !sd_buff_addr[7]) begin
			buf_mem[{sd_buff_addr[6:0], 1'b0}] <= sd_buff_dout[7:0];
			buf_mem[{sd_buff_addr[6:0], 1'b1}] <= sd_buff_dout[15:8];
		end

		if (pram_wr) dirty <= 1'b1;

		if (img_mounted && !old_mnt) begin
			ena <= 1'b0;
			if (img_size != 0) load_pending <= 1'b1;
			else               ready <= 1'b1;
		end

		if (pram_wr)                settle <= T_SETTLE;
		else if (settle > 27'd1)    settle <= settle - 1'd1;
		else if (settle == 27'd1) begin
			settle <= 27'd0;
			if (dirty && ena) flush_pending <= 1'b1;
		end
		if (osd_status && !old_osd && dirty && ena) flush_pending <= 1'b1;
		if (save_req && !old_save && ena)           flush_pending <= 1'b1;

		if (!ready && pst == P_IDLE && !load_pending && rom_loaded) begin
			if (backstop == T_BACKSTOP) ready <= 1'b1;
			else backstop <= backstop + 1'd1;
		end

		case (pst)
		P_IDLE:
			if (load_pending) begin
				load_pending <= 0; sd_rd <= 1'b1; wd <= 0; pst <= P_LD_RD;
			end else if (flush_pending) begin
				flush_pending <= 0; pcnt <= 0; fph <= 0; pst <= P_FILL;
				dirty <= pram_wr;
			end

		P_LD_RD:
			if (sd_ack) begin sd_rd <= 1'b0; wd <= 0; pst <= P_LD_DAT; end
			else if (wd == T_LOADWAIT) ready <= 1'b1;
			else wd <= wd + 1'd1;
		P_LD_DAT:
			if (old_ack && !sd_ack) begin
				pcnt <= 0;
				if (too_late) pst <= P_LD_WAIT;
				else begin restart_after <= mac_running; pst <= P_LD_CPY; end
			end
			else if (wd == {2'b00, T_WATCHDOG}) begin ready <= 1'b1; pst <= P_IDLE; end
			else wd <= wd + 1'd1;
		P_LD_CPY:
			if (!ext_we) begin
				ext_we <= 1'b1; ext_addr <= pcnt[7:0]; ext_wdata <= buf_mem[pcnt[7:0]];
			end else if (ext_ready) begin
				if (pcnt == 9'd255) begin
					ext_we <= 1'b0; dirty <= 1'b0; ena <= 1'b1; ready <= 1'b1;
					if (restart_after) begin restart_after <= 1'b0; restart <= 1'b1; end
					pst <= P_IDLE;
				end else begin
					pcnt <= pcnt + 1'd1;
					ext_addr <= pcnt[7:0] + 8'd1; ext_wdata <= buf_mem[pcnt[7:0] + 8'd1];
				end
			end

		P_FILL:
			case (fph)
			2'd0: begin ext_addr <= pcnt[7:0]; fph <= 2'd1; end
			2'd1: if (ext_ready) fph <= 2'd2;
			2'd2: begin
				buf_mem[pcnt[7:0]] <= ext_q;
				if (pcnt == 9'd255) pst <= P_SV_WR;
				else begin pcnt <= pcnt + 1'd1; fph <= 2'd0; end
			end
			default: fph <= 2'd0;
			endcase
		P_SV_WR: begin
			sd_wr <= 1'b1;
			if (sd_ack) begin sd_wr <= 1'b0; pst <= P_SV_DAT; end
		end
		P_SV_DAT:
			if (old_ack && !sd_ack) pst <= P_IDLE;

		P_LD_WAIT:
			if (mac_reset) pst <= P_LD_CPY;

		default: pst <= P_IDLE;
		endcase
	end
end

endmodule
