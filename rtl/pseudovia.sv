// Mac LC Pseudo-VIA
// Based on MAME's pseudovia.cpp by R. Belmont
// Color Classic (M1, 2026-10-06): taken unchanged from the MacLC core
// (docs/reference/maclc_mister/rtl/pseudovia.sv). Spice's pseudo-VIA is the

module pseudovia(
    input clk_sys,
    input reset,
    input soft_rst,

    input [12:0] addr,
    input [7:0] data_in,
    output reg [7:0] data_out,
    input we,
    input req,

    input vblank_irq,
    input slot_irq,
    input asc_irq,
    input scsi_irq,
    input scsi_drq,
    output reg irq_out,

    input [7:0] ram_config,
    input [3:0] monitor_id,

    output reg [7:0] video_config,

    output [7:0] ram_config_out,

    output reg ram_configured
);

assign ram_config_out = ram_cfg;

reg [7:0] port_b;
reg [7:0] ram_cfg;
reg [7:0] ifr;
reg [7:0] slot_ier;
reg [7:0] ier;

reg  vbl_flag_n = 1'b1;
reg  vbl_lvl_d  = 1'b0;
reg  asc_irq_d  = 1'b0;
wire [7:0] slot_status = {1'b0, vbl_flag_n, ~slot_irq, 1'b1, 3'b111, 1'b1};

