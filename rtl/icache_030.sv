module icache_030 #(
	parameter LOG2_WORDS   = 7,
	parameter WRITE_UPDATE = 0
)(
	input  wire        clk,
	input  wire        reset,
	input  wire        flush,
	input  wire        enable,
	input  wire        freeze,

	input  wire [23:0] early_addr,
	input  wire [23:0] bus_addr,
	input  wire        as_n,
	input  wire        rw,
	input  wire        fetch,
	input  wire        cacheable,
	input  wire [15:0] mem_din,
	input  wire [15:0] wdata,
	input  wire  [1:0] wbe,

	output wire        hit,
	output wire [15:0] hit_data
);

localparam integer WORDS = 1 << LOG2_WORDS;
localparam integer TAGW  = 23 - LOG2_WORDS;

(* ramstyle = "M10K" *) reg [TAGW-1:0] tag_ram  [0:WORDS-1];
(* ramstyle = "M10K" *) reg [15:0]     data_ram [0:WORDS-1];
reg [WORDS-1:0] valid = {WORDS{1'b0}};

wire [LOG2_WORDS-1:0] e_idx = early_addr[LOG2_WORDS:1];
wire [LOG2_WORDS-1:0] idx   = bus_addr[LOG2_WORDS:1];
wire [TAGW-1:0]       tag   = bus_addr[23:LOG2_WORDS+1];

reg  as_n_d = 1'b1;
wire as_fall = as_n_d && !as_n;
wire as_rise = !as_n_d && as_n;
wire fetch_start = as_fall && rw && fetch && cacheable;
wire write_start = as_fall && !rw && cacheable;

reg [TAGW-1:0]       tag_q;
reg [15:0]           data_q;
reg                  valid_q;
reg [LOG2_WORDS-1:0] rd_idx;

reg                  miss_pend = 1'b0;
reg [LOG2_WORDS-1:0] miss_idx;
reg [TAGW-1:0]       miss_tag;
wire                 fill = as_rise && miss_pend && !flush;

reg  collide_d = 1'b0, flush_d = 1'b0;

wire hold    = valid_q && !collide_d && !flush && !flush_d && rd_idx == idx && tag_q == tag;
wire match   = hold;
wire hit_c   = enable && rw && fetch && cacheable && match;
reg  hit_held = 1'b0;
reg  [15:0] hit_data_r;
assign hit      = !as_n && (as_n_d ? hit_c : hit_held);
assign hit_data = as_n_d ? data_q : hit_data_r;

wire [15:0] w_merge = {wbe[1] ? wdata[15:8] : data_q[15:8], wbe[0] ? wdata[7:0] : data_q[7:0]};
wire        w_upd   = WRITE_UPDATE && write_start && !flush && (hold || wbe == 2'b11);

wire                  ram_we    = fill || w_upd;
wire [LOG2_WORDS-1:0] ram_widx  = fill ? miss_idx : idx;
wire [TAGW-1:0]       ram_wtag  = fill ? miss_tag : tag;
wire [15:0]           ram_wdata = fill ? mem_din  : w_merge;
wire                  collide   = ram_we && ram_widx == e_idx;

always @(posedge clk) begin
	if (ram_we) begin
		tag_ram[ram_widx]  <= ram_wtag;
		data_ram[ram_widx] <= ram_wdata;
	end
	tag_q  <= tag_ram[e_idx];
	data_q <= data_ram[e_idx];
end

always @(posedge clk) begin
	as_n_d    <= as_n;
	valid_q   <= valid[e_idx];
	rd_idx    <= e_idx;
	collide_d <= collide;
	flush_d   <= flush;

	if (as_n)        hit_held <= 1'b0;
	else if (as_n_d) begin hit_held <= hit_c; hit_data_r <= data_q; end

	if (reset || flush) begin
		valid     <= {WORDS{1'b0}};
		miss_pend <= 1'b0;
	end else begin
		if (write_start) valid[idx] <= w_upd;
		if (fetch_start && !match) begin
			miss_pend <= !freeze;
			miss_idx  <= idx;
			miss_tag  <= tag;
		end
		if (fill) begin
			miss_pend     <= 1'b0;
			valid[miss_idx] <= 1'b1;
		end
	end
end

`ifdef VERILATOR
reg [31:0] n_fetch = 0, n_hit = 0;
always @(posedge clk) if (fetch_start) begin
	n_fetch <= n_fetch + 1;
	if (hit_c) n_hit <= n_hit + 1;
end
`endif

endmodule
