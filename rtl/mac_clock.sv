module mac_clock (
	input             clk,
	input             clear,
	input      [32:0] timestamp,
	input      [64:0] rtc_bcd,
	output reg [31:0] secs = 32'd0,
	output wire       seeded
);

reg seeded_r = 1'b0;
assign seeded = seeded_r;

localparam [31:0] MAC_EPOCH = 32'd2082844800;
localparam [24:0] ONE_SEC   = 25'd32_499_999;

reg  [24:0] tick = 25'd0;
reg         ts_t = 1'b0, rtc_t = 1'b0;
reg         rtc_valid = 1'b0;
reg  [15:0] rtc_hm = 16'd0;
reg   [2:0] sst = 3'd0;
localparam  S_IDLE = 3'd0, S_WAIT = 3'd1, S_MOD = 3'd2, S_DIV = 3'd3, S_ADD = 3'd4;
reg  [31:0] ts_cap, r;
reg   [4:0] k;
reg  [10:0] ts_min;
reg  [24:0] wait_cnt;
reg         wait_sec;

wire [32:0] mod_sub = 33'd86400 << k;
wire [16:0] div_sub = 17'd60 << k[3:0];
wire  [7:0] rtc_h   = rtc_hm[15:12] * 4'd10 + rtc_hm[11:8];
wire  [7:0] rtc_m   = rtc_hm[7:4]   * 4'd10 + rtc_hm[3:0];
wire [11:0] rtc_min = rtc_h * 6'd60 + rtc_m;
wire signed [12:0] dmin_raw = $signed({1'b0, rtc_min}) - $signed({2'b00, ts_min});
wire signed [12:0] dmin = (dmin_raw < -13'sd720) ? dmin_raw + 13'sd1440 :
                          (dmin_raw >= 13'sd720) ? dmin_raw - 13'sd1440 : dmin_raw;
wire signed [31:0] dsec = dmin * 32'sd60;
wire ts_new = (ts_t != timestamp[32]);
`ifdef VERILATOR
reg hw_path = 1'b0;
initial hw_path = $test$plusargs("mac_clock_hw");
`endif

always @(posedge clk) begin
	ts_t  <= timestamp[32];
	rtc_t <= rtc_bcd[64];
	if (rtc_t != rtc_bcd[64]) begin rtc_valid <= 1'b1; rtc_hm <= rtc_bcd[23:8]; end

	if (tick == ONE_SEC) begin tick <= 25'd0; secs <= secs + 1'd1; end
	else tick <= tick + 1'd1;

	case (sst)
	S_IDLE:
`ifdef VERILATOR
		if (!seeded_r && !hw_path && timestamp[31:0] != 32'd0) begin
			secs <= timestamp[31:0] + MAC_EPOCH; seeded_r <= 1'b1;
		end else
`endif
		if (!seeded_r && ts_new) begin
			ts_cap <= timestamp[31:0]; wait_cnt <= 25'd0; wait_sec <= 1'b0; sst <= S_WAIT;
		end
	S_WAIT:
		if (rtc_valid) begin r <= ts_cap; k <= 5'd15; sst <= S_MOD; end
		else if (wait_cnt == ONE_SEC) begin
			secs <= ts_cap + MAC_EPOCH + 32'd1; seeded_r <= 1'b1; sst <= S_IDLE;
		end else wait_cnt <= wait_cnt + 1'd1;
	S_MOD: begin
		if ({1'b0, r} >= mod_sub) r <= r - mod_sub[31:0];
		if (k == 5'd0) begin k <= 5'd10; ts_min <= 11'd0; sst <= S_DIV; end
		else k <= k - 1'd1;
	end
	S_DIV: begin
		if (r[16:0] >= div_sub) begin r <= r - div_sub; ts_min[k[3:0]] <= 1'b1; end
		if (k == 5'd0) sst <= S_ADD;
		else k <= k - 1'd1;
	end
	S_ADD: begin
		secs <= ts_cap + MAC_EPOCH + dsec + {31'd0, wait_sec};
		seeded_r <= 1'b1; sst <= S_IDLE;
	end
	default: sst <= S_IDLE;
	endcase

	if (clear) begin seeded_r <= 1'b0; sst <= S_IDLE; end
end

endmodule
