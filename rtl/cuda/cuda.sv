// card as boot1.rom: never baked into the bitstream. The CPU is the MacLC
// core's m68hc05_core; the 68HC05E1's peripherals and Cuda's pins are written
// from MAME 0.289 (docs/reference/mame/m68hc05e1.cpp, cuda.cpp), not from the
// MacLC core's Egret wrapper, whose port-test and handshake workarounds belong
// to Egret's firmware.

`default_nettype none

module cuda (
	input  wire        clk,
	input  wire        reset,

	input  wire        fw_wr,
	input  wire [11:0] fw_addr,
	input  wire [15:0] fw_data,
	input  wire        fw_loaded,

	input  wire        ext_we,
	input  wire  [7:0] ext_addr,
	input  wire  [7:0] ext_wdata,
	output wire        ext_ready,
	output reg   [7:0] ext_q,
	input  wire        pram_valid,
	input  wire        run,
	output wire        pram_written,
	input  wire [31:0] mac_seconds,

	input  wire        via_tip,
	input  wire        via_byteack,
	input  wire        via_cb2_o,
	input  wire        via_cb2_oe,
	output wire        treq,
	output wire        via_clock,
	output wire        via_data,

	input  wire        adb_line,
	output wire        adb_drive_low,

	output wire        iic_scl,
	output wire        iic_sda,
	input  wire        iic_sda_in,

	output reg         cpu_hold,
	output reg         cpu_reset_pulse,
	output wire        nmi,

	output wire [15:0] dbg_addr,
	output wire        dbg_running,
	output wire [7:0]  dbg_a2
);

reg  [2:0] div;
reg        copy_busy;
wire       cen_raw = div == 3'd0;
wire       cen     = cen_raw && fw_loaded && run && !copy_busy;
always @(posedge clk) div <= reset ? 3'd0 : div + 3'd1;

wire [15:0] cpu_addr;
wire        cpu_wr_n;
wire  [7:0] cpu_dout;
reg   [7:0] cpu_din;
wire  [3:0] cpu_state;
reg         timer_irq, cpi_irq;

m68hc05_core u_cpu (
	.clk        ( clk          ),
	.cen        ( cen          ),
	.rst        ( ~(reset || !fw_loaded) ),
	.irq        ( 1'b1         ),
	.timer_irq  ( ~timer_irq   ),
	.onesec_irq ( ~cpi_irq     ),
	.addr       ( cpu_addr     ),
	.wr         ( cpu_wr_n     ),
	.datain     ( cpu_din      ),
	.state      ( cpu_state    ),
	.dataout    ( cpu_dout     )
);

assign dbg_addr    = cpu_addr;
assign dbg_running = fw_loaded && !reset;

wire [12:0] a13    = cpu_addr[12:0];
wire        io_cs  = a13 < 13'h0020;
wire        ram_cs = a13 >= 13'h0090 && a13 < 13'h0200;
wire        rom_cs = a13 >= 13'h0F00;
wire        cpu_we = cen && !cpu_wr_n;

reg [15:0] rom [0:2175];
reg [15:0] rom_q;
reg        rom_lo;
wire [12:0] rom_off = a13 - 13'h0F00;
always @(posedge clk) begin
	if (fw_wr) rom[fw_addr] <= fw_data;
	rom_q  <= rom[rom_off[12:1]];
	rom_lo <= rom_off[0];
end
wire [7:0] rom_byte = rom_lo ? rom_q[7:0] : rom_q[15:8];

reg  [7:0] ram [0:367];
reg  [7:0] ram_q;
reg  [8:0] copy_idx;
reg        copy_done;
reg  [8:0] ram_waddr;
reg  [7:0] ram_wdata;
reg        ram_we;

reg  [7:0] pram [0:255];
reg  [7:0] pram_q;
wire       ram_cpu_we = cpu_we && ram_cs;
assign     ext_ready  = !copy_busy && !ram_cpu_we;
always @(posedge clk) begin
	if (ext_we && ext_ready) pram[ext_addr] <= ext_wdata;
	pram_q <= pram[copy_idx[7:0]];
end

wire [8:0] ram_raddr = a13[8:0] - 9'h090;
assign pram_written = ram_cpu_we && copy_done && ram_raddr >= 9'h070 && ram_raddr < 9'h170;

`ifdef VERILATOR
reg pramlog = 1'b0, pram_wr_d = 1'b0;
initial pramlog = $test$plusargs("pramlog");
always @(posedge clk) begin
	pram_wr_d <= pram_written;
	if (pramlog && pram_written && !pram_wr_d)
		$display("cuda: PRAM[%02X] <= %02X  (t %0t)", ram_raddr - 9'h070, cpu_dout, $time);
end
`endif

always @(*) begin
	ram_we    = 1'b0;
	ram_waddr = ram_raddr;
	ram_wdata = cpu_dout;
	if (ext_we && ext_ready && copy_done) begin
		ram_we    = 1'b1;
		ram_waddr = 9'h070 + ext_addr;
		ram_wdata = ext_wdata;
	end
	else if (copy_busy && copy_idx != 9'd0) begin
		ram_we = pram_valid || copy_idx > 9'd256;
		if (copy_idx <= 9'd256) begin
			ram_waddr = 9'h070 + (copy_idx - 9'd1);
			ram_wdata = pram_q;
		end else begin
			ram_waddr = 9'h01B + (copy_idx - 9'd257);
			case (copy_idx - 9'd257)
				9'd0: ram_wdata = mac_seconds[31:24];
				9'd1: ram_wdata = mac_seconds[23:16];
				9'd2: ram_wdata = mac_seconds[15:8];
				default: ram_wdata = mac_seconds[7:0];
			endcase
		end
	end
	else if (cpu_we && ram_cs) ram_we = 1'b1;
end

always @(posedge clk) ext_q <= ram[9'h070 + ext_addr];

always @(posedge clk) begin
	if (ram_we) ram[ram_waddr] <= ram_wdata;
	ram_q <= ram[ram_raddr];
end

reg [7:0] a2_shadow = 8'h00;
always @(posedge clk) if (cpu_we && a13 == 13'h00A2) a2_shadow <= cpu_dout;
assign dbg_a2 = a2_shadow;

reg [7:0] pa_l, pb_l, pc_l, pa_ddr, pb_ddr, pc_ddr;
localparam [7:0] PULL_A = 8'h00, PULL_B = 8'hC0, PULL_C = 8'h04;

wire [7:0] pa_pin = (pa_l & pa_ddr) | (PULL_A & ~pa_ddr);
wire [7:0] pb_pin = (pb_l & pb_ddr) | (PULL_B & ~pb_ddr);
wire [7:0] pc_pin = (pc_l & pc_ddr) | (PULL_C & ~pc_ddr);

reg via_data_r = 1'b1;
always @(posedge clk) if (via_cb2_oe) via_data_r <= via_cb2_o;

wire [7:0] pa_ext = {1'b0, adb_line, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1, 1'b1};
wire [7:0] pb_ext = {1'b1, iic_sda_in, via_data_r, 1'b0, via_tip, via_byteack, 1'b0, 1'b1};
wire [7:0] pc_ext = 8'h03;

assign adb_drive_low = pa_pin[7];
assign treq          = pb_pin[1];
assign via_clock     = pb_pin[4];
assign via_data      = pb_pin[5];
assign iic_sda       = pb_pin[6];
assign iic_scl       = pb_pin[7];
assign nmi           = !pc_pin[2];

reg  [7:0] pll_ctrl, timer_ctrl, onesec;
reg        prog_run;
reg [13:0] prog_cnt;
reg [15:0] cyc;
reg        onesec_run;
reg [24:0] onesec_cnt;

wire [13:0] prog_period = 14'd1024 << (2'd3 - pll_ctrl[1:0]);
localparam [24:0] ONESEC = 25'd32_499_999;

always @(*) begin
	cpu_din = 8'h00;
	if (io_cs) begin
		case (a13[4:0])
			5'h00: cpu_din = (pa_ext & ~pa_ddr) | (pa_l & pa_ddr);
			5'h01: cpu_din = (pb_ext & ~pb_ddr) | (pb_l & pb_ddr);
			5'h02: cpu_din = (pc_ext & ~pc_ddr) | (pc_l & pc_ddr);
			5'h04: cpu_din = pa_ddr;
			5'h05: cpu_din = pb_ddr;
			5'h06: cpu_din = pc_ddr;
			5'h07: cpu_din = pll_ctrl;
			5'h08: cpu_din = timer_ctrl;
			5'h09: cpu_din = cyc[9:2];
			5'h12: cpu_din = onesec;
			default: cpu_din = 8'h00;
		endcase
	end
	else if (ram_cs) cpu_din = ram_q;
	else if (rom_cs) cpu_din = rom_byte;
end

reg pc3_d;
always @(posedge clk) begin
	cpu_reset_pulse <= 1'b0;
	if (reset) begin
		pa_l <= 0; pb_l <= 0; pc_l <= 0;
		pa_ddr <= 0; pb_ddr <= 0; pc_ddr <= 0;
		pll_ctrl <= 0; timer_ctrl <= 0; onesec <= 0;
		prog_run <= 0; prog_cnt <= 0; cyc <= 0;
		onesec_run <= 0; onesec_cnt <= 0;
		timer_irq <= 0; cpi_irq <= 0;
		cpu_hold <= 1'b1;
		pc3_d <= 1'b0;
		copy_busy <= 1'b0; copy_done <= 1'b0; copy_idx <= 9'd0;
	end else begin
		if (cen) begin
			cyc <= cyc + 1'd1;
			if (prog_run) begin
				if (prog_cnt >= prog_period - 1'd1) begin
					prog_cnt <= 0;
					timer_ctrl[7] <= 1'b1;
					if (timer_ctrl[5]) timer_irq <= 1'b1;
				end
				else prog_cnt <= prog_cnt + 1'd1;
			end
		end
		if (onesec_run && fw_loaded) begin
			if (onesec_cnt == ONESEC) begin
				onesec_cnt <= 0;
				onesec[6] <= 1'b1;
				if (onesec[4]) cpi_irq <= 1'b1;
			end
			else onesec_cnt <= onesec_cnt + 1'd1;
		end

		if (cpu_we && io_cs) begin
			case (a13[4:0])
				5'h00: pa_l <= cpu_dout;
				5'h01: pb_l <= cpu_dout;
				5'h02: pc_l <= cpu_dout;
				5'h04: pa_ddr <= cpu_dout & 8'hFE;
				5'h05: pb_ddr <= cpu_dout;
				5'h06: pc_ddr <= cpu_dout;
				5'h07: begin
					pll_ctrl <= (cpu_dout[1:0] == 2'd2) ? (cpu_dout | 8'h03) : cpu_dout;
					if (((cpu_dout[1:0] == 2'd2) ? (cpu_dout | 8'h03) : cpu_dout) != pll_ctrl) begin
						prog_run <= 1'b1;
						prog_cnt <= 0;
					end
				end
				5'h08: begin
					if (timer_ctrl[7] && !cpu_dout[7]) begin
						timer_irq <= 1'b0;
						timer_ctrl <= {1'b0, timer_ctrl[6], cpu_dout[5:0]};
					end
					else if (timer_ctrl[6] && !cpu_dout[6]) begin
						timer_irq <= 1'b0;
						timer_ctrl <= {timer_ctrl[7], 1'b0, cpu_dout[5:0]};
					end
					else timer_ctrl <= {timer_ctrl[7:6], cpu_dout[5:0]};
				end
				5'h12: begin
					if (onesec[6] && !cpu_dout[6]) cpi_irq <= 1'b0;
					onesec <= cpu_dout;
					onesec_run <= 1'b1;
				end
				default: ;
			endcase
		end

		pc3_d <= pc_pin[3];
		if (pc_pin[3] && !pc3_d) begin
			if (!copy_done) begin
				copy_busy <= 1'b1;
				copy_idx  <= 9'd0;
			end
			else cpu_reset_pulse <= 1'b1;
		end
		if (copy_busy) begin
			if (copy_idx == 9'd260) begin
				copy_busy <= 1'b0;
				copy_done <= 1'b1;
				cpu_hold  <= 1'b0;
			end
			else copy_idx <= copy_idx + 1'd1;
		end
	end
end

endmodule

`default_nettype wire
