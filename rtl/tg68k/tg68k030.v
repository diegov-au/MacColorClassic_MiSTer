module tg68k030 (
	input             clk,
	input             reset,
	input             phi1,
	input             phi2,

	input             dtack_n,
	input             vpa_n,
	input             berr,
	input       [2:0] ipl,
	input      [15:0] din,
	output     [15:0] dout,
	output reg [31:0] addr,
	output            as_n,
	output            uds_n,
	output            lds_n,
	output            rw_n,
	output      [2:0] fc,
	output            reset_n,

	output reg        E,
	output            E_PosClkEn,
	output            E_NegClkEn,
	output            vma_n,

	output            walker_cycle,

	output     [31:0] early_addr,
	output reg        fetch_cycle,
	output reg        data_cycle,
	output            cache_inv,
	input             din_now,

	output            dbg_clkena,
	output            dbg_decode,
	output     [31:0] dbg_pc,
	output     [15:0] dbg_opcode,
	output            dbg_pmmu_busy,
	output            dbg_pmmu_fault,
	output     [31:0] dbg_cacr,
	output     [31:0] dbg_vbr,
	output     [31:0] dbg_trap_vector,
	output            dbg_halted,
	output     [15:0] dbg_pmmu_fstat,
	output     [31:0] dbg_memaddr,
	output     [31:0] dbg_exe_pc,
	output      [2:0] dbg_kfc,
	output            dbg_krw
);

localparam S_IDLE  = 3'd0,
           S_WAIT  = 3'd1,
           S_TAIL1 = 3'd2,
           S_TAIL2 = 3'd3,
           S_ENDC  = 3'd4;

reg   [2:0] s_state;
reg         clkena_d;

wire  [1:0] k_busstate;
wire [31:0] k_addr;
wire [15:0] k_dout;
wire        k_uds_n, k_lds_n, k_rw;
wire  [2:0] k_fc;
wire        pmmu_busy, pmmu_fault;

wire        wk_req, wk_we;
wire [31:0] wk_addr, wk_wdat;
reg         wk_ack;
reg  [31:0] wk_data;
reg         wk_berr;

reg         wk_cyc;
reg         wk_half;

wire        k_hold = wk_req | (pmmu_busy & ~pmmu_fault);

