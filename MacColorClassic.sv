//============================================================================
//  Macintosh Color Classic
//
//  Port to MiSTer. Descended from the Macintosh Classic core (and through it
//  the MacPlus core, Copyright (C) 2017-2019 Sorgelig) and the MacLC core.
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;

assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {UART_RTS, UART_TXD, UART_DTR} = {1'b0, 1'b1, 1'b0};

assign LED_DISK  = 0;
assign LED_POWER = 0;
assign BUTTONS   = 0;
assign VGA_SCALER= 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

wire [1:0] ar = status[8:7];
video_freak video_freak
(
	.*,
	.VGA_DE_IN(VGA_DE),
	.VGA_DE(),

	.ARX((!ar) ? 12'd4 : (ar - 1'd1)),
	.ARY((!ar) ? 12'd3 : 12'd0),
	.CROP_SIZE(0),
	.CROP_OFF(0),
	.SCALE(status[12:11])
);

`include "build_id.v"
localparam CONF_STR = {
	"MacColorClassic;UART115200;",
	"-;",
	"S2,DSK,Mount Floppy;",
	"O6,Floppy Write Protect,On,Off;",
	"-;",
	"SC0,VHD,Mount Internal HDD;",
	"SC1,VHD,Mount External SCSI;",
	"SC3,NVR,Mount PRAM;",
	"-;",
	"OJ,Resolution,Original,640x480;",
	"O78,Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"OBC,Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;",
	"-;",
	"O45,Memory,4MB,6MB,8MB,10MB;",
	"-;",
	"R0,Reset;",
	"v,1;",
	"V,v",`BUILD_DATE
};

wire clk_sys, clk_mem;
wire pll_locked;
wire clk8, clk8_en_p, clk8_en_n;

pll pll
(
	.refclk(CLK_50M),
	.outclk_0(clk_mem),
	.outclk_1(clk_sys),
	.locked(pll_locked)
);

localparam VDNUM = 4;

wire [31:0] status;
wire  [1:0] buttons;
wire [31:0] sd_lba[VDNUM];
wire  [VDNUM-1:0] sd_ack;
wire [12:0] sd_buff_addr;
wire [15:0] sd_buff_dout;
wire [15:0] sd_buff_din[VDNUM];
wire        sd_buff_wr;
wire  [VDNUM-1:0] img_mounted;
wire [63:0] img_size;
wire        img_readonly;

localparam SCSI_DEVS   = 2;
localparam SCSI_CD_DEV = SCSI_DEVS;
wire [31:0] scsi_sd_lba[SCSI_DEVS];
wire [15:0] scsi_sd_buff_din[SCSI_DEVS];
wire [SCSI_DEVS-1:0] scsi_sd_rd, scsi_sd_wr;
assign sd_lba[0] = scsi_sd_lba[0];
assign sd_lba[1] = scsi_sd_lba[1];
assign sd_buff_din[0] = scsi_sd_buff_din[0];
assign sd_buff_din[1] = scsi_sd_buff_din[1];
wire        ldr_sd_rd, wrb_sd_wr, ldr_busy;
wire [31:0] ldr_sd_lba, wrb_sd_lba;
wire [15:0] wrb_sd_buff_din;
assign sd_lba[2] = ldr_busy ? ldr_sd_lba : wrb_sd_lba;
assign sd_buff_din[2] = wrb_sd_buff_din;
wire        pram_sd_rd, pram_sd_wr;
wire  [5:0] scsi_blk_cnt[SCSI_DEVS];
wire  [5:0] sd_blk_cnt[VDNUM];
assign sd_blk_cnt[0] = scsi_blk_cnt[0];
assign sd_blk_cnt[1] = scsi_blk_cnt[1];
assign sd_blk_cnt[2] = 6'd0;
assign sd_blk_cnt[3] = 6'd0;

wire        ioctl_write;
reg         ioctl_wait = 0;
wire [24:0] ioctl_addr;
wire [15:0] ioctl_data;
wire        dio_download;
wire  [7:0] dio_index;

wire [10:0] ps2_key;
wire [24:0] ps2_mouse;
wire [32:0] TIMESTAMP;
wire [64:0] RTC;