wire [7:0] slot_irqs = (~slot_status) & 8'h78;
wire [7:0] slot_irqs_masked = slot_irqs & (slot_ier & 8'h78);
wire any_slot_irq = |slot_irqs_masked;

wire [7:0] ifr_live = { ifr[7], ifr[6], ifr[5], ifr[4], scsi_irq, ifr[2], any_slot_irq, scsi_drq };

wire irq_pending = |(ifr_live & ier & 8'h1B);

integer pvia_reg10_reads = 0;

wire [7:0] native_offset = addr[7:0];
wire [2:0] reg_sel = {addr[4], addr[1:0]};
wire native_reg_valid = (native_offset[7:5] == 3'b000) && (native_offset[3:2] == 2'b00);

wire is_native = (addr[12:8] == 5'b00000);
wire [3:0] compat_reg = addr[12:9];

always @(posedge clk_sys) begin
    if (reset) begin
        port_b <= 8'h00;
        ram_cfg <= ram_config;
        ram_configured <= 1'b0;
        ifr <= 8'h00;
        slot_ier <= 8'h00;
        ier <= 8'h00;
        irq_out <= 1'b0;
        video_config <= 8'h03;
        vbl_flag_n <= 1'b1;
        vbl_lvl_d  <= 1'b0;
        asc_irq_d  <= 1'b0;
    end else if (soft_rst) begin
        ifr        <= 8'h00;
        slot_ier   <= 8'h00;
        ier        <= 8'h00;
        irq_out    <= 1'b0;
        vbl_flag_n <= 1'b1;
    end else begin
        vbl_lvl_d <= vblank_irq;
        if (!vbl_lvl_d && vblank_irq)
            vbl_flag_n <= 1'b0;
        else if (vbl_lvl_d && !vblank_irq)
            vbl_flag_n <= 1'b1;

        if (any_slot_irq)
            ifr[1] <= 1'b1;
        else
            ifr[1] <= 1'b0;

        asc_irq_d <= asc_irq;
        if (!asc_irq_d && asc_irq)
            ifr[4] <= 1'b1;

        if (scsi_irq)
            ifr[3] <= 1'b1;
        else
            ifr[3] <= 1'b0;

        if (scsi_drq)
            ifr[0] <= 1'b1;
        else
            ifr[0] <= 1'b0;

        if (irq_pending) begin
            ifr[7] <= 1'b1;
            irq_out <= 1'b1;
        end else begin
            ifr[7] <= 1'b0;
            irq_out <= 1'b0;
        end

        if (req) begin
            if (is_native && native_reg_valid) begin
                if (we) begin
                    case (reg_sel)
                        3'b000: begin
                            port_b <= data_in;
                            `ifdef VERBOSE_TRACE
                            $display("PVIA: WRITE Port B = %02x @%0t", data_in, $time);
                            `endif
                        end

                        3'b001: begin
                            ram_cfg <= data_in;
                            ram_configured <= 1'b1;
                            `ifdef VERBOSE_TRACE
                            $display("PVIA: WRITE RAM Config = %02x @%0t", data_in, $time);
                            `endif
                        end

                        3'b010: begin
                            if (data_in[6])
                                vbl_flag_n <= 1'b1;
                            `ifdef VERBOSE_TRACE
                            $display("PVIA: WRITE Slot Status = %02x @%0t", data_in, $time);
                            `endif
                        end

                        3'b011: begin
                            ifr <= ifr & ~(data_in & 8'h7F);
                            `ifdef VERBOSE_TRACE
                            $display("PVIA: WRITE IFR ACK %02x (clearing bits) @%0t", data_in & 8'h7F, $time);
                            `endif
                        end

                        3'b100: begin
                            video_config <= data_in;
                            `ifdef VERBOSE_TRACE
                            $display("PVIA: WRITE Video Config = %02x (bpp mode = %d) addr=%h @%0t",
                                     data_in, data_in[2:0], addr, $time);
                            `endif
                            `ifdef ARIEL_TRACE
                            $display("PVIA VIDMODE=%02x @%0t", data_in, $time);
                            `endif
                        end

                        3'b101: ;

                        3'b110: begin
                            if (data_in[7])
                                slot_ier <= slot_ier | (data_in & 8'h7F);
                            else
                                slot_ier <= slot_ier & ~(data_in & 8'h7F);
                            `ifdef VERBOSE_TRACE
                            $display("PVIA: WRITE Slot IER = %02x @%0t", data_in, $time);
                            `endif
                        end

                        3'b111: begin
                            if (data_in[7]) begin
                                ier <= ier | (data_in & 8'h7F);
                                if (data_in == 8'hFF)
                                    ier <= 8'h1F;
                            end else begin
                                ier <= ier & ~(data_in & 8'h7F);
                            end
                            `ifdef VERBOSE_TRACE
                            $display("PVIA: WRITE IER = %02x @%0t", data_in, $time);
                            `endif
                        end
                    endcase
                end else begin
                    case (reg_sel)
                        3'b000: begin
                            data_out <= 8'h00;
                            `ifdef VERBOSE_TRACE
                            $display("PVIA: READ Port B -> %02x @%0t", port_b, $time);
                            `endif
                        end

                        3'b001: begin
                            data_out <= ram_cfg | 8'h04;
                            `ifdef VERBOSE_TRACE
                            $display("PVIA: READ RAM Config -> %02x @%0t", ram_cfg | 8'h04, $time);
                            `endif
                        end

                        3'b010: begin
                            data_out <= slot_status;
                            `ifdef VERBOSE_TRACE
                            $display("PVIA: READ Slot Status -> %02x @%0t", slot_status, $time);
                            `endif
                        end

                        3'b011: begin
                            data_out <= ifr;
                            `ifdef VERBOSE_TRACE
                            $display("PVIA: READ IFR -> %02x @%0t", ifr, $time);
                            `endif
                        end

                        3'b100: begin
                            data_out <= {1'b0, monitor_id[3:0], 3'b000};
                            pvia_reg10_reads <= pvia_reg10_reads + 1;
                            `ifdef VERBOSE_TRACE
                            $display("PVIA: READ Video Config -> %02x @%0t",
                                     {1'b0, monitor_id[3:0], 3'b000}, $time);
                            `endif
                        end

                        3'b101: begin
                            data_out <= 8'h00;
                        end

                        3'b110: begin
                            data_out <= slot_ier & 8'h7F;
                            `ifdef VERBOSE_TRACE
                            $display("PVIA: READ Slot IER -> %02x @%0t", slot_ier & 8'h7F, $time);
                            `endif
                        end

                        3'b111: begin
                            data_out <= ier & 8'h7F;
                            `ifdef VERBOSE_TRACE
                            $display("PVIA: READ IER -> %02x @%0t", ier & 8'h7F, $time);
                            `endif
                        end
                    endcase
                end
            end else if (!is_native) begin
                if (we) begin
                    case (compat_reg)
                        4'd13: begin
                            ifr <= ifr & ~(data_in & 8'h7F);
                            `ifdef VERBOSE_TRACE
                            $display("PVIA COMPAT: WRITE IFR ACK %02x @%0t", data_in & 8'h7F, $time);
                            `endif
                        end
                        4'd14: begin
                            if (data_in[7])
                                ier <= ier | (data_in & 8'h7F);
                            else
                                ier <= ier & ~(data_in & 8'h7F);
                            `ifdef VERBOSE_TRACE
                            $display("PVIA COMPAT: WRITE IER = %02x @%0t", data_in, $time);
                            `endif
                        end
                        default: begin
                            `ifdef VERBOSE_TRACE
                            $display("PVIA COMPAT: WRITE unknown reg %0d = %02x @%0t", compat_reg, data_in, $time);
                            `endif
                        end
                    endcase
                end else begin
                    case (compat_reg)
                        4'd13: begin
                            data_out <= ifr;
                            `ifdef VERBOSE_TRACE
                            $display("PVIA COMPAT: READ IFR -> %02x @%0t", ifr, $time);
                            `endif
                        end
                        4'd14: begin
                            data_out <= ier;
                            `ifdef VERBOSE_TRACE
                            $display("PVIA COMPAT: READ IER -> %02x @%0t", ier, $time);
                            `endif
                        end
                        default: begin
                            data_out <= 8'h00;
                            `ifdef VERBOSE_TRACE
                            $display("PVIA COMPAT: READ unknown reg %0d @%0t", compat_reg, $time);
                            `endif
                        end
                    endcase
                end
            end
        end
    end
end

endmodule
