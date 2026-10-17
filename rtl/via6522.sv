///////////////////////////////////////////////////////////////////////////////
// Title      : VIA 6522
///////////////////////////////////////////////////////////////////////////////
// Author     : Gideon Zweijtzer  <gideon.zweijtzer@gmail.com>
///////////////////////////////////////////////////////////////////////////////
//              Thanks to gyurco for ironing out some
//              differences that were left unnoticed.
///////////////////////////////////////////////////////////////////////////////
// License:     GPL 3.0 - Free to use, distribute and change to your own needs.
//              Leaving a reference to the author will be highly appreciated.
///////////////////////////////////////////////////////////////////////////////

module via6522 (
	input  wire       clock,
	input  wire       rising,
	input  wire       falling,
	input  wire       reset,

	input  wire [3:0] addr,
	input  wire       wen,
	input  wire       ren,
	input  wire [7:0] data_in,
	output reg  [7:0] data_out,

	output reg        phi2_ref,

	output wire [7:0] port_a_o,
	output wire [7:0] port_a_t,
	input  wire [7:0] port_a_i,

	output wire [7:0] port_b_o,
	output wire [7:0] port_b_t,
	input  wire [7:0] port_b_i,

	input  wire       ca1_i,

	output reg        ca2_o,
	input  wire       ca2_i,
	output wire       ca2_t,

	output wire       cb1_o,
	input  wire       cb1_i,
	output wire       cb1_t,

	output wire       cb2_o,
	input  wire       cb2_i,
	output wire       cb2_t,

	output wire       irq,

	output wire [3:0] dbg_ext_cnt,
	output wire [7:0] dbg_acr,
	output wire [6:0] dbg_ifr,
	output wire [6:0] dbg_ier,
	output wire [7:0] dbg_sr,
	output wire       dbg_sr_done
);

	localparam [15:0] latch_reset_pattern = 16'h5550;

	reg  [7:0] pio_pra  = 8'h00;
	reg  [7:0] pio_ddra = 8'h00;
	reg  [7:0] pio_prb  = 8'h00;
	reg  [7:0] pio_ddrb = 8'h00;

	reg  [7:0] port_a_c = 8'h00;
	reg  [7:0] port_b_c = 8'h00;

	reg  [6:0] irq_mask   = 7'h00;
	reg  [6:0] irq_flags  = 7'h00;
	wire [6:0] irq_events;
	reg        irq_out;

	reg [15:0] timer_a_latch = latch_reset_pattern;
	reg [15:0] timer_b_latch = latch_reset_pattern;
	reg [15:0] timer_a_count = latch_reset_pattern;
	reg [15:0] timer_b_count = latch_reset_pattern;
	wire       timer_a_out;
	reg        timer_b_tick;

	reg  [7:0] acr = 8'h00, pcr = 8'h00;
	reg  [7:0] shift_reg = 8'h00;
	wire       serport_en;
	wire       ser_cb2_o;
	reg        hs_cb2_o;
	wire       cb1_t_int;
	wire       cb1_o_int;
	wire       cb2_t_int;
	wire       cb2_o_int;

	wire ca2_event, ca1_event, serial_event, cb2_event, cb1_event, timer_b_event, timer_a_event;
	assign irq_events = {timer_a_event, timer_b_event, cb1_event, cb2_event, serial_event, ca1_event, ca2_event};

	wire       tmr_a_output_en    = acr[7];
	wire       tmr_a_freerun      = acr[6];
	wire       tmr_b_count_mode   = acr[5];
	wire       shift_dir          = acr[4];
	wire [1:0] shift_clk_sel      = acr[3:2];
	wire [2:0] shift_mode_control = acr[4:2];
	wire       pb_latch_en        = acr[1];
	wire       pa_latch_en        = acr[0];

	wire       cb2_is_output      = pcr[7];
	wire       cb2_edge_select    = pcr[6];
	wire       cb2_no_irq_clr     = pcr[5];
	wire [1:0] cb2_out_mode       = pcr[6:5];
	wire       cb1_edge_select    = pcr[4];

	wire       ca2_is_output      = pcr[3];
	wire       ca2_edge_select    = pcr[2];
	wire       ca2_no_irq_clr     = pcr[1];
	wire [1:0] ca2_out_mode       = pcr[2:1];
	wire       ca1_edge_select    = pcr[0];

	reg  [7:0] ira = 8'h00, irb = 8'h00;

	wire       write_t1c_l;
	wire       write_t1c_h;
	wire       write_t2c_h;

	reg        ca1_c, ca2_c;
	reg        cb1_c, cb2_c;
	reg        ca1_d, ca2_d;
	reg        cb1_d, cb2_d;

	reg        ca2_handshake_o;
	reg        ca2_pulse_o;
	reg        cb2_handshake_o;
	reg        cb2_pulse_o;
	reg        shift_active;

	assign irq = irq_out;

	assign write_t1c_l = ((addr == 4'h4) || (addr == 4'h6)) && wen && falling;
	assign write_t1c_h = (addr == 4'h5) && wen && falling;
	assign write_t2c_h = (addr == 4'h9) && wen && falling;

	assign ca1_event = (ca1_c ^ ca1_d) & (ca1_d ^ ca1_edge_select);
	assign ca2_event = (ca2_c ^ ca2_d) & (ca2_d ^ ca2_edge_select);
	assign cb1_event = (cb1_c ^ cb1_d) & (cb1_d ^ cb1_edge_select);
	assign cb2_event = (cb2_c ^ cb2_d) & (cb2_d ^ cb2_edge_select);

	assign ca2_t     = ca2_is_output;
	assign cb2_t_int = serport_en ? shift_dir : cb2_is_output;
	assign cb2_o_int = serport_en ? ser_cb2_o : hs_cb2_o;

	assign cb1_t = cb1_t_int;
	assign cb1_o = cb1_o_int;
	assign cb2_t = cb2_t_int;
	assign cb2_o = cb2_o_int;

	always @(*) begin
		case (ca2_out_mode)
			2'b00:   ca2_o = ca2_handshake_o;
			2'b01:   ca2_o = ca2_pulse_o;
			2'b10:   ca2_o = 1'b0;
			default: ca2_o = 1'b1;
		endcase
	end

	always @(*) begin
		case (cb2_out_mode)
			2'b00:   hs_cb2_o = cb2_handshake_o;
			2'b01:   hs_cb2_o = cb2_pulse_o;
			2'b10:   hs_cb2_o = 1'b0;
			default: hs_cb2_o = 1'b1;
		endcase
	end

	always @(*) begin
		if ((irq_flags & irq_mask) == 7'b0000000)
			irq_out = 1'b0;
		else
			irq_out = 1'b1;
	end

	always @(posedge clock) begin
		if (rising)
			phi2_ref <= 1'b1;
		else if (falling)
			phi2_ref <= 1'b0;
	end

	always @(posedge clock) begin
		ca1_c <= ca1_i;
		ca2_c <= ca2_i;
		if (cb1_t_int == 1'b0)
			cb1_c <= cb1_i;
		else
			cb1_c <= cb1_o_int;
		if (cb2_t_int == 1'b0)
			cb2_c <= cb2_i;
		else
			cb2_c <= cb2_o_int;

		ca1_d <= ca1_c;
		ca2_d <= ca2_c;
		cb1_d <= cb1_c;
		cb2_d <= cb2_c;

		port_a_c <= port_a_i;
		port_b_c <= port_b_i;

		if (pa_latch_en == 1'b0 || ca1_event == 1'b1)
			ira <= port_a_c;

		if (pb_latch_en == 1'b0 || cb1_event == 1'b1)
			irb <= port_b_c;

		if (ca1_event)
			ca2_handshake_o <= 1'b1;
		else if ((ren || wen) && addr == 4'h1 && falling)
			ca2_handshake_o <= 1'b0;

		if (falling) begin
			if ((ren || wen) && addr == 4'h1)
				ca2_pulse_o <= 1'b0;
			else
				ca2_pulse_o <= 1'b1;
		end

		if (cb1_event)
			cb2_handshake_o <= 1'b1;
		else if ((ren || wen) && addr == 4'h0 && falling)
			cb2_handshake_o <= 1'b0;

		if (falling) begin
			if ((ren || wen) && addr == 4'h0)
				cb2_pulse_o <= 1'b0;
			else
				cb2_pulse_o <= 1'b1;
		end

		irq_flags <= irq_flags | irq_events;

		if (wen && falling) begin
			case (addr)
				4'h0: begin
					pio_prb <= data_in;
					if (cb2_no_irq_clr == 1'b0)
						irq_flags[3] <= 1'b0;
					irq_flags[4] <= 1'b0;
				end

				4'h1: begin
					pio_pra <= data_in;
					if (ca2_no_irq_clr == 1'b0)
						irq_flags[0] <= 1'b0;
					irq_flags[1] <= 1'b0;
				end

				4'h2: pio_ddrb <= data_in;

				4'h3: pio_ddra <= data_in;

				4'h4: timer_a_latch[7:0] <= data_in;

				4'h5: begin
					timer_a_latch[15:8] <= data_in;
					irq_flags[6] <= 1'b0;
				end

				4'h6: timer_a_latch[7:0] <= data_in;

				4'h7: begin
					timer_a_latch[15:8] <= data_in;
					irq_flags[6] <= 1'b0;
				end

				4'h8: timer_b_latch[7:0] <= data_in;

				4'h9: irq_flags[5] <= 1'b0;

				4'hA: irq_flags[2] <= 1'b0;

				4'hB: acr <= data_in;

				4'hC: pcr <= data_in;

				4'hD: irq_flags <= (irq_flags & ~data_in[6:0]) | irq_events;

				4'hE: begin
					if (data_in[7])
						irq_mask <= irq_mask | data_in[6:0];
					else
						irq_mask <= irq_mask & ~data_in[6:0];
				end

				4'hF: pio_pra <= data_in;

				default: ;
			endcase
		end

		data_out <= 8'h00;
		case (addr)
			4'h0: begin
				data_out <= (pio_prb & pio_ddrb) | (irb & ~pio_ddrb);
				if (tmr_a_output_en)
					data_out[7] <= timer_a_out;
			end
			4'h1: data_out <= ira;
			4'h2: data_out <= pio_ddrb;
			4'h3: data_out <= pio_ddra;
			4'h4: data_out <= timer_a_count[7:0];
			4'h5: data_out <= timer_a_count[15:8];
			4'h6: data_out <= timer_a_latch[7:0];
			4'h7: data_out <= timer_a_latch[15:8];
			4'h8: data_out <= timer_b_count[7:0];
			4'h9: data_out <= timer_b_count[15:8];
			4'hA: data_out <= shift_reg;
			4'hB: data_out <= acr;
			4'hC: data_out <= pcr;
			4'hD: data_out <= {irq_out, irq_flags};
			4'hE: data_out <= {1'b1, irq_mask};
			4'hF: data_out <= ira;
			default: ;
		endcase

		if (ren && falling) begin
			case (addr)
				4'h0: begin
					if (cb2_no_irq_clr == 1'b0)
						irq_flags[3] <= 1'b0;
					irq_flags[4] <= 1'b0;
				end

				4'h1: begin
					if (ca2_no_irq_clr == 1'b0)
						irq_flags[0] <= 1'b0;
					irq_flags[1] <= 1'b0;
				end

				4'h4: irq_flags[6] <= 1'b0;

				4'h8: irq_flags[5] <= 1'b0;

				4'hA: irq_flags[2] <= 1'b0;

				default: ;
			endcase
		end

		if (reset) begin
			pio_pra         <= 8'h00;
			pio_ddra        <= 8'h00;
			pio_prb         <= 8'h00;
			pio_ddrb        <= 8'h00;
			irq_mask        <= 7'h00;
			irq_flags       <= 7'h00;
			acr             <= 8'h00;
			pcr             <= 8'h00;
			ca2_handshake_o <= 1'b1;
			ca2_pulse_o     <= 1'b1;
			cb2_handshake_o <= 1'b1;
			cb2_pulse_o     <= 1'b1;
			timer_a_latch   <= latch_reset_pattern;
			timer_b_latch   <= latch_reset_pattern;
		end
	end

	assign port_a_o      = pio_pra;
	assign port_b_o[6:0] = pio_prb[6:0];
	assign port_b_o[7]   = tmr_a_output_en ? timer_a_out : pio_prb[7];

	assign port_a_t      = pio_ddra;
	assign port_b_t[6:0] = pio_ddrb[6:0];
	assign port_b_t[7]   = pio_ddrb[7] | tmr_a_output_en;

	reg timer_a_reload;
	reg timer_a_toggle;
	reg timer_a_may_interrupt;

	always @(posedge clock) begin
		if (falling) begin
			if (timer_a_reload) begin
				timer_a_count <= timer_a_latch;
				if (write_t1c_l)
					timer_a_count[7:0] <= data_in;
				timer_a_reload <= 1'b0;
				timer_a_may_interrupt <= timer_a_may_interrupt & tmr_a_freerun;
			end
			else begin
				if (timer_a_count == 16'h0000)
					timer_a_reload <= 1'b1;
				timer_a_count <= timer_a_count - 16'h0001;
			end
		end

		if (rising) begin
			if (timer_a_event && tmr_a_output_en)
				timer_a_toggle <= ~timer_a_toggle;
		end

		if (write_t1c_h) begin
			timer_a_may_interrupt <= 1'b1;
			timer_a_toggle <= ~tmr_a_output_en;
			timer_a_count  <= {data_in, timer_a_latch[7:0]};
			timer_a_reload <= 1'b0;
		end

		if (reset) begin
			timer_a_may_interrupt <= 1'b0;
			timer_a_toggle <= 1'b1;
			timer_a_count  <= latch_reset_pattern;
			timer_a_reload <= 1'b0;
		end
	end

	assign timer_a_out   = timer_a_toggle;
	assign timer_a_event = rising & timer_a_reload & timer_a_may_interrupt;

	reg timer_b_reload_lo;
	reg timer_b_oneshot_trig;
	reg timer_b_timeout;
	reg pb6_c, pb6_d;

	always @(posedge clock) begin : tmr_b
		reg timer_b_decrement;
		timer_b_decrement = 1'b0;

		if (rising) begin
			pb6_c <= port_b_i[6];
			pb6_d <= pb6_c;
		end

		if (falling) begin
			timer_b_timeout <= 1'b0;
			timer_b_tick    <= 1'b0;

			if (tmr_b_count_mode) begin
				if (pb6_d == 1'b1 && pb6_c == 1'b0)
					timer_b_decrement = 1'b1;
			end
			else
				timer_b_decrement = 1'b1;

			if (timer_b_decrement) begin
				if (timer_b_count == 16'h0000) begin
					if (timer_b_oneshot_trig) begin
						timer_b_oneshot_trig <= 1'b0;
						timer_b_timeout <= 1'b1;
					end
				end
				if (timer_b_count[7:0] == 8'h00) begin
					case (shift_mode_control)
						3'b001, 3'b101, 3'b100: begin
							timer_b_reload_lo <= 1'b1;
							timer_b_tick <= 1'b1;
						end
						default: ;
					endcase
				end
				timer_b_count <= timer_b_count - 16'h0001;
			end
			if (timer_b_reload_lo) begin
				timer_b_count[7:0] <= timer_b_latch[7:0];
				timer_b_reload_lo <= 1'b0;
			end
		end

		if (write_t2c_h) begin
			timer_b_count <= {data_in, timer_b_latch[7:0]};
			timer_b_oneshot_trig <= 1'b1;
		end

		if (reset) begin
			timer_b_count        <= latch_reset_pattern;
			timer_b_reload_lo    <= 1'b0;
			timer_b_oneshot_trig <= 1'b0;
		end
	end

	assign timer_b_event = rising & timer_b_timeout;

	wire       trigger_serial;
	reg        shift_clock_d;
	reg        shift_clock;
	wire       shift_tick_r;
	wire       shift_tick_f;
	reg        shift_timer_tick;
	reg        ser_cb2_c = 1'b0;
	reg  [2:0] bit_cnt;
	reg        shift_pulse;

	always @(*) begin
		case (shift_clk_sel)
			2'b10:        shift_pulse = 1'b1;
			2'b00, 2'b01: shift_pulse = shift_timer_tick;
			default:      shift_pulse = shift_clock & ~shift_clock_d;
		endcase

		if (shift_active == 1'b0) begin
			if (shift_mode_control == 3'b000)
				shift_pulse = shift_clock & ~shift_clock_d;
			else
				shift_pulse = 1'b0;
		end
	end

	always @(posedge clock) begin
		ser_cb2_c <= cb2_i;

		if (rising) begin
			if (shift_active == 1'b0) begin
				if (shift_mode_control == 3'b000)
					shift_clock <= cb1_i;
				else
					shift_clock <= 1'b1;
			end
			else if (shift_clk_sel == 2'b11)
				shift_clock <= cb1_i;
			else if (shift_pulse)
				shift_clock <= ~shift_clock;

			shift_clock_d <= shift_clock;
		end

		if (falling)
			shift_timer_tick <= timer_b_tick;

		if (reset) begin
			shift_clock   <= 1'b1;
			shift_clock_d <= 1'b1;
		end
	end

	wire       ext_clk_mode = (shift_clk_sel == 2'b11);
	reg        ext_cb1_d = 1'b1;
	reg        ext_cb2_o = 1'b1;
	reg  [3:0] ext_cnt   = 4'd8;
	wire       ext_shift = ext_clk_mode &&
	                       (shift_dir ? (ext_cb1_d && !cb1_i) : (!ext_cb1_d && cb1_i));
	wire       ext_done  = ext_shift && ext_cnt == 4'd1;

	always @(posedge clock) begin
		ext_cb1_d <= cb1_i;
		if (ext_shift) begin
			ext_cnt <= (ext_cnt - 4'd1) & 4'd7;
			if (shift_dir)
				ext_cb2_o <= shift_reg[7];
		end
		if ((ren || wen) && addr == 4'hA && falling)
			ext_cnt <= 4'd8;
		if (reset) begin
			ext_cnt   <= 4'd8;
			ext_cb2_o <= 1'b1;
		end
	end

	assign cb1_t_int = (shift_clk_sel == 2'b11) ? 1'b0 : serport_en;
	assign cb1_o_int = shift_clock_d;
	assign ser_cb2_o = ext_clk_mode ? ext_cb2_o : shift_reg[7];

	assign serport_en     = shift_dir | shift_clk_sel[1] | shift_clk_sel[0];
	assign trigger_serial = (ren || wen) && addr == 4'hA;
	assign shift_tick_r   = ~shift_clock_d & shift_clock;
	assign shift_tick_f   = shift_clock_d & ~shift_clock;

	always @(posedge clock) begin
		if (reset)
			shift_reg <= 8'h00;
		else if (ext_clk_mode) begin
			if (wen && addr == 4'hA && falling)
				shift_reg <= data_in;
			else if (ext_shift)
				shift_reg <= shift_dir ? {shift_reg[6:0], shift_reg[7]}
				                       : {shift_reg[6:0], cb2_i};
		end
		else if (falling) begin
			if (wen && addr == 4'hA)
				shift_reg <= data_in;
			else if (shift_dir && shift_tick_f)
				shift_reg <= {shift_reg[6:0], shift_reg[7]};
			else if (!shift_dir && shift_tick_r)
				shift_reg <= {shift_reg[6:0], ser_cb2_c};
		end
	end

	assign serial_event = ext_clk_mode ? ext_done
	                                   : (shift_tick_r & ~shift_active & rising & serport_en);

	assign dbg_ext_cnt = ext_cnt;
	assign dbg_acr     = acr;
	assign dbg_ifr     = irq_flags;
	assign dbg_ier     = irq_mask;
	assign dbg_sr      = shift_reg;
	assign dbg_sr_done = serial_event;

	always @(posedge clock) begin
		if (falling) begin
			if (shift_active == 1'b0 && shift_mode_control != 3'b000) begin
				if (trigger_serial) begin
					bit_cnt      <= 3'd7;
					shift_active <= 1'b1;
				end
			end
			else begin
				if (shift_clk_sel == 2'b00)
					shift_active <= shift_dir;
				else if (shift_pulse && shift_clock) begin
					if (bit_cnt == 3'd0)
						shift_active <= 1'b0;
					else
						bit_cnt <= bit_cnt - 3'd1;
				end
			end
			if (wen && addr == 4'hA && shift_mode_control != 3'b000) begin
				bit_cnt      <= 3'd7;
				shift_active <= 1'b1;
			end
		end

		if (reset) begin
			shift_active <= 1'b0;
			bit_cnt      <= 3'd0;
		end
	end

endmodule