wire        tg68_clkena = (s_state == S_ENDC && !wk_cyc) ||
                          (s_state == S_IDLE && k_busstate == 2'b01 && !clkena_d && !k_hold);

wire        auto_iack   = (fc == 3'b111) && !vpa_n;
wire  [7:0] auto_vector = {4'h1, 1'b1, addr[3:1]};
wire [15:0] k_din_src   = auto_iack ? {auto_vector, auto_vector} : din;
reg  [15:0] k_din_r;

reg         uds_n_r, lds_n_r, rw_r, as_n_r;
reg   [2:0] fc_r;
reg  [15:0] dout_r;

assign as_n  = as_n_r;
assign uds_n = uds_n_r;
assign lds_n = lds_n_r;
assign rw_n  = rw_r;
assign fc    = fc_r;
assign dout  = dout_r;
assign walker_cycle = wk_cyc;

reg  berr_hold;
wire berr_held = berr | berr_hold;
always @(posedge clk) begin
	if (reset || s_state == S_IDLE) berr_hold <= 1'b0;
	else if (berr)                  berr_hold <= 1'b1;
end

wire xVma;
wire wait_exit = berr_held | ~dtack_n | (phi2 & xVma);

always @(posedge clk) begin
	if (reset) begin
		s_state  <= S_IDLE;
		as_n_r   <= 1'b1;
		rw_r     <= 1'b1;
		uds_n_r  <= 1'b1;
		lds_n_r  <= 1'b1;
		fc_r     <= 3'b110;
		fetch_cycle <= 1'b0;
		data_cycle  <= 1'b0;
		clkena_d <= 1'b0;
		wk_cyc   <= 1'b0;
		wk_half  <= 1'b0;
		wk_ack   <= 1'b0;
		wk_berr  <= 1'b0;
		wk_data  <= 32'd0;
	end else begin
		clkena_d <= tg68_clkena;

		if (!wk_req) begin
			wk_ack  <= 1'b0;
			wk_berr <= 1'b0;
			if (!wk_cyc) wk_half <= 1'b0;
		end

		case (s_state)
			S_IDLE:
				if (wk_req && !wk_ack) begin
					wk_cyc  <= 1'b1;
					addr    <= {wk_addr[31:1] + {30'd0, wk_half}, 1'b0};
					fc_r    <= 3'b101;
					fetch_cycle <= 1'b0;
					data_cycle  <= 1'b0;
					rw_r    <= ~wk_we;
					dout_r  <= wk_half ? wk_wdat[15:0] : wk_wdat[31:16];
					uds_n_r <= 1'b0;
					lds_n_r <= 1'b0;
					as_n_r  <= 1'b0;
					s_state <= S_WAIT;
				end
				else if (k_busstate != 2'b01 && !wk_req && pmmu_fault) begin
					s_state <= S_ENDC;
				end
				else if (k_busstate != 2'b01 && !k_hold) begin
					wk_cyc  <= 1'b0;
					addr    <= k_addr;
					fc_r    <= k_fc;
					fetch_cycle <= k_busstate == 2'b00;
					data_cycle  <= k_busstate == 2'b10;
					rw_r    <= k_rw;
					dout_r  <= k_dout;
					uds_n_r <= k_uds_n;
					lds_n_r <= k_lds_n;
					as_n_r  <= 1'b0;
					s_state <= S_WAIT;
				end
			S_WAIT:
				if (wait_exit && din_now && !berr_held) begin
					if (wk_cyc) begin
						if (wk_half) wk_data[15:0]  <= din;
						else         wk_data[31:16] <= din;
					end
					k_din_r <= k_din_src;
					uds_n_r <= 1'b1;
					lds_n_r <= 1'b1;
					as_n_r  <= 1'b1;
					s_state <= S_ENDC;
				end
				else if (wait_exit) s_state <= S_TAIL1;
			S_TAIL1:
				s_state <= S_TAIL2;
			S_TAIL2: begin
				if (wk_cyc) begin
					if (wk_half) wk_data[15:0]  <= din;
					else         wk_data[31:16] <= din;
					if (berr_held) wk_berr <= 1'b1;
				end
				k_din_r <= k_din_src;
				uds_n_r <= 1'b1;
				lds_n_r <= 1'b1;
				as_n_r  <= 1'b1;
				s_state <= S_ENDC;
			end
			S_ENDC: begin
				rw_r    <= 1'b1;
				s_state <= S_IDLE;
				if (wk_cyc) begin
					wk_cyc <= 1'b0;
					if (wk_half || wk_berr) begin
						wk_half <= 1'b0;
						wk_ack  <= 1'b1;
					end else begin
						wk_half <= 1'b1;
					end
				end
			end
			default: s_state <= S_IDLE;
		endcase
	end
end

reg [3:0] eCntr;
reg       rVma;
reg       Vpai;
assign vma_n = rVma;
assign xVma  = ~rVma & (eCntr == 8);
assign E_PosClkEn = phi2 & (eCntr == 5);
assign E_NegClkEn = phi2 & (eCntr == 9);

always @(posedge clk) begin
	if (reset) begin
		E     <= 1'b0;
		eCntr <= 4'd0;
		rVma  <= 1'b1;
	end else begin
		if (phi1) Vpai <= vpa_n;
		if (phi2) begin
			if (eCntr == 9)      E <= 1'b0;
			else if (eCntr == 5) E <= 1'b1;
			eCntr <= (eCntr == 9) ? 4'd0 : eCntr + 1'd1;
		end
		if (phi2 & (s_state != S_IDLE) & ~Vpai & (eCntr == 3))
			rVma <= 1'b0;
		else if (phi1 & (eCntr == 0))
			rVma <= 1'b1;
	end
end

TG68KdotC_Kernel tg68k (
	.clk                ( clk               ),
	.nReset             ( ~reset            ),
	.clkena_in          ( tg68_clkena       ),
	.data_in            ( k_din_r           ),
	.IPL                ( ipl               ),
	.IPL_autovector     ( 1'b0              ),
	.berr               ( berr_held & ~wk_cyc ),
	.CPU                ( 2'b10             ),
	.addr_out           ( k_addr            ),
	.data_write         ( k_dout            ),
	.nWr                ( k_rw              ),
	.nUDS               ( k_uds_n           ),
	.nLDS               ( k_lds_n           ),
	.busstate           ( k_busstate        ),
	.longword           (                   ),
	.nResetOut          ( reset_n           ),
	.FC                 ( k_fc              ),
	.clr_berr           (                   ),
	.CACR_out           ( dbg_cacr          ),
	.cache_inv_req      ( cache_inv         ),
	.VBR_out            ( dbg_vbr           ),
	.pmmu_walker_req    ( wk_req            ),
	.pmmu_walker_we     ( wk_we             ),
	.pmmu_walker_addr   ( wk_addr           ),
	.pmmu_walker_wdat   ( wk_wdat           ),
	.pmmu_walker_ack    ( wk_ack            ),
	.pmmu_walker_data   ( wk_data           ),
	.pmmu_walker_berr   ( wk_berr           ),
	.debug_pmmu_busy    ( pmmu_busy         ),
	.debug_pmmu_fault   ( pmmu_fault        ),
	.debug_decodeOPC    ( dbg_decode        ),
	.debug_last_opc_pc  ( dbg_pc            ),
	.debug_opcode       ( dbg_opcode        ),
	.debug_trap_vector  ( dbg_trap_vector   ),
	.debug_cpu_halted   ( dbg_halted        ),
	.debug_pmmu_fault_status ( dbg_pmmu_fstat ),
	.debug_memaddr_reg  ( dbg_memaddr       ),
	.debug_exe_PC       ( dbg_exe_pc        )
);
assign dbg_kfc = k_fc;
assign dbg_krw = k_rw;

assign early_addr     = k_addr;
assign dbg_clkena     = tg68_clkena;
assign dbg_pmmu_busy  = pmmu_busy;
assign dbg_pmmu_fault = pmmu_fault;

endmodule
