module asc_sonora (
	input  wire        clk,
	input  wire        reset,

	input  wire        strobe,
	input  wire        we,
	input  wire [12:0] addr,
	input  wire        uds,
	input  wire        lds,
	input  wire [15:0] din,
	output reg  [7:0]  dout,

	output reg         irq,

	output reg  [7:0]  sample_l,
	output reg  [7:0]  sample_r,
	output reg         sample_tick,
	output wire [7:0]  volume
);

localparam [7:0]  VERSION    = 8'hBC;
localparam [10:0] SAMPLE_DIV = 11'd1460;

function automatic in_regs(input [11:0] a);
	in_regs = (a[11:8] == 4'h8 || a[11:8] == 4'hF) && a[7:6] == 2'b00;
endfunction
function automatic [6:0] ridx(input [11:0] a);
	ridx = {a[8], a[5:0]};
endfunction

reg  [9:0] wr_a, wr_b, rd_a, rd_b;
reg [11:0] cap_a, cap_b;
reg  [7:0] stat;
reg        irqen_a, irqen_b;
reg  [7:0] regs [0:127];
reg [10:0] div;

wire [7:0] playreca = regs[7'h0A];
assign     volume   = regs[7'h06];

wire [11:0] a_byte = {addr[11:1], (lds && !uds) ? 1'b1 : addr[0]};
wire        tick   = (div == SAMPLE_DIV - 1'd1);
wire        cpu_wr = strobe && we && !addr[12];
wire        push_a1 = cpu_wr && addr[11:10] == 2'b00;
wire        push_b1 = cpu_wr && addr[11:10] == 2'b01;
reg         pend_a = 0, pend_b = 0;
reg   [7:0] pend_d;
always @(posedge clk) begin
	pend_a <= !reset && push_a1 && uds && lds;
	pend_b <= !reset && push_b1 && uds && lds;
	if ((push_a1 || push_b1) && uds && lds) pend_d <= din[7:0];
end
wire        push_a = push_a1 || pend_a;
wire        push_b = push_b1 || pend_b;
wire  [7:0] push_d = (pend_a || pend_b) ? pend_d : (uds ? din[15:8] : din[7:0]);

always @(*) begin
	if (addr[12])
		dout = 8'hFF;
	else if (!addr[11])
		dout = 8'h00;
	else case (a_byte)
		12'h800: dout = VERSION;
		12'h801: dout = 8'h01;
		12'h802, 12'h803, 12'h805, 12'h807, 12'h808: dout = 8'h00;
		12'h804: dout = stat;
		12'hF09: dout = {7'd0, irqen_a};
		12'hF29: dout = {7'd0, irqen_b};
		default: dout = in_regs(a_byte) ? regs[ridx(a_byte)] : 8'h00;
	endcase
end

reg [7:0] fifo_a [0:1023];
reg [7:0] fifo_b [0:1023];
always @(posedge clk) if (push_a) fifo_a[wr_a] <= push_d;
always @(posedge clk) if (push_b) fifo_b[wr_b] <= push_d;
always @(posedge clk) begin
	sample_tick <= tick && !reset;
	if (tick) begin
		sample_l <= fifo_a[rd_a];
		sample_r <= fifo_b[rd_b];
	end
end

task automatic reg_lane(input [11:0] a, input [7:0] d,
                        inout [7:0] st, inout iq, inout ia, inout ib);
	begin
		case (a)
			12'h801, 12'h802, 12'h805, 12'h807, 12'h808: ;
			default: begin
				if (a == 12'hF09) begin
					if (!d[0] && ia && st[0]) iq = 1'b1;
					else if (d[0])            iq = 1'b0;
					ia = d[0];
				end
				if (a == 12'hF29) begin
					if (!d[0] && ib && st[2]) iq = 1'b1;
					else if (d[0])            iq = 1'b0;
					ib = d[0];
				end
				if (a == 12'hE00) begin
					st = st | 8'h0F;
					iq = 1'b1;
				end
				if (a == 12'h804)
					st = d;
			end
		endcase
	end
endtask

wire reg_wr_even = cpu_wr && addr[11] && uds && in_regs({addr[11:1], 1'b0});
wire reg_wr_odd  = cpu_wr && addr[11] && lds && in_regs({addr[11:1], 1'b1});
function automatic dropped(input [11:0] a);
	dropped = (a == 12'h801 || a == 12'h802 || a == 12'h805 || a == 12'h807 || a == 12'h808);
endfunction

integer i;
always @(posedge clk) begin
	if (reset) begin
		for (i = 0; i < 128; i = i + 1) regs[i] <= 8'h00;
	end
	else begin
		if (reg_wr_even && !dropped({addr[11:1], 1'b0}))
			regs[ridx({addr[11:1], 1'b0})] <= din[15:8];
		if (reg_wr_odd && !dropped({addr[11:1], 1'b1}))
			regs[ridx({addr[11:1], 1'b1})] <= din[7:0];
	end
end

reg [11:0] ca, cb;
reg  [7:0] st;
reg        iq, ia, ib;

always @(posedge clk) begin
	if (reset) begin
		wr_a <= 0; wr_b <= 0; rd_a <= 0; rd_b <= 0;
		cap_a <= 0; cap_b <= 0;
		stat <= 8'h02;
		irqen_a <= 0; irqen_b <= 0;
		irq <= 0;
		div <= 0;
	end
	else begin
		ca = cap_a; cb = cap_b; st = stat; iq = irq; ia = irqen_a; ib = irqen_b;

		div <= tick ? 11'd0 : div + 1'd1;
		if (tick) begin
			if (!playreca[0]) begin
				st[1] = 1'b1;
				if (!ia) iq = 1'b1;
			end
			if (ca != 0) begin rd_a <= rd_a + 1'd1; ca = ca - 1'd1; end
			if (cb != 0) begin rd_b <= rd_b + 1'd1; cb = cb - 1'd1; end
			if (ca < 12'h200 || cb < 12'h200) begin
				st[2] = 1'b1;
				if (!ib) iq = 1'b1;
			end
			else
				st[2] = 1'b0;
			st[3] = (ca == 0 || cb == 0);
		end

		if (push_a) begin
			wr_a <= wr_a + 1'd1;
			ca = ca + 1'd1;
			if (!playreca[0]) begin
				if (ca >= 12'h200) begin
					st[0] = 1'b0;
					if (ca >= 12'h3FF) st[1] = 1'b1;
				end
				else if (ca > 0)
					st[1] = 1'b0;
				st[1] = 1'b1;
			end
		end
		else if (push_b) begin
			wr_b <= wr_b + 1'd1;
			cb = cb + 1'd1;
			if (cb >= 12'h200) begin
				st[2] = 1'b0;
				if (cb >= 12'h3FF) st[3] = 1'b1;
			end
			else if (cb > 0)
				st[3] = 1'b0;
		end
		else if (cpu_wr && addr[11]) begin
			if (uds) reg_lane({addr[11:1], 1'b0}, din[15:8], st, iq, ia, ib);
			if (lds) reg_lane({addr[11:1], 1'b1}, din[7:0],  st, iq, ia, ib);
		end
		else if (strobe && !we && !addr[12] && a_byte == 12'h804 && !st[2])
			iq = 1'b0;

		cap_a <= ca; cap_b <= cb; stat <= st; irq <= iq; irqen_a <= ia; irqen_b <= ib;
	end
end

endmodule
