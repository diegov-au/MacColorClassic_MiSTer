module spice_mem (
	input             clk,
	input             reset,

	input      [31:0] cpuAddr,
	input             _cpuAS,
	input             _cpuRW,
	input             _cpuUDS,
	input             _cpuLDS,
	input       [2:0] cpuFC,
	input      [15:0] cpuDataOut,

	output     [15:0] memDataOut,
	output            mem_dtack,
	output            selectMem,
	output            selectIO,
	output reg        overlay,

	input       [7:0] ram_config,
	input             ram_configured,
	input       [1:0] simm,

	input             vram_bram,
	input             vram_ack,
	input      [15:0] vram_q,
	input             icache_hit,
	output            cacheable,

	output reg  [1:0] busPhase,
	output            clk8,
	output            clk8_en_p,
	output            clk8_en_n,
	output            dioBusControl,

	input             flp_ok,
	input      [21:0] dskReadAddr,
	output            dskReadAck,
	output     [23:0] flp_addr,
	output reg        flp_guard,

	output reg [23:0] sdram_addr,
	output reg [15:0] sdram_din,
	output reg  [1:0] sdram_ds,
	output reg        sdram_we,
	output reg        sdram_oe,
	input             sdram_cpu_done,
	input      [15:0] sdram_cpu_dout
);

reg [1:0] busCycle;
always @(posedge clk) begin
	busPhase <= busPhase + 2'd1;
	if (busPhase == 2'd3) busCycle <= busCycle + 2'd1;
end

assign clk8      = !busPhase[1];
assign clk8_en_p = busPhase == 2'd3;
assign clk8_en_n = busPhase == 2'd1;

assign dioBusControl = busCycle == 2'b10;

reg [1:0] extra_slot_count;
reg       extra_slot_advance;
always @(posedge clk) begin
	if (clk8_en_n) extra_slot_advance <= busCycle == 2'b11;
	if (clk8_en_p && extra_slot_advance) extra_slot_count <= extra_slot_count + 2'd1;
	flp_guard <= extra_slot_count == 2'd0 && (busCycle == 2'b01 || busCycle == 2'b10) && flp_ok;
end
assign dskReadAck = busCycle == 2'b10 && extra_slot_count == 2'd0 && flp_ok;
assign flp_addr   = 24'h700000 + {3'b000, dskReadAddr[21:1]};

wire [23:0] a = cpuAddr[23:0];
wire cpu_space = cpuFC == 3'b111;

wire in_rom  = a[23:20] == 4'hA;
wire in_ram  = a[23:20] <  4'hA;
wire in_vram = a[23:20] == 4'hF && (a[19:18] == 2'b01 || a[19:18] == 2'b10);
assign selectIO = !_cpuAS && !cpu_space && a[23:20] == 4'hF && !in_vram;

wire [7:0] cfg      = ram_configured ? ram_config : 8'hC0;
wire [2:0] simm_2m  = (simm == 2'd3) ? 3'd4 : {1'b0, simm};
wire [2:0] cfg_2m   = (cfg[7:6] == 2'd3) ? 3'd4 : {1'b0, cfg[7:6]};
wire [2:0] mb_2m    = cfg[5] ? 3'd1 : 3'd2;
wire [2:0] a_2m     = a[23:21];
wire       ram_hi   = a_2m == 3'b100;
wire       mb_hit   = cfg[7:6] != 2'd3 && a_2m >= cfg_2m && a_2m < cfg_2m + mb_2m;
wire       simm_hit = cfg[7:6] != 2'd0 && a_2m < simm_2m;
wire       ram_lo   = mb_hit || simm_hit;
wire [2:0] mb_off_2m = a_2m - cfg_2m;
wire [23:0] ram_off  = ram_hi ? {3'b000, a[20:0]} :
                       mb_hit ? {mb_off_2m, a[20:0]} :
                                24'h400000 + a;

wire rom_read  = in_rom && _cpuRW;
wire ovl_read  = overlay && in_ram && _cpuRW;
wire ram_acc   = !overlay && in_ram && (ram_hi || ram_lo);
wire vram_blk  = !cpu_space && in_vram && vram_bram;
wire vram_acc  = in_vram && !vram_bram;
wire mem_op    = !cpu_space && (rom_read || ovl_read || ram_acc || vram_acc);
wire mem_nop   = !cpu_space && !mem_op && (in_rom || in_ram);

assign selectMem = !_cpuAS && (mem_op || mem_nop || vram_blk);
assign cacheable = !cpu_space && (rom_read || ovl_read || ram_acc);

always @(posedge clk) begin
	if (reset)                              overlay <= 1'b1;
	else if (!_cpuAS && rom_read && !cpu_space) overlay <= 1'b0;
end

wire [23:0] cpu_word =
	(rom_read || ovl_read) ? {5'b01100, a[19:1]} :
	vram_acc               ? {6'b011010, a[18:1]} :
	                         {1'b0, ram_off[23:1]};

always @(posedge clk) begin
	sdram_addr <= cpu_word;
	sdram_din  <= cpuDataOut;
	sdram_ds   <= {!_cpuUDS, !_cpuLDS};
	sdram_oe   <= !reset && !_cpuAS && mem_op &&  _cpuRW && !icache_hit;
	sdram_we   <= !reset && !_cpuAS && mem_op && !_cpuRW;
end

assign mem_dtack  = !_cpuAS && (sdram_cpu_done || mem_nop || (vram_blk && vram_ack));
assign memDataOut = vram_blk ? vram_q : sdram_cpu_dout;

endmodule