hps_io #(.CONF_STR(CONF_STR), .VDNUM(VDNUM), .WIDE(1)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.buttons(buttons),
	.status(status),

	.sd_lba(sd_lba),
	.sd_blk_cnt(sd_blk_cnt),
	.sd_rd({pram_sd_rd, ldr_sd_rd, scsi_sd_rd}),
	.sd_wr({pram_sd_wr, wrb_sd_wr, scsi_sd_wr}),
	.sd_ack(sd_ack),

	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr),

	.img_mounted(img_mounted),
	.img_size(img_size),
	.img_readonly(img_readonly),

	.ioctl_download(dio_download),
	.ioctl_index(dio_index),
	.ioctl_wr(ioctl_write),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_data),
	.ioctl_wait(ioctl_wait),

	.TIMESTAMP(TIMESTAMP),
	.RTC(RTC),

	.ps2_key(ps2_key),
	.ps2_kbd_led_use(3'b001),
	.ps2_kbd_led_status(3'b000),

	.ps2_mouse(ps2_mouse)
);

reg rom_loaded = 1'b0;
reg cuda_fw_loaded = 1'b0;
always @(posedge clk_sys) begin
	reg old_dl = 0;
	old_dl <= dio_download;
	if (old_dl & ~dio_download & dio_index == 8'd0)   rom_loaded <= 1'b1;
	if (old_dl & ~dio_download & dio_index == 8'h40)  cuda_fw_loaded <= 1'b1;
end

wire cuda_reset = ~pll_locked || status[0] || buttons[1] || RESET;
wire cuda_hold, cuda_reset_pulse;
reg  cuda_rst_req = 1'b0;
wire pram_ready, pram_restart;
reg  pram_rst_req = 1'b0;

reg n_reset = 0;
always @(posedge clk_sys) begin
	reg [15:0] rst_cnt;
	if (cuda_reset_pulse) cuda_rst_req <= 1'b1;
	if (pram_restart) pram_rst_req <= 1'b1;
	if (clk8_en_p) begin
		if (~pll_locked || status[0] || buttons[1] || RESET || ~rom_loaded || cuda_hold || cuda_rst_req || pram_rst_req) begin
			cuda_rst_req <= 1'b0;
			pram_rst_req <= 1'b0;
			rst_cnt <= '1;
			n_reset <= 0;
		end
		else if (rst_cnt) rst_cnt <= rst_cnt - 1'd1;
		else n_reset <= 1;
	end
end

localparam VRAM_FULL = 1;
reg       mode640 = 1'b0;
reg [1:0] simm_size = 2'd0;
reg       ce_pix;
reg [9:0] hc;
reg [9:0] vc;
always @(posedge clk_sys) begin
	if (!n_reset) mode640 <= status[19] && VRAM_FULL;
	if (!n_reset) simm_size <= status[5:4];
	ce_pix <= mode640 ? 1'b1 : ~ce_pix;
	if (ce_pix) begin
		if (hc == (mode640 ? 10'd1023 : 10'd639)) begin
			hc <= 10'd0;
			vc <= (vc >= (mode640 ? 10'd524 : 10'd406)) ? 10'd0 : vc + 1'd1;
		end
		else hc <= hc + 1'd1;
	end
end
wire vblank = vc >= (mode640 ? 10'd480 : 10'd384);

wire [7:0] sv_r, sv_g, sv_b;
wire       sv_de, sv_hs, sv_vs;
reg        dbg_on = 1'b0;
reg  [7:0] dbg_r, dbg_g, dbg_b;
assign CLK_VIDEO = clk_sys;
assign CE_PIXEL  = ce_pix;
assign VGA_R  = dbg_on ? dbg_r : sv_r;
assign VGA_G  = dbg_on ? dbg_g : sv_g;
assign VGA_B  = dbg_on ? dbg_b : sv_b;
assign VGA_DE = sv_de;
assign VGA_HS = sv_hs;
assign VGA_VS = sv_vs;
assign VGA_F1 = 0;
assign VGA_SL = 0;

wire [7:0]  asc_sample_a, asc_sample_b;
wire [7:0]  asc_sa = asc_sample_a ^ 8'h80;
wire [7:0]  asc_sb = asc_sample_b ^ 8'h80;
wire [8:0]  asc_sum = {asc_sa[7], asc_sa} + {asc_sb[7], asc_sb};
wire [15:0] asc_mono = {asc_sum[8], asc_sum, 6'd0};
wire [7:0]  asc_vol;
reg  [8:0]  asc_gain;
always @(*) case (asc_vol[7:5])
	3'd0: asc_gain = 9'd0;    3'd1: asc_gain = 9'd32;  3'd2: asc_gain = 9'd46;  3'd3: asc_gain = 9'd64;
	3'd4: asc_gain = 9'd91;   3'd5: asc_gain = 9'd128; 3'd6: asc_gain = 9'd181; default: asc_gain = 9'd256;
endcase
wire signed [25:0] asc_prod = $signed(asc_mono) * $signed({1'b0, asc_gain});
reg  [15:0] asc_out = 16'd0;
always @(posedge clk_sys) asc_out <= asc_prod[23:8];
assign AUDIO_L = asc_out;
assign AUDIO_R = asc_out;
assign AUDIO_S = 1;
assign AUDIO_MIX = 0;

wire [31:0] cpuAddr;
wire [15:0] cpuDataOut;
wire [15:0] cpuDataIn;
wire  [2:0] cpuFC;
wire        _cpuAS, _cpuUDS, _cpuLDS, _cpuRW, _cpuVMA;
wire        _cpuDTACK, _cpuVPA, cpuBERR;
wire  [2:0] _cpuIPL;
wire        k_reset_n;
wire        E_rising, E_falling;

wire        dbg_clkena, dbg_decode, dbg_pmmu_busy, dbg_pmmu_fault, dbg_halted, dbg_walker;
wire [15:0] dbg_pmmu_fstat;
wire [31:0] dbg_pc, dbg_cacr, dbg_vbr, dbg_trap_vector;
wire [15:0] dbg_opcode;
wire [31:0] dbg_memaddr, dbg_exe_pc;
wire  [2:0] dbg_kfc;
wire        dbg_krw;

wire [31:0] cpu_early_addr;
wire        cpu_fetch, cpu_data, cpu_cache_inv, cpu_din_now;

tg68k030 cpu
(
	.clk        ( clk_sys       ),
	.reset      ( !n_reset      ),
	.phi1       ( clk8_en_p     ),
	.phi2       ( clk8_en_n     ),

	.dtack_n    ( _cpuDTACK     ),
	.vpa_n      ( _cpuVPA       ),
	.berr       ( cpuBERR       ),
	.ipl        ( _cpuIPL       ),
	.din        ( cpuDataIn     ),
	.dout       ( cpuDataOut    ),
	.addr       ( cpuAddr       ),
	.as_n       ( _cpuAS        ),
	.uds_n      ( _cpuUDS       ),
	.lds_n      ( _cpuLDS       ),
	.rw_n       ( _cpuRW        ),
	.fc         ( cpuFC         ),
	.reset_n    ( k_reset_n     ),

	.E          (               ),
	.E_PosClkEn ( E_falling     ),
	.E_NegClkEn ( E_rising      ),
	.vma_n      ( _cpuVMA       ),

	.walker_cycle   ( dbg_walker      ),
	.early_addr     ( cpu_early_addr  ),
	.fetch_cycle    ( cpu_fetch       ),
	.data_cycle     ( cpu_data        ),
	.cache_inv      ( cpu_cache_inv   ),
	.din_now        ( cpu_din_now     ),
	.dbg_clkena     ( dbg_clkena      ),
	.dbg_decode     ( dbg_decode      ),
	.dbg_pc         ( dbg_pc          ),
	.dbg_opcode     ( dbg_opcode      ),
	.dbg_pmmu_busy  ( dbg_pmmu_busy   ),
	.dbg_pmmu_fault ( dbg_pmmu_fault  ),
	.dbg_cacr       ( dbg_cacr        ),
	.dbg_vbr        ( dbg_vbr         ),
	.dbg_trap_vector( dbg_trap_vector ),
	.dbg_halted     ( dbg_halted      ),
	.dbg_pmmu_fstat ( dbg_pmmu_fstat  ),
	.dbg_memaddr    ( dbg_memaddr     ),
	.dbg_exe_pc     ( dbg_exe_pc      ),
	.dbg_kfc        ( dbg_kfc         ),
	.dbg_krw        ( dbg_krw         )
);

wire periph_reset = !n_reset || !k_reset_n;

wire [15:0] memDataOut;
wire        mem_dtack, selectMem, selectIO, overlay;
wire  [7:0] ram_config_out;
wire        ram_configured;
wire        dioBusControl;
wire  [1:0] busPhase;

wire [23:0] sdram_addr;
wire [15:0] sdram_din, sdram_cpu_dout;
wire  [1:0] sdram_ds;
wire        sdram_we, sdram_oe, sdram_cpu_done, sdram_dl_ack;

wire        flp_ok, dskReadAck, flp_guard;
wire [21:0] dskReadAddr;
wire [23:0] flp_addr;
wire [15:0] flp_word;
wire  [7:0] dskReadData;
reg         fm_req = 1'b0;
reg  [23:0] fm_addr;
reg  [15:0] fm_din;
wire        fm_ack;

reg  [18:0] dio_a;
reg  [15:0] dio_data;

wire [15:0] vram_q;
wire [18:0] vram_off  = cpuAddr[18:0] - 19'h40000;
wire        vram_win  = cpuAddr[23:0] >= 24'hF40000 && cpuAddr[23:0] < 24'hFC0000;
wire        vram_bram = vram_win && (mode640 ? (vram_off[18:10] < 9'd480 && vram_off[9:0] < 10'd640)
                                             : (vram_off < 19'h60000 && (VRAM_FULL || !vram_off[9])));
wire        vb_cyc    = !_cpuAS && cpuFC != 3'b111 && vram_bram;
wire  [1:0] vb_we     = (vb_cyc && !_cpuRW) ? {!_cpuUDS, !_cpuLDS} : 2'b00;
reg         vb_ack    = 1'b0;
always @(posedge clk_sys) vb_ack <= vb_cyc;

wire        ic_hit, dc_hit, mem_cacheable;
wire [15:0] ic_data, dc_data;
wire        cache_hit = ic_hit || dc_hit;
assign      cpu_din_now = (cache_hit || (vb_cyc && vb_ack));
wire        ic_slot = cpuAddr[31:24] >= 8'hF1 && cpuAddr[31:24] <= 8'hFE;
`ifdef VERILATOR
reg         sim_cache_flush /*verilator public_flat_rw*/ = 1'b0;
`else
wire        sim_cache_flush = 1'b0;
`endif
reg  [10:0] ic_map = 0, ic_map_d = 0;
always @(posedge clk_sys) begin
	ic_map   <= {overlay, ram_configured, ram_config_out, dio_download};
	ic_map_d <= ic_map;
end

icache_030 icache
(
	.clk        ( clk_sys                    ),
	.reset      ( !n_reset                   ),
	.flush      ( cpu_cache_inv || ic_map != ic_map_d || sim_cache_flush ),
	.enable     ( dbg_cacr[0] ),
	.freeze     ( dbg_cacr[1]                ),
	.early_addr ( cpu_early_addr[23:0]       ),
	.bus_addr   ( cpuAddr[23:0]              ),
	.as_n       ( _cpuAS                     ),
	.rw         ( _cpuRW                     ),
	.fetch      ( cpu_fetch                  ),
	.cacheable  ( mem_cacheable && !ic_slot  ),
	.mem_din    ( sdram_cpu_dout             ),
	.wdata      ( cpuDataOut                 ),
	.wbe        ( {!_cpuUDS, !_cpuLDS}       ),
	.hit        ( ic_hit                     ),
	.hit_data   ( ic_data                    )
);

icache_030 #(.WRITE_UPDATE(1)) dcache
(
	.clk        ( clk_sys                    ),
	.reset      ( !n_reset                   ),
	.flush      ( cpu_cache_inv || ic_map != ic_map_d || sim_cache_flush ),
	.enable     ( dbg_cacr[8] ),
	.freeze     ( dbg_cacr[9]                ),
	.early_addr ( cpu_early_addr[23:0]       ),
	.bus_addr   ( cpuAddr[23:0]              ),
	.as_n       ( _cpuAS                     ),
	.rw         ( _cpuRW                     ),
	.fetch      ( cpu_data                   ),
	.cacheable  ( mem_cacheable && !ic_slot  ),
	.mem_din    ( sdram_cpu_dout             ),
	.wdata      ( cpuDataOut                 ),
	.wbe        ( {!_cpuUDS, !_cpuLDS}       ),
	.hit        ( dc_hit                     ),
	.hit_data   ( dc_data                    )
);

spice_mem mem
(
	.clk            ( clk_sys         ),
	.reset          ( !n_reset        ),

	.cpuAddr        ( cpuAddr         ),
	._cpuAS         ( _cpuAS          ),
	._cpuRW         ( _cpuRW          ),
	._cpuUDS        ( _cpuUDS         ),
	._cpuLDS        ( _cpuLDS         ),
	.cpuFC          ( cpuFC           ),
	.cpuDataOut     ( cpuDataOut      ),

	.memDataOut     ( memDataOut      ),
	.mem_dtack      ( mem_dtack       ),
	.selectMem      ( selectMem       ),
	.selectIO       ( selectIO        ),
	.overlay        ( overlay         ),

	.ram_config     ( ram_config_out  ),
	.ram_configured ( ram_configured  ),
	.simm           ( simm_size       ),

	.vram_bram      ( vram_bram       ),
	.vram_ack       ( vb_ack          ),
	.vram_q         ( vram_q          ),
	.icache_hit     ( cache_hit       ),
	.cacheable      ( mem_cacheable   ),

	.busPhase       ( busPhase        ),
	.clk8           ( clk8            ),
	.clk8_en_p      ( clk8_en_p       ),
	.clk8_en_n      ( clk8_en_n       ),
	.dioBusControl  ( dioBusControl   ),

	.flp_ok         ( flp_ok          ),
	.dskReadAddr    ( dskReadAddr     ),
	.dskReadAck     ( dskReadAck      ),
	.flp_addr       ( flp_addr        ),
	.flp_guard      ( flp_guard       ),

	.sdram_addr     ( sdram_addr      ),
	.sdram_din      ( sdram_din       ),
	.sdram_ds       ( sdram_ds        ),
	.sdram_we       ( sdram_we        ),
	.sdram_oe       ( sdram_oe        ),
	.sdram_cpu_done ( sdram_cpu_done  ),
	.sdram_cpu_dout ( sdram_cpu_dout  )
);

wire        cuda_fw_wr   = ioctl_write && dio_index == 8'h40;
wire [15:0] cuda_fw_data = {ioctl_data[7:0], ioctl_data[15:8]};

reg dl_ack_d = 0;
always @(posedge clk_sys) begin
	dl_ack_d <= sdram_dl_ack;
	if (ioctl_write && dio_index != 8'h40) begin
		dio_data <= {ioctl_data[7:0], ioctl_data[15:8]};
		dio_a    <= ioctl_addr[19:1];
		ioctl_wait <= 1;
	end
	else if (ioctl_wait && (dio_index != 8'd0 || (sdram_dl_ack && !dl_ack_d)))
		ioctl_wait <= 0;
end

reg        dl_req_q = 0, dl_slot_q = 0;
reg [23:0] dl_addr_q;
reg [15:0] dl_din_q;
always @(posedge clk_sys) begin
	dl_req_q  <= ioctl_wait && dio_index == 8'd0 && dio_download;
	dl_slot_q <= dioBusControl;
	dl_addr_q <= {5'b01100, dio_a};
	dl_din_q  <= dio_data;
end

assign SDRAM_CKE = 1;

sdram sdram
(
	.init           ( !pll_locked              ),
	.clk_64         ( clk_mem                  ),
	.clk_8          ( clk8                     ),

	.sd_clk         ( SDRAM_CLK                ),
	.sd_data        ( SDRAM_DQ                 ),
	.sd_addr        ( SDRAM_A                  ),
	.sd_dqm         ( {SDRAM_DQMH, SDRAM_DQML} ),
	.sd_cs          ( SDRAM_nCS                ),
	.sd_ba          ( SDRAM_BA                 ),
	.sd_we          ( SDRAM_nWE                ),
	.sd_ras         ( SDRAM_nRAS               ),
	.sd_cas         ( SDRAM_nCAS               ),

	.din            ( sdram_din                ),
	.addr           ( sdram_addr               ),
	.ds             ( sdram_ds                 ),
	.we             ( sdram_we                 ),
	.oe             ( sdram_oe                 ),
	.dout           ( flp_word                 ),
	.cpu_done       ( sdram_cpu_done           ),
	.cpu_dout       ( sdram_cpu_dout           ),

	.dl_req         ( dl_req_q                 ),
	.dl_slot        ( dl_slot_q                ),
	.dl_addr        ( dl_addr_q                ),
	.dl_din         ( dl_din_q                 ),
	.dl_ack         ( sdram_dl_ack             ),

	.flp_win        ( dskReadAck               ),
	.flp_addr       ( flp_addr                 ),
	.flp_guard      ( flp_guard                ),
	.eth_req        ( fm_req                   ),
	.eth_we         ( 1'b1                     ),
	.eth_addr       ( fm_addr                  ),
	.eth_din        ( fm_din                   ),
	.eth_ack        ( fm_ack                   ),
	.eth_dout       (                          )
);

reg       flp_odd_q;
always @(posedge clk_sys) flp_odd_q <= dskReadAddr[0];
assign dskReadData = flp_odd_q ? flp_word[7:0] : flp_word[15:8];

wire [23:0] a24 = cpuAddr[23:0];
wire selectVIA  = selectIO && a24[19:13] == 7'h00;
wire selectPVIA = selectIO && a24[19:13] == 7'h13;
wire selectASC  = selectIO && a24[19:13] == 7'h0A;
wire selectSCC  = selectIO && a24[19:13] == 7'h02;
wire selectCLUT = selectIO && a24[19:13] == 7'h12;
wire scsi_regs  = selectIO && a24[19:13] == 7'h08;
wire scsi_dma   = selectIO && (a24[19:13] == 7'h09 || a24[19:13] == 7'h03);
wire selectSCSI = scsi_regs || scsi_dma;
wire selectSWIM = selectIO && a24[19:13] == 7'h0B;

wire fc7        = cpuFC == 3'b111;
wire fc7_iack   = fc7 && a24[19:16] == 4'hF;
wire slot_space = cpuAddr[31:24] >= 8'hF1 && cpuAddr[31:24] <= 8'hFE;
wire bus_fault  = !_cpuAS && ((fc7 && !fc7_iack) || slot_space);
wire unmapped   = !_cpuAS && !fc7 && !slot_space && !selectMem && !selectIO;

wire scsi_bus_hold;
wire pdma_word = scsi_dma && !_cpuUDS && !_cpuLDS;
reg  pd_done = 0;
reg  [7:0] pd_hi, pd_lo;
assign cpuBERR   = bus_fault;
assign _cpuVPA   = !((!_cpuAS && fc7_iack) || (selectIO && !slot_space && !selectSCSI));
assign _cpuDTACK = !(cache_hit || mem_dtack || unmapped ||
                     (!_cpuAS && selectSCSI && (pdma_word ? pd_done : !scsi_bus_hold)));

wire [7:0] via_do, via_pa_o, via_pa_oe, via_pb_o, via_pb_oe;
wire       via_irq;
wire       via_cb2_o, via_cb2_t;
wire       cuda_treq, cuda_via_clock, cuda_via_data, cuda_nmi;
wire       cuda_adb_low, cuda_scl, cuda_sda, dfac_sda_o;
wire [7:0] pram_ext_addr, pram_ext_wdata, pram_ext_q;
wire       pram_ext_we, pram_ext_ready, pram_loaded, pram_written;
wire [15:0] cuda_dbg_addr;
wire       cuda_running;
wire [7:0] cuda_dbg_a2;
wire [3:0] via_dbg_cnt;
wire [7:0] via_dbg_acr, via_dbg_sr;
wire [6:0] via_dbg_ifr, via_dbg_ier;
wire       via_dbg_done;

wire [31:0] mac_secs;
wire        mac_seeded;
mac_clock mac_clock
(
	.clk        ( clk_sys    ),
	.clear      ( ~pll_locked ),
	.timestamp  ( TIMESTAMP  ),
	.rtc_bcd    ( RTC        ),
	.secs       ( mac_secs   ),
	.seeded     ( mac_seeded )
);

wire       adb_dev_line;
wire       adb_line = !cuda_adb_low && adb_dev_line;
wire [7:0] adb_dbg_state;

adb_device adb_dev
(
	.clk        ( clk_sys         ),
	.reset      ( !n_reset        ),
	.host_line  ( !cuda_adb_low   ),
	.dev_line   ( adb_dev_line    ),
	.ps2_key    ( ps2_key         ),
	.ps2_mouse  ( ps2_mouse       ),
	.dbg_state  ( adb_dbg_state   )
);

cuda cuda
(
	.clk            ( clk_sys          ),
	.reset          ( cuda_reset       ),

	.fw_wr          ( cuda_fw_wr       ),
	.fw_addr        ( ioctl_addr[12:1] ),
	.fw_data        ( cuda_fw_data     ),
	.fw_loaded      ( cuda_fw_loaded   ),

	.ext_we         ( pram_ext_we      ),
	.ext_addr       ( pram_ext_addr    ),
	.ext_wdata      ( pram_ext_wdata   ),
	.ext_ready      ( pram_ext_ready   ),
	.ext_q          ( pram_ext_q       ),
	.pram_valid     ( pram_loaded      ),
	.run            ( pram_ready && mac_seeded ),
	.pram_written   ( pram_written     ),
	.mac_seconds    ( mac_secs         ),

	.via_tip        ( via_pb_oe[5] ? via_pb_o[5] : 1'b1 ),
	.via_byteack    ( via_pb_oe[4] ? via_pb_o[4] : 1'b1 ),
	.via_cb2_o      ( via_cb2_o        ),
	.via_cb2_oe     ( via_cb2_t        ),
	.treq           ( cuda_treq        ),
	.via_clock      ( cuda_via_clock   ),
	.via_data       ( cuda_via_data    ),

	.adb_line       ( adb_line         ),
	.adb_drive_low  ( cuda_adb_low     ),

	.iic_scl        ( cuda_scl         ),
	.iic_sda        ( cuda_sda         ),
	.iic_sda_in     ( cuda_sda && dfac_sda_o ),

	.cpu_hold       ( cuda_hold        ),
	.cpu_reset_pulse( cuda_reset_pulse ),
	.nmi            ( cuda_nmi         ),

	.dbg_addr       ( cuda_dbg_addr    ),
	.dbg_running    ( cuda_running     ),
	.dbg_a2         ( cuda_dbg_a2      )
);

pram_nvr pram_nvr
(
	.clk          ( clk_sys          ),
	.reset        ( !pll_locked      ),
	.rom_loaded   ( rom_loaded       ),
	.mac_reset    ( !n_reset         ),
	.img_mounted  ( img_mounted[3]   ),
	.img_size     ( img_size         ),
	.sd_lba       ( sd_lba[3]        ),
	.sd_rd        ( pram_sd_rd       ),
	.sd_wr        ( pram_sd_wr       ),
	.sd_ack       ( sd_ack[3]        ),
	.sd_buff_addr ( sd_buff_addr[7:0] ),
	.sd_buff_dout ( sd_buff_dout     ),
	.sd_buff_din  ( sd_buff_din[3]   ),
	.sd_buff_wr   ( sd_buff_wr       ),
	.osd_status   ( OSD_STATUS       ),
	.save_req     ( 1'b0             ),
	.ext_addr     ( pram_ext_addr    ),
	.ext_we       ( pram_ext_we      ),
	.ext_wdata    ( pram_ext_wdata   ),
	.ext_ready    ( pram_ext_ready   ),
	.ext_q        ( pram_ext_q       ),
	.pram_wr      ( pram_written     ),
	.ready        ( pram_ready       ),
	.restart      ( pram_restart     ),
	.loaded       ( pram_loaded      )
);

wire [7:0] dfac_reg_addr, dfac_reg_data;
wire       dfac_reg_wr;

dfac2 dfac
(
	.clk        ( clk_sys          ),
	.reset      ( cuda_reset       ),
	.scl        ( cuda_scl         ),
	.sda        ( cuda_sda && dfac_sda_o ),
	.sda_o      ( dfac_sda_o       ),
	.reg_addr   ( dfac_reg_addr    ),
	.reg_data   ( dfac_reg_data    ),
	.reg_wr     ( dfac_reg_wr      )
);

via6522 via1
(
	.clock      ( clk_sys       ),
	.rising     ( E_rising      ),
	.falling    ( E_falling     ),
	.reset      ( periph_reset  ),

	.addr       ( a24[12:9]     ),
	.wen        ( selectVIA && !_cpuVMA && !_cpuRW ),
	.ren        ( selectVIA && !_cpuVMA &&  _cpuRW ),
	.data_in    ( cpuDataOut[15:8] ),
	.data_out   ( via_do        ),

	.phi2_ref   (               ),

	.port_a_o   ( via_pa_o      ),
	.port_a_t   ( via_pa_oe     ),
	.port_a_i   ( (via_pa_o & via_pa_oe) | (8'h82 & ~via_pa_oe) ),

	.port_b_o   ( via_pb_o      ),
	.port_b_t   ( via_pb_oe     ),
	.port_b_i   ( (via_pb_o & via_pb_oe) | ({4'b0000, cuda_treq, 3'b000} & ~via_pb_oe) ),

	.ca1_i      ( vblank        ),
	.ca2_o      (               ),
	.ca2_i      ( 1'b0          ),
	.ca2_t      (               ),

	.cb1_o      (               ),
	.cb1_i      ( cuda_via_clock ),
	.cb1_t      (               ),

	.cb2_o      ( via_cb2_o     ),
	.cb2_i      ( cuda_via_data ),
	.cb2_t      ( via_cb2_t     ),

	.irq        ( via_irq       ),

	.dbg_ext_cnt ( via_dbg_cnt  ),
	.dbg_acr     ( via_dbg_acr  ),
	.dbg_ifr     ( via_dbg_ifr  ),
	.dbg_ier     ( via_dbg_ier  ),
	.dbg_sr      ( via_dbg_sr   ),
	.dbg_sr_done ( via_dbg_done )
);

wire [7:0] scc_do;
wire       scc_irq_n;

scc scc
(
	.clk      ( clk_sys          ),
	.cep      ( clk8_en_p        ),
	.cen      ( clk8_en_n        ),
	.reset_hw ( periph_reset     ),
	.cs       ( selectSCC && !_cpuAS && (!_cpuUDS || !_cpuLDS) ),
	.we       ( !_cpuRW          ),
	.rs       ( a24[2:1]         ),
	.wdata    ( cpuDataOut[15:8] ),
	.rdata    ( scc_do           ),
	._irq     ( scc_irq_n        ),
	.rxd      ( 1'b1             ),
	.txd      (                  ),
	.cts      ( 1'b1             ),
	.rts      (                  ),
	.dcd_a    ( 1'b1             ),
	.dcd_b    ( 1'b1             ),
	.wreq     (                  )
);

wire [7:0] scsi_do;
wire       scsi_dreq;
wire       scsi_strobe = !_cpuAS && (!_cpuUDS || !_cpuLDS);
reg  [2:0] pd_st = 0;
reg        pd_strobe = 0, pd_second = 0;
reg  [3:0] pd_cnt;
always @(posedge clk_sys) begin
	if (!n_reset || _cpuAS || !pdma_word) begin
		pd_st <= 0; pd_strobe <= 0; pd_second <= 0; pd_done <= 0; pd_cnt <= 0;
	end
	else case (pd_st)
		3'd0: begin pd_strobe <= 1; pd_cnt <= 0; pd_st <= 3'd1; end
		3'd1: if (!scsi_bus_hold) begin
			pd_cnt <= pd_cnt + 1'd1;
			if (pd_cnt == 4'd2) begin pd_hi <= scsi_do; pd_strobe <= 0; pd_cnt <= 0; pd_st <= 3'd2; end
		end
		3'd2: begin
			pd_cnt <= pd_cnt + 1'd1;
			if (pd_cnt == 4'd12) begin pd_second <= 1; pd_strobe <= 1; pd_cnt <= 0; pd_st <= 3'd3; end
		end
		3'd3: if (!scsi_bus_hold) begin
			pd_cnt <= pd_cnt + 1'd1;
			if (pd_cnt == 4'd2) begin pd_lo <= scsi_do; pd_strobe <= 0; pd_st <= 3'd4; end
		end
		default: pd_done <= 1;
	endcase
end
wire scsi_ior = pdma_word ? (pd_strobe &&  _cpuRW) : (scsi_strobe &&  _cpuRW);
wire scsi_iow = pdma_word ? (pd_strobe && !_cpuRW) : (scsi_strobe && !_cpuRW);

ncr5380 #(.DEVS(SCSI_DEVS), .CD_DEV(SCSI_CD_DEV)) scsi
(
	.clk             ( clk_sys          ),
	.reset           ( periph_reset     ),
	.bus_cs          ( selectSCSI       ),
	.bus_rs          ( scsi_dma ? (_cpuRW ? 3'd6 : 3'd0) : a24[6:4] ),
	.ior             ( scsi_ior         ),
	.iow             ( scsi_iow         ),
	.dack            ( scsi_dma || a24[9] ),
	.dreq            ( scsi_dreq        ),
	.wdata           ( (pdma_word && pd_second) ? cpuDataOut[7:0] : cpuDataOut[15:8] ),
	.rdata           ( scsi_do          ),
	.img_mounted     ( img_mounted[1:0] ),
	.img_size        ( img_size[40:9]   ),
	.io_lba          ( scsi_sd_lba      ),
	.io_rd           ( scsi_sd_rd       ),
	.io_wr           ( scsi_sd_wr       ),
	.io_blk_cnt      ( scsi_blk_cnt     ),
	.wr_batch        ( 1'b1             ),
	.io_ack          ( sd_ack[1:0]      ),
	.sd_buff_addr    ( sd_buff_addr[7:0]  ),
	.sd_buff_addr_hi ( sd_buff_addr[12:8] ),
	.sd_buff_dout    ( sd_buff_dout     ),
	.sd_buff_din     ( scsi_sd_buff_din ),
	.sd_buff_wr      ( sd_buff_wr       ),
	.cd_enable       ( 1'b0             ),
	.cd_snd_l        (                  ),
	.cd_snd_r        (                  ),
	.bus_hold        ( scsi_bus_hold    )
);

wire [7:0] swim_do;
wire       flp_eject;
wire [21:0] wc_wr_addr, wc_addr;
wire [15:0] wc_wr_data, wc_buf_data;
wire        wc_wr_req, wc_wr_ack, wc_done, wc_buf_wr;
wire  [7:0] wc_buf_addr;
wire [21:0] ldr_wr_addr;
wire [15:0] ldr_wr_data;
wire        ldr_wr_req, ldr_wr_ack, ldr_done, ldr_readonly, wrb_busy;
wire [63:0] ldr_size;

reg dsk_ds = 0, dsk_ss = 0;
reg dsk_mfm = 0, dsk_hd = 0;

localparam [25:0] DSK_EMPTY_CY = 26'h3FFFFFF;
reg [25:0] dsk_empty_cy = DSK_EMPTY_CY;
reg        dsk_swap = 1'b0;
wire dsk_empty = dsk_empty_cy != DSK_EMPTY_CY;
wire dsk_ins   = !dsk_empty && (dsk_ds || dsk_ss || dsk_mfm);

always @(posedge clk_sys) begin
	if (img_mounted[2] && img_size != 0) begin
		dsk_ds <= 1'b0; dsk_ss <= 1'b0; dsk_mfm <= 1'b0; dsk_hd <= 1'b0;
		dsk_swap <= dsk_ds || dsk_ss || dsk_mfm;
		if (dsk_ds || dsk_ss || dsk_mfm) dsk_empty_cy <= 26'd0;
	end
	else if (ldr_busy && dsk_swap)
		dsk_empty_cy <= 26'd0;
	else if (dsk_empty_cy != DSK_EMPTY_CY)
		dsk_empty_cy <= dsk_empty_cy + 26'd1;

	if (ldr_done) begin
		dsk_ds  <= ldr_size == 64'd819200;
		dsk_ss  <= ldr_size == 64'd409600;
		dsk_mfm <= ldr_size == 64'd737280 || ldr_size == 64'd1474560;
		dsk_hd  <= ldr_size == 64'd1474560;
	end

	if (flp_eject) begin
		dsk_ds <= 1'b0; dsk_ss <= 1'b0; dsk_mfm <= 1'b0; dsk_hd <= 1'b0;
	end
end

assign flp_ok = dsk_ins && !ldr_busy && !dio_download;

wire flp_wp = !status[6] || ldr_readonly;

swim2 swim
(
	.clk          ( clk_sys          ),
	.cep          ( clk8_en_p        ),
	.cen          ( clk8_en_n        ),
	.reset        ( periph_reset     ),
	.strobe       ( selectSWIM && !_cpuVMA && E_falling ),
	.we           ( !_cpuRW          ),
	.reg_sel      ( a24[11:9]        ),
	.wdata        ( _cpuUDS ? cpuDataOut[7:0] : cpuDataOut[15:8] ),
	.rdata        ( swim_do          ),
	.hdsel        ( via_pa_o[5]      ),

	.insertDisk   ( dsk_ins          ),
	.diskSides    ( dsk_ds           ),
	.diskMFM      ( dsk_mfm          ),
	.diskHD       ( dsk_hd           ),
	.writeProtect ( flp_wp           ),
	.diskEject    ( flp_eject        ),
	.diskMotor    (                  ),
	.diskAct      (                  ),

	.dskReadAddr  ( dskReadAddr      ),
	.dskReadAck   ( dskReadAck       ),
	.dskReadData  ( dskReadData      ),

	.wrSdAddr     ( wc_wr_addr       ),
	.wrSdData     ( wc_wr_data       ),
	.wrSdReq      ( wc_wr_req        ),
	.wrSdAck      ( wc_wr_ack        ),
	.wrCommitDone ( wc_done          ),
	.wrCommitAddr ( wc_addr          ),
	.wrSdBufAddr  ( wc_buf_addr      ),
	.wrSdBufData  ( wc_buf_data      ),
	.wrSdBufWr    ( wc_buf_wr        )
);

floppy_loader flp_loader
(
	.clk_sys          ( clk_sys          ),
	.reset            ( !pll_locked      ),
	.img_mounted      ( img_mounted[2]   ),
	.img_size         ( img_size         ),
	.img_readonly     ( img_readonly     ),
	.sd_lba           ( ldr_sd_lba       ),
	.sd_rd            ( ldr_sd_rd        ),
	.sd_ack           ( sd_ack[2]        ),
	.sd_buff_addr     ( sd_buff_addr[7:0] ),
	.sd_buff_dout     ( sd_buff_dout     ),
	.sd_buff_wr       ( sd_buff_wr       ),
	.wr_addr          ( ldr_wr_addr      ),
	.wr_data          ( ldr_wr_data      ),
	.wr_req           ( ldr_wr_req       ),
	.wr_ack           ( ldr_wr_ack       ),
	.done             ( ldr_done         ),
	.loaded_size      ( ldr_size         ),
	.readonly_latched ( ldr_readonly     ),
	.busy             ( ldr_busy         )
);

floppy_sd_writer flp_writer
(
	.clk             ( clk_sys          ),
	.reset           ( !pll_locked      ),
	.img_mounted     ( img_mounted[2]   ),
	.commit_done     ( wc_done          ),
	.commit_addr     ( wc_addr          ),
	.commit_buf_wr   ( wc_buf_wr        ),
	.commit_buf_addr ( wc_buf_addr      ),
	.commit_buf_data ( wc_buf_data      ),
	.readonly        ( ldr_readonly     ),
	.loader_busy     ( ldr_busy         ),
	.size_blocks     ( ldr_size[21:9]   ),
	.sd_lba          ( wrb_sd_lba       ),
	.sd_wr           ( wrb_sd_wr        ),
	.sd_ack          ( sd_ack[2]        ),
	.sd_buff_addr    ( sd_buff_addr[7:0] ),
	.sd_buff_din     ( wrb_sd_buff_din  ),
	.busy            ( wrb_busy         )
);

assign LED_USER = dio_download || ldr_busy || wrb_busy;

reg  fm_own = 1'b0;
reg  fm_wait = 1'b0;
wire fm_done = fm_req && fm_ack;
assign ldr_wr_ack = fm_done && !fm_own;
assign wc_wr_ack  = fm_done &&  fm_own;
always @(posedge clk_sys) begin
	if (!pll_locked) begin
		fm_req  <= 1'b0;
		fm_wait <= 1'b0;
	end
	else if (fm_req) begin
		if (fm_ack) begin fm_req <= 1'b0; fm_wait <= 1'b1; end
	end
	else if (fm_wait) begin
		if (!fm_ack) fm_wait <= 1'b0;
	end
	else if (ldr_wr_req || wc_wr_req) begin
		fm_own  <= !ldr_wr_req;
		fm_addr <= 24'h700000 + {3'b000, ldr_wr_req ? ldr_wr_addr[21:1] : wc_wr_addr[21:1]};
		fm_din  <= ldr_wr_req ? ldr_wr_data : wc_wr_data;
		fm_req  <= 1'b1;
	end
end

wire [7:0] asc_do;
wire       asc_irq;

asc_sonora asc
(
	.clk         ( clk_sys          ),
	.reset       ( periph_reset     ),
	.strobe      ( selectASC && !_cpuVMA && E_falling ),
	.we          ( !_cpuRW          ),
	.addr        ( a24[12:0]        ),
	.uds         ( !_cpuUDS         ),
	.lds         ( !_cpuLDS         ),
	.din         ( cpuDataOut       ),
	.dout        ( asc_do           ),
	.irq         ( asc_irq          ),
	.sample_l    ( asc_sample_a     ),
	.sample_r    ( asc_sample_b     ),
	.sample_tick (                  ),
	.volume      ( asc_vol          )
);

wire [7:0]  pvia_video_cfg;
wire [7:0]  clut_do;

wire [12:0] clut_boff = {a24[12:1], _cpuUDS && !_cpuLDS};

spice_video #(.FULL(VRAM_FULL)) video
(
	.clk         ( clk_sys          ),
	.reset       ( periph_reset     ),
	.ce_pix      ( ce_pix           ),
	.hc          ( hc               ),
	.vc          ( vc               ),
	.mode640     ( mode640          ),
	.depth       ( pvia_video_cfg[2:0] ),
	.vram_off    ( vram_off         ),
	.vram_wdata  ( cpuDataOut       ),
	.vram_we     ( vb_we            ),
	.vram_q      ( vram_q           ),
	.clut_strobe ( selectCLUT && !_cpuVMA && E_falling ),
	.clut_we     ( !_cpuRW          ),
	.clut_off    ( clut_boff[1:0]   ),
	.clut_sel    ( clut_boff[12:2] == 11'd0 ),
	.clut_wdata  ( _cpuUDS ? cpuDataOut[7:0] : cpuDataOut[15:8] ),
	.clut_rdata  ( clut_do          ),
	.r           ( sv_r             ),
	.g           ( sv_g             ),
	.b           ( sv_b             ),
	.de          ( sv_de            ),
	.hs          ( sv_hs            ),
	.vs          ( sv_vs            )
);

localparam DEBUG_STRIP = 1'b0;

reg  [31:0] dbg_icount = 0;
reg         dbg_dec_d = 0, dbg_vram_seen = 0, dbg_clut_seen = 0, dbg_fault_seen = 0;
reg  [63:0] dbg_sadmac = 0;
reg  [79:0] dbg_ill = 0;
reg         dbg_ill_seen = 0;
reg  [31:0] dbg_pc_d = 0;
reg  [63:0] dbg_fail = 0;
reg  [63:0] dbg_berr = 0;
reg  [15:0] dbg_berr_cnt = 0;
reg         dbg_fail_seen = 0, dbg_berr_d = 0;
reg   [1:0] dbg_scsi_mnt = 0;
reg  [15:0] dbg_scsi_rds = 0;
reg  [31:0] dbg_scsi_lba = 0;
reg         dbg_scsi_rd_d = 0;
reg  [31:0] dbg_clk_rel = 0;
reg         dbg_hold_d = 1;
always @(posedge clk_sys) begin
	dbg_dec_d <= dbg_decode;
	if (!n_reset) dbg_icount <= 0;
	else if (dbg_decode && !dbg_dec_d) dbg_icount <= dbg_icount + 1'd1;
	if (!n_reset) begin dbg_ill_seen <= 1'b0; dbg_ill <= 0; end
	else if (!dbg_ill_seen && dbg_trap_vector == 32'h10) begin
		dbg_ill_seen <= 1'b1;
		dbg_ill <= {dbg_pc, dbg_opcode, dbg_icount};
	end
	dbg_pc_d <= dbg_pc;
	dbg_berr_d <= cpuBERR;
	if (!n_reset) begin
		dbg_fail_seen <= 1'b0; dbg_fail <= 0; dbg_berr <= 0; dbg_berr_cnt <= 0;
	end
	else if (!dbg_fail_seen) begin
		if (dbg_pc[31:8] == 24'h40A4A6 && dbg_pc != dbg_pc_d) begin
			dbg_fail_seen <= 1'b1;
			dbg_fail <= {dbg_pc_d, dbg_icount};
		end
		if (cpuBERR && !dbg_berr_d) begin
			dbg_berr <= {cpuAddr, dbg_pc};
			dbg_berr_cnt <= dbg_berr_cnt + 1'd1;
		end
	end
	if (img_mounted[0]) dbg_scsi_mnt[0] <= |img_size;
	if (img_mounted[1]) dbg_scsi_mnt[1] <= |img_size;
	dbg_scsi_rd_d <= scsi_sd_rd[0];
	dbg_hold_d <= cuda_hold;
	if (dbg_hold_d && !cuda_hold) dbg_clk_rel <= mac_secs;
	if (scsi_sd_rd[0] && !dbg_scsi_rd_d) begin
		dbg_scsi_rds <= dbg_scsi_rds + 1'd1;
		dbg_scsi_lba <= scsi_sd_lba[0];
	end
	if (vb_we != 2'b00) dbg_vram_seen <= 1'b1;
	if (selectCLUT && !_cpuVMA && E_falling && !_cpuRW) dbg_clut_seen <= 1'b1;
	if (dbg_pmmu_fault) dbg_fault_seen <= 1'b1;
	if (!_cpuAS && !_cpuRW && !_cpuUDS && !_cpuLDS && !fc7 && cpuAddr[31:4] == 28'h00000C4)
		case (cpuAddr[3:1])
			3'd4: dbg_sadmac[31:16] <= cpuDataOut;
			3'd5: dbg_sadmac[15:0]  <= cpuDataOut;
			3'd6: dbg_sadmac[63:48] <= cpuDataOut;
			3'd7: dbg_sadmac[47:32] <= cpuDataOut;
			default: ;
		endcase
end

reg  [24:0] dk_tick = 0;
reg  [31:0] dk_rd = 0, dk_wr = 0, dk_hold = 0, dk_hrd = 0, dk_hwr = 0, dk_hreq = 0;
reg  [95:0] dk_l10 = 0, dk_l11 = 0;
reg         dk_as_d = 1'b1, dk_dma_d = 1'b0, dk_word_d = 1'b0, dk_rw_d = 1'b1;
reg         dk_rq_d = 1'b0, dk_wq_d = 1'b0, dk_rd_op = 1'b0;
wire        dk_rq = |scsi_sd_rd, dk_wq = |scsi_sd_wr, dk_ack = |sd_ack[1:0];
always @(posedge clk_sys) begin
	dk_as_d <= _cpuAS; dk_dma_d <= scsi_dma; dk_word_d <= pdma_word; dk_rw_d <= _cpuRW;
	dk_rq_d <= dk_rq; dk_wq_d <= dk_wq;
	if (dk_rq && !dk_rq_d) dk_rd_op <= 1'b1;
	else if (dk_wq && !dk_wq_d) dk_rd_op <= 1'b0;
	if (dk_tick == 25'd32_499_999) begin
		dk_tick <= 0;
		dk_l10 <= {dk_rd, dk_wr, dk_hold};
		dk_l11 <= {dk_hrd, dk_hwr, dk_hreq};
		dk_rd <= 0; dk_wr <= 0; dk_hold <= 0; dk_hrd <= 0; dk_hwr <= 0; dk_hreq <= 0;
	end
	else begin
		dk_tick <= dk_tick + 1'd1;
		if (_cpuAS && !dk_as_d && dk_dma_d) begin
			if (dk_rw_d) dk_rd <= dk_rd + (dk_word_d ? 32'd2 : 32'd1);
			else         dk_wr <= dk_wr + (dk_word_d ? 32'd2 : 32'd1);
		end
		if (!_cpuAS && selectSCSI && scsi_bus_hold) dk_hold <= dk_hold + 1'd1;
		if (dk_rq || (dk_ack && dk_rd_op))  dk_hrd <= dk_hrd + 1'd1;
		if (dk_wq || (dk_ack && !dk_rd_op)) dk_hwr <= dk_hwr + 1'd1;
		if (dk_rq && !dk_rq_d) dk_hreq <= dk_hreq + 1'd1;
	end
end

reg  [31:0] ab_kbd = 0, ab_mouse = 0, ab_fall = 0, ab_cb1 = 0, ab_hold = 0, ab_hold_max = 0, ab_low = 0;
reg  [31:0] ab_l_hmax = 0;
reg  [95:0] ab_l13 = 0;
reg         ab_key_d = 0, ab_mouse_d = 0, ab_line_d = 1, ab_cb1_d = 0;
always @(posedge clk_sys) begin
	ab_key_d <= ps2_key[10]; ab_mouse_d <= ps2_mouse[24]; ab_line_d <= adb_line; ab_cb1_d <= cuda_via_clock;
	if (!_cpuAS && selectSCSI && scsi_bus_hold) ab_hold <= ab_hold + 1'd1;
	else ab_hold <= 0;
	if (!adb_line) begin if (~&ab_low) ab_low <= ab_low + 1'd1; end
	else ab_low <= 0;
	if (dk_tick == 25'd32_499_999) begin
		ab_l13    <= {ab_kbd[15:0], ab_mouse[15:0], ab_fall, ab_cb1};
		ab_l_hmax <= ab_hold_max;
		ab_kbd <= 0; ab_mouse <= 0; ab_fall <= 0; ab_cb1 <= 0; ab_hold_max <= 0;
	end
	else begin
		if (ps2_key[10] != ab_key_d)     ab_kbd   <= ab_kbd + 1'd1;
		if (ps2_mouse[24] != ab_mouse_d) ab_mouse <= ab_mouse + 1'd1;
		if (ab_line_d && !adb_line)      ab_fall  <= ab_fall + 1'd1;
		if (cuda_via_clock != ab_cb1_d)  ab_cb1   <= ab_cb1 + 1'd1;
		if (ab_hold > ab_hold_max)       ab_hold_max <= ab_hold;
	end
end
wire [95:0] ab_l12_live = {adb_dbg_state,
	3'b000, adb_line, 3'b000, cuda_adb_low, 3'b000, !adb_dev_line,
	3'b000, (via_pb_oe[5] ? via_pb_o[5] : 1'b1), 3'b000, (via_pb_oe[4] ? via_pb_o[4] : 1'b1), 3'b000, cuda_treq,
	ab_l_hmax, ab_low};
reg  [95:0] ab_l12 = 0;
always @(posedge clk_sys) if (ce_pix && hc == 10'd0 && vc == 10'd384) ab_l12 <= ab_l12_live;

wire       rv_acc = selectVIA && !_cpuVMA && E_falling;
wire       rv_wr  = rv_acc && !_cpuRW;
wire [3:0] rv_reg = a24[12:9];
wire       rv_tip = via_pb_oe[5] ? via_pb_o[5] : 1'b1;
wire       rv_ack = via_pb_oe[4] ? via_pb_o[4] : 1'b1;
reg [31:0] rec_mem [0:23];
reg  [4:0] rec_wp = 5'd0;
reg [15:0] rec_dt = 16'd0;
reg  [4:0] rec_div = 5'd0;
reg [31:0] rec_total = 32'd0;
reg  [3:0] rb_falls = 4'd0, rb_rises = 4'd0;
reg        rb_open = 1'b0;
reg  [7:0] rb_idle = 8'd0;
reg        rc_cb1_d = 1'b1, rc_treq_d = 1'b1;
reg        rev;
reg  [3:0] rev_code;
reg [11:0] rev_val;
always @(*) begin
	rev = 1'b1; rev_code = 4'd0; rev_val = 12'd0;
	if (rv_acc && _cpuRW && rv_reg == 4'hA)          begin rev_code = 4'd2; rev_val = {4'd0, via_dbg_sr}; end
	else if (rv_wr && rv_reg == 4'hA)                begin rev_code = 4'd3; rev_val = {4'd0, cpuDataOut[15:8]}; end
	else if (rv_wr && rv_reg == 4'hB)                begin rev_code = 4'd4; rev_val = {4'd0, cpuDataOut[15:8]}; end
	else if (rv_wr && rv_reg == 4'h0)                begin rev_code = 4'd5; rev_val = {4'd0, cpuDataOut[15:8]}; end
	else if (rv_wr && rv_reg == 4'hD && cpuDataOut[10]) begin rev_code = 4'd6; rev_val = {4'd0, cpuDataOut[15:8]}; end
	else if (rv_wr && rv_reg == 4'hE)                begin rev_code = 4'd7; rev_val = {4'd0, cpuDataOut[15:8]}; end
	else if (cuda_treq != rc_treq_d)                 begin rev_code = 4'd8; rev_val = {11'd0, cuda_treq}; end
	else if (via_dbg_done)                           begin rev_code = 4'd9; rev_val = {8'd0, via_dbg_cnt}; end
	else if (rb_open && rb_idle == 8'hFF)            begin rev_code = 4'd1; rev_val = {via_dbg_cnt, rb_falls, rb_rises}; end
	else rev = 1'b0;
end
always @(posedge clk_sys) begin
	rc_cb1_d  <= cuda_via_clock;
	rc_treq_d <= cuda_treq;
	rec_div   <= rec_div + 5'd1;
	if (rec_div == 5'd31 && rec_dt != 16'hFFFF) rec_dt <= rec_dt + 16'd1;
	if (cuda_via_clock != rc_cb1_d) begin
		rb_open <= 1'b1;
		rb_idle <= 8'd0;
		if (!cuda_via_clock && rb_falls != 4'hF) rb_falls <= rb_falls + 4'd1;
		if ( cuda_via_clock && rb_rises != 4'hF) rb_rises <= rb_rises + 4'd1;
	end
	else if (rb_idle != 8'hFF) rb_idle <= rb_idle + 8'd1;
	if (rev) begin
		rec_mem[rec_wp] <= {rev_code, rev_val, rec_dt};
		rec_wp    <= (rec_wp == 5'd23) ? 5'd0 : rec_wp + 5'd1;
		rec_dt    <= 16'd0;
		rec_total <= rec_total + 32'd1;
		if (rev_code == 4'd1) begin rb_open <= 1'b0; rb_falls <= 4'd0; rb_rises <= 4'd0; end
	end
end
reg  [79:0] jr_mem [0:7];
reg   [2:0] jr_wp = 3'd0;
reg  [31:0] jr_prev = 32'd0;
reg         jr_frozen = 1'b0;
reg         flt_seen = 1'b0, flt_d = 1'b0;
reg  [31:0] flt_addr = 32'd0, flt_pc = 32'd0;
reg   [3:0] flt_fc = 4'd0;
reg   [7:0] flt_cnt = 8'd0;
wire        jr_trig = dbg_ill_seen || dbg_halted || dbg_pmmu_fault;
always @(posedge clk_sys) begin
	flt_d <= dbg_pmmu_fault;
	if (dbg_pc != jr_prev) jr_prev <= dbg_pc;
	if (!n_reset) begin
		jr_frozen <= 1'b0; jr_wp <= 3'd0;
		flt_seen <= 1'b0; flt_cnt <= 8'd0;
	end
	else begin
		if (jr_trig) jr_frozen <= 1'b1;
		if (dbg_pc != jr_prev && dbg_pc != jr_prev + 32'd2 && !jr_frozen && !jr_trig) begin
			jr_mem[jr_wp] <= {jr_prev, dbg_opcode, dbg_pc};
			jr_wp <= jr_wp + 3'd1;
		end
		if (dbg_pmmu_fault && !flt_d) begin
			if (flt_cnt != 8'hFF) flt_cnt <= flt_cnt + 8'd1;
			if (!flt_seen) begin
				flt_seen <= 1'b1;
				flt_addr <= dbg_memaddr;
				flt_pc   <= dbg_exe_pc;
				flt_fc   <= {dbg_krw, dbg_kfc};
			end
		end
	end
end

function automatic [4:0] rec_idx(input [4:0] wp, input [4:0] k);
	reg [5:0] s;
	begin s = wp + k; rec_idx = (s >= 6'd24) ? s - 6'd24 : s[4:0]; end
endfunction
wire [95:0] rec_live = {via_dbg_cnt, 4'd0, via_dbg_acr, 1'b0, via_dbg_ifr, 1'b0, via_dbg_ier,
                        via_dbg_sr, cuda_dbg_a2, 3'd0, cuda_treq, 3'd0, rv_tip, 3'd0, rv_ack, 3'd0, cuda_via_clock,
                        rec_total};

reg [31:0] dbg_l_pc = 0, dbg_l_trap = 0, dbg_l_icnt = 0;
reg [15:0] dbg_l_op = 0, dbg_l_cuda = 0;
reg [63:0] dbg_l_sad = 0;
reg [79:0] dbg_l_ill = 0;
reg [63:0] dbg_l_fail = 0, dbg_l_berr = 0;
reg [15:0] dbg_l_bcnt = 0;
reg [55:0] dbg_l_scsi = 0;
reg [67:0] dbg_l_clk = 0;
always @(posedge clk_sys) if (ce_pix && hc == 10'd0 && vc == 10'd384) begin
	dbg_l_sad  <= dbg_sadmac;
	dbg_l_pc   <= dbg_pc;
	dbg_l_op   <= dbg_opcode;
	dbg_l_cuda <= cuda_dbg_addr;
	dbg_l_icnt <= dbg_icount;
	dbg_l_trap <= dbg_trap_vector;
	dbg_l_ill  <= dbg_ill;
	dbg_l_fail <= dbg_fail;
	dbg_l_berr <= dbg_berr;
	dbg_l_bcnt <= dbg_berr_cnt;
	dbg_l_scsi <= {3'b000, dbg_scsi_mnt[1], 3'b000, dbg_scsi_mnt[0], dbg_scsi_rds, dbg_scsi_lba};
	dbg_l_clk  <= {3'b000, mac_seeded, mac_secs, dbg_clk_rel};
end

wire [12:0] dbg_flags = {
	ram_configured, !dbg_fault_seen, !dbg_halted, dbg_vram_seen, dbg_clut_seen,
	dbg_l_icnt[20], n_reset, !cuda_hold, cuda_running, pram_loaded, pram_ready,
	cuda_fw_loaded, rom_loaded };

function automatic [2:0] dbg_glyph(input [3:0] d, input [2:0] row);
	reg [14:0] g;
	begin
		case (d)
			4'h0: g = 15'b111_101_101_101_111;  4'h1: g = 15'b010_110_010_010_111;
			4'h2: g = 15'b111_001_111_100_111;  4'h3: g = 15'b111_001_111_001_111;
			4'h4: g = 15'b101_101_111_001_001;  4'h5: g = 15'b111_100_111_001_111;
			4'h6: g = 15'b111_100_111_101_111;  4'h7: g = 15'b111_001_001_001_001;
			4'h8: g = 15'b111_101_111_101_111;  4'h9: g = 15'b111_101_111_001_111;
			4'hA: g = 15'b111_101_111_101_101;  4'hB: g = 15'b110_101_110_101_110;
			4'hC: g = 15'b111_100_100_100_111;  4'hD: g = 15'b110_101_101_101_110;
			4'hE: g = 15'b111_100_111_100_111;  default: g = 15'b111_100_111_100_100;
		endcase
		case (row)
			3'd0: dbg_glyph = g[14:12];  3'd1: dbg_glyph = g[11:9];  3'd2: dbg_glyph = g[8:6];
			3'd3: dbg_glyph = g[5:3];    3'd4: dbg_glyph = g[2:0];   default: dbg_glyph = 3'b000;
		endcase
	end
endfunction

wire [9:0] dbg_x  = hc - 10'd8;
wire [8:0] dbg_y  = vc[8:0] - 9'd4;
wire [4:0] dbg_cell = dbg_x[7:3];
wire [95:0] dk_row = (dbg_y >= 9'd168) ? ab_l13 : (dbg_y >= 9'd154) ? ab_l12 :
                     (dbg_y >= 9'd140) ? dk_l11 : dk_l10;
wire [8:0] rr_y = dbg_y - 9'd182;
wire [3:0] rr_k = (rr_y >= 9'd112) ? 4'd8 : (rr_y >= 9'd98) ? 4'd7 : (rr_y >= 9'd84) ? 4'd6 :
                  (rr_y >= 9'd70)  ? 4'd5 : (rr_y >= 9'd56) ? 4'd4 : (rr_y >= 9'd42) ? 4'd3 :
                  (rr_y >= 9'd28)  ? 4'd2 : (rr_y >= 9'd14) ? 4'd1 : 4'd0;
wire [4:0] rr_e = (rr_k - 4'd1) * 3;
wire [79:0] jr_ent = jr_mem[jr_wp + rr_k[2:0] - 3'd1];
wire [95:0] jr_row = {jr_ent[79:48], 16'h0000, jr_ent[47:32], jr_ent[31:0]};
wire [95:0] rec_row = (rr_k == 4'd0) ? rec_live :
                      jr_frozen ? jr_row :
                      {rec_mem[rec_idx(rec_wp, rr_e)], rec_mem[rec_idx(rec_wp, rr_e + 5'd1)],
                       rec_mem[rec_idx(rec_wp, rr_e + 5'd2)]};
wire [95:0] flt_row = {flt_addr, dbg_pmmu_fstat, flt_fc, 4'h0, flt_cnt, flt_pc};
reg  [3:0] dbg_nib;
reg        dbg_blank;
always @(*) begin
	dbg_nib = 4'h0; dbg_blank = 1'b1;
	if (dbg_y >= 9'd14 && dbg_y < 9'd26) begin
		dbg_blank = 1'b0;
		if (dbg_cell < 5'd8)                          dbg_nib = dbg_l_pc[31 - dbg_cell*4 -: 4];
		else if (dbg_cell >= 5'd9  && dbg_cell < 5'd13) dbg_nib = dbg_l_op[15 - (dbg_cell-5'd9)*4 -: 4];
		else if (dbg_cell >= 5'd14 && dbg_cell < 5'd18) dbg_nib = dbg_l_cuda[15 - (dbg_cell-5'd14)*4 -: 4];
		else dbg_blank = 1'b1;
	end
	else if (dbg_y >= 9'd28 && dbg_y < 9'd40) begin
		dbg_blank = 1'b0;
		if (dbg_cell < 5'd8)                          dbg_nib = dbg_l_icnt[31 - dbg_cell*4 -: 4];
		else if (dbg_cell >= 5'd9 && dbg_cell < 5'd17) dbg_nib = dbg_l_trap[31 - (dbg_cell-5'd9)*4 -: 4];
		else dbg_blank = 1'b1;
	end
	else if (dbg_y >= 9'd42 && dbg_y < 9'd54) begin
		dbg_blank = 1'b0;
		if (dbg_cell < 5'd8)                          dbg_nib = dbg_l_sad[63 - dbg_cell*4 -: 4];
		else if (dbg_cell >= 5'd9 && dbg_cell < 5'd17) dbg_nib = dbg_l_sad[31 - (dbg_cell-5'd9)*4 -: 4];
		else dbg_blank = 1'b1;
	end
	else if (dbg_y >= 9'd56 && dbg_y < 9'd68) begin
		dbg_blank = 1'b0;
		if (dbg_cell < 5'd8)                            dbg_nib = dbg_l_ill[79 - dbg_cell*4 -: 4];
		else if (dbg_cell >= 5'd9  && dbg_cell < 5'd13) dbg_nib = dbg_l_ill[47 - (dbg_cell-5'd9)*4 -: 4];
		else if (dbg_cell >= 5'd14 && dbg_cell < 5'd22) dbg_nib = dbg_l_ill[31 - (dbg_cell-5'd14)*4 -: 4];
		else dbg_blank = 1'b1;
	end
	else if (dbg_y >= 9'd70 && dbg_y < 9'd82) begin
		dbg_blank = 1'b0;
		if (dbg_cell < 5'd8)                          dbg_nib = dbg_l_fail[63 - dbg_cell*4 -: 4];
		else if (dbg_cell >= 5'd9 && dbg_cell < 5'd17) dbg_nib = dbg_l_fail[31 - (dbg_cell-5'd9)*4 -: 4];
		else dbg_blank = 1'b1;
	end
	else if (dbg_y >= 9'd84 && dbg_y < 9'd96) begin
		dbg_blank = 1'b0;
		if (dbg_cell < 5'd8)                            dbg_nib = dbg_l_berr[63 - dbg_cell*4 -: 4];
		else if (dbg_cell >= 5'd9  && dbg_cell < 5'd17) dbg_nib = dbg_l_berr[31 - (dbg_cell-5'd9)*4 -: 4];
		else if (dbg_cell >= 5'd18 && dbg_cell < 5'd22) dbg_nib = dbg_l_bcnt[15 - (dbg_cell-5'd18)*4 -: 4];
		else dbg_blank = 1'b1;
	end
	else if (dbg_y >= 9'd98 && dbg_y < 9'd110) begin
		dbg_blank = 1'b0;
		if (dbg_cell < 5'd2)                            dbg_nib = dbg_l_scsi[55 - dbg_cell*4 -: 4];
		else if (dbg_cell >= 5'd3 && dbg_cell < 5'd7)   dbg_nib = dbg_l_scsi[47 - (dbg_cell-5'd3)*4 -: 4];
		else if (dbg_cell >= 5'd8 && dbg_cell < 5'd16)  dbg_nib = dbg_l_scsi[31 - (dbg_cell-5'd8)*4 -: 4];
		else dbg_blank = 1'b1;
	end
	else if (dbg_y >= 9'd112 && dbg_y < 9'd124) begin
		dbg_blank = 1'b0;
		if (dbg_cell == 5'd0)                           dbg_nib = dbg_l_clk[67:64];
		else if (dbg_cell >= 5'd2 && dbg_cell < 5'd10)  dbg_nib = dbg_l_clk[63 - (dbg_cell-5'd2)*4 -: 4];
		else if (dbg_cell >= 5'd11 && dbg_cell < 5'd19) dbg_nib = dbg_l_clk[31 - (dbg_cell-5'd11)*4 -: 4];
		else dbg_blank = 1'b1;
	end
	else if (dbg_y >= 9'd126 && dbg_y < 9'd180) begin
		dbg_blank = 1'b0;
		if (dbg_cell < 5'd8)                            dbg_nib = dk_row[95 - dbg_cell*4 -: 4];
		else if (dbg_cell >= 5'd9  && dbg_cell < 5'd17) dbg_nib = dk_row[63 - (dbg_cell-5'd9)*4 -: 4];
		else if (dbg_cell >= 5'd18 && dbg_cell < 5'd26) dbg_nib = dk_row[31 - (dbg_cell-5'd18)*4 -: 4];
		else dbg_blank = 1'b1;
	end
	else if (dbg_y >= 9'd182 && dbg_y < 9'd308) begin
		dbg_blank = 1'b0;
		if (dbg_cell < 5'd8)                            dbg_nib = rec_row[95 - dbg_cell*4 -: 4];
		else if (dbg_cell >= 5'd9  && dbg_cell < 5'd17) dbg_nib = rec_row[63 - (dbg_cell-5'd9)*4 -: 4];
		else if (dbg_cell >= 5'd18 && dbg_cell < 5'd26) dbg_nib = rec_row[31 - (dbg_cell-5'd18)*4 -: 4];
		else dbg_blank = 1'b1;
	end
	else if (dbg_y >= 9'd308 && dbg_y < 9'd320) begin
		dbg_blank = 1'b0;
		if (dbg_cell < 5'd8)                            dbg_nib = flt_row[95 - dbg_cell*4 -: 4];
		else if (dbg_cell >= 5'd9  && dbg_cell < 5'd17) dbg_nib = flt_row[63 - (dbg_cell-5'd9)*4 -: 4];
		else if (dbg_cell >= 5'd18 && dbg_cell < 5'd26) dbg_nib = flt_row[31 - (dbg_cell-5'd18)*4 -: 4];
		else dbg_blank = 1'b1;
	end
end
wire [8:0] dbg_ry  = (dbg_y >= 9'd308) ? dbg_y - 9'd308 :
                     (dbg_y >= 9'd182) ? rr_y - rr_k * 9'd14 :
                     (dbg_y >= 9'd168) ? dbg_y - 9'd168 :
                     (dbg_y >= 9'd154) ? dbg_y - 9'd154 :
                     (dbg_y >= 9'd140) ? dbg_y - 9'd140 :
                     (dbg_y >= 9'd126) ? dbg_y - 9'd126 :
                     (dbg_y >= 9'd112) ? dbg_y - 9'd112 :
                     (dbg_y >= 9'd98) ? dbg_y - 9'd98 :
                     (dbg_y >= 9'd84) ? dbg_y - 9'd84 :
                     (dbg_y >= 9'd70) ? dbg_y - 9'd70 :
                     (dbg_y >= 9'd56) ? dbg_y - 9'd56 :
                     (dbg_y >= 9'd42) ? dbg_y - 9'd42 :
                     (dbg_y >= 9'd28) ? dbg_y - 9'd28 : dbg_y - 9'd14;
wire [2:0] dbg_row = dbg_ry[3:1];
wire [2:0] dbg_g3  = dbg_glyph(dbg_nib, dbg_row);
wire [1:0] dbg_col = dbg_x[2:1];
wire       dbg_ink = !dbg_blank && dbg_col != 2'd3 && dbg_g3[2 - dbg_col];

wire       dbg_panel = hc >= 10'd8 && dbg_x < 10'd216 && vc >= 10'd4 && vc < 10'd324;
wire [3:0] dbg_fidx  = dbg_x[7:4];
wire       dbg_fblk  = dbg_y < 9'd12 && dbg_x[3:0] < 4'd12 && dbg_x[9:4] < 6'd13;

always @(posedge clk_sys) if (ce_pix) begin
	dbg_on <= DEBUG_STRIP && dbg_panel && !status[13];
	if (dbg_fblk) begin
		dbg_r <= dbg_flags[dbg_fidx] ? 8'h00 : 8'hE0;
		dbg_g <= dbg_flags[dbg_fidx] ? 8'hE0 : 8'h00;
		dbg_b <= 8'h00;
	end
	else begin
		dbg_r <= dbg_ink ? 8'hFF : 8'h00;
		dbg_g <= dbg_ink ? 8'hFF : 8'h00;
		dbg_b <= dbg_ink ? 8'hFF : 8'h00;
	end
end

wire [7:0] pvia_do;
wire       pvia_irq;
wire [3:0] sim_monitor_id = mode640 ? 4'd6 : 4'd2;

pseudovia pvia
(
	.clk_sys        ( clk_sys        ),
	.reset          ( !n_reset       ),
	.soft_rst       ( !k_reset_n     ),

	.addr           ( a24[12:0]      ),
	.data_in        ( cpuDataOut[15:8] ),
	.data_out       ( pvia_do        ),
	.we             ( !_cpuRW        ),
	.req            ( selectPVIA && !_cpuVMA ),

	.vblank_irq     ( vblank         ),
	.slot_irq       ( 1'b0           ),
	.asc_irq        ( asc_irq        ),
	.scsi_irq       ( 1'b0           ),
	.scsi_drq       ( 1'b0           ),
	.irq_out        ( pvia_irq       ),

	.ram_config     ( 8'hC0          ),
	.monitor_id     ( sim_monitor_id ),
	.video_config   ( pvia_video_cfg ),
	.ram_config_out ( ram_config_out ),
	.ram_configured ( ram_configured )
);

assign cpuDataIn = ic_hit     ? ic_data :
                   dc_hit     ? dc_data :
                   selectMem  ? memDataOut :
                   selectVIA  ? {via_do, via_do} :
                   selectPVIA ? {pvia_do, pvia_do} :
                   selectASC  ? {asc_do, asc_do} :
                   selectSCC  ? {scc_do, scc_do} :
                   selectCLUT ? {clut_do, clut_do} :
                   selectSCSI ? (pdma_word ? {pd_hi, pd_lo} : {scsi_do, scsi_do}) :
                   selectSWIM ? {swim_do, swim_do} :
                                16'h0000;

assign _cpuIPL = cuda_nmi ? 3'b000 : !scc_irq_n ? 3'b011 : pvia_irq ? 3'b101 : via_irq ? 3'b110 : 3'b111;

`ifdef VERILATOR
wire [31:0] sim_cpuAddr     /*verilator public_flat_rd*/ = cpuAddr;
wire  [2:0] sim_cpuFC       /*verilator public_flat_rd*/ = cpuFC;
wire        sim_cpuAS       /*verilator public_flat_rd*/ = _cpuAS;
wire        sim_cpuRW       /*verilator public_flat_rd*/ = _cpuRW;
wire        sim_cpuDTACK    /*verilator public_flat_rd*/ = _cpuDTACK;
wire        sim_cpuVPA      /*verilator public_flat_rd*/ = _cpuVPA;
wire        sim_cpuBERR     /*verilator public_flat_rd*/ = cpuBERR;
wire [15:0] sim_cpuDin      /*verilator public_flat_rd*/ = cpuDataIn;
wire [15:0] sim_cpuDout     /*verilator public_flat_rd*/ = cpuDataOut;
wire  [1:0] sim_cpuDS_n     /*verilator public_flat_rd*/ = {_cpuUDS, _cpuLDS};
wire        sim_cpuReset    /*verilator public_flat_rd*/ = n_reset;
wire        sim_overlay     /*verilator public_flat_rd*/ = overlay;
wire        sim_rom_loaded  /*verilator public_flat_rd*/ = rom_loaded;
wire  [2:0] sim_ipl_n       /*verilator public_flat_rd*/ = _cpuIPL;
wire  [7:0] sim_via_pa_o    /*verilator public_flat_rd*/ = via_pa_o;
wire  [7:0] sim_via_pa_oe   /*verilator public_flat_rd*/ = via_pa_oe;
wire        sim_kclkena     /*verilator public_flat_rd*/ = dbg_clkena;
wire        sim_kdecode     /*verilator public_flat_rd*/ = dbg_decode;
wire [31:0] sim_kpc         /*verilator public_flat_rd*/ = dbg_pc;
wire [15:0] sim_kopcode     /*verilator public_flat_rd*/ = dbg_opcode;
wire        sim_pmmu_busy   /*verilator public_flat_rd*/ = dbg_pmmu_busy;
wire        sim_pmmu_fault  /*verilator public_flat_rd*/ = dbg_pmmu_fault;
wire        sim_walker      /*verilator public_flat_rd*/ = dbg_walker;
wire [31:0] sim_cacr        /*verilator public_flat_rd*/ = dbg_cacr;
wire [31:0] sim_vbr         /*verilator public_flat_rd*/ = dbg_vbr;
wire [31:0] sim_trap_vector /*verilator public_flat_rd*/ = dbg_trap_vector;
wire        sim_halted      /*verilator public_flat_rd*/ = dbg_halted;
wire [15:0] sim_pmmu_fstat  /*verilator public_flat_rd*/ = dbg_pmmu_fstat;
wire [31:0] sim_mac_secs    /*verilator public_flat_rd*/ = mac_secs;
wire        sim_mac_seeded  /*verilator public_flat_rd*/ = mac_seeded;
wire [31:0] sim_ic_fetch    /*verilator public_flat_rd*/ = icache.n_fetch;
wire [31:0] sim_ic_hit      /*verilator public_flat_rd*/ = icache.n_hit;
wire [31:0] sim_dc_read     /*verilator public_flat_rd*/ = dcache.n_fetch;
wire [31:0] sim_dc_hit      /*verilator public_flat_rd*/ = dcache.n_hit;
wire        sim_adb_cuda_low /*verilator public_flat_rd*/ = cuda_adb_low;
wire        sim_adb_dev_line /*verilator public_flat_rd*/ = adb_dev_line;
wire  [7:0] sim_ram_config  /*verilator public_flat_rd*/ = ram_config_out;
wire        sim_ram_cfgd    /*verilator public_flat_rd*/ = ram_configured;
wire [15:0] sim_cuda_addr   /*verilator public_flat_rd*/ = cuda_dbg_addr;
wire        sim_cuda_run    /*verilator public_flat_rd*/ = cuda_running;
wire        sim_cuda_hold   /*verilator public_flat_rd*/ = cuda_hold;
wire  [4:0] sim_cuda_via    /*verilator public_flat_rd*/ =
	{cuda_treq, via_pb_oe[4] ? via_pb_o[4] : 1'b1, via_pb_oe[5] ? via_pb_o[5] : 1'b1,
	 cuda_via_clock, cuda_via_data};

reg  [63:0] dbg_tick = 0;
reg  [31:0] dbg_last = 0;
wire [31:0] dbg_now = {cuda_treq, via_pb_oe[4] ? via_pb_o[4] : 1'b1,
	via_pb_oe[5] ? via_pb_o[5] : 1'b1, cuda_via_clock, cuda_via_data,
	via_cb2_t, via_cb2_o, via1.ext_cnt, via1.shift_reg,
	via1.acr, via1.irq_flags[2], 4'd0};
always @(posedge clk_sys) begin
	dbg_tick <= dbg_tick + 1;
	dbg_last <= dbg_now;
	if (dbg_now != dbg_last && $test$plusargs("cudalog"))
		$display("CL %0d hc05=%04x treq=%b ack=%b tip=%b cb1=%b cdata=%b cb2t=%b cb2o=%b cnt=%0d sr=%02x acr=%02x ifr2=%b",
			dbg_tick, cuda_dbg_addr, dbg_now[31], dbg_now[30], dbg_now[29], dbg_now[28],
			dbg_now[27], dbg_now[26], dbg_now[25], dbg_now[24:21],
			dbg_now[20:13], dbg_now[12:5], dbg_now[4]);
	if (selectVIA && !_cpuVMA && a24[12:9] == 4'hA && E_falling && $test$plusargs("cudalog"))
		$display("CL %0d 68030 %s SR %02x", dbg_tick, _cpuRW ? "R" : "W",
			_cpuRW ? via_do : cpuDataOut[15:8]);
end
`endif

endmodule
