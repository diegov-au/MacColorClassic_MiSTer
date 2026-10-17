/* verilator lint_off UNUSED */

/* based on minimigmac by Benjamin Herrenschmidt */

`define RREG_CDR        3'h0
`define RREG_ICR        3'h1
`define RREG_MR         3'h2
`define RREG_TCR        3'h3
`define RREG_CSR        3'h4
`define RREG_BSR        3'h5
`define RREG_IDR        3'h6
`define RREG_RST        3'h7

`define WREG_ODR        3'h0
`define WREG_ICR        3'h1
`define WREG_MR         3'h2
`define WREG_TCR        3'h3
`define WREG_SER        3'h4
`define WREG_DMAS       3'h5
`define WREG_DMATR      3'h6
`define WREG_IDMAR      3'h7

`define MR_DMA_MODE     1
`define MR_ARB          0

`define ICR_A_RST       7
`define ICR_TEST_MODE   6
`define ICR_DIFF_ENBL   5
`define ICR_A_ACK       4
`define ICR_A_BSY       3
`define ICR_A_SEL       2
`define ICR_A_ATN       1
`define ICR_A_DATA      0

`define TCR_A_REQ       3
`define TCR_A_MSG       2
`define TCR_A_CD        1
`define TCR_A_IO        0

module ncr5380
(
	input    		clk,
	input 	     	reset,

	input         bus_cs,
	input   [2:0] bus_rs,
	input         ior,
	input         iow,
	input         dack,
	output        dreq,
	input   [7:0] wdata,
	output  [7:0] rdata,

	input  [DEVS-1:0] img_mounted,
	input      [31:0] img_size,
	
	output reg [31:0] io_lba[DEVS],
	output [DEVS-1:0] io_rd,
	output [DEVS-1:0] io_wr,
	output      [5:0] io_blk_cnt[DEVS],
	input             wr_batch,
	input  [DEVS-1:0] io_ack,

	input        [7:0] sd_buff_addr,
	input        [4:0] sd_buff_addr_hi,
	input       [15:0] sd_buff_dout,
	output      [15:0] sd_buff_din[DEVS],
	input              sd_buff_wr,

	input              cd_enable,

	output signed [15:0] cd_snd_l,
	output signed [15:0] cd_snd_r

	,output            bus_hold
);
	parameter DEVS = 2;
	parameter CD_DEV = DEVS;
	parameter WDOG_LOG = 22;
	parameter IOWDOG_LOG = 24;
	parameter SPINUP_LOG = 27;

	wire bus_data_phase = scsi_bsy & ~scsi_cd & ~scsi_msg;

	wire dma_wr_wait = dma_en & bus_data_phase & ~scsi_io & (|target_holdoff);
	assign dreq = (scsi_req | dma_wr_wait) & dma_en;

	assign bus_hold = bus_cs & dack & (ior | iow) & dma_en & (|target_holdoff);

	reg  [7:0] mr;
	reg  [7:0] icr;
	reg  [3:0] tcr;
	wire [7:0] csr;

	reg  [7:0] din;
	reg  [7:0] dout;
	reg        dma_en;

	reg dma_wr;
	reg reg_wr;
	reg dma_ack;

	wire i_dma_rd = bus_cs &  dack & ior;
	wire i_dma_wr = bus_cs &  dack & iow;
	wire i_reg_wr = bus_cs & ~dack & iow;

	always @(posedge clk) begin
		reg old_dma_rd, old_dma_wr, old_reg_wr;

		old_dma_rd <= i_dma_rd;
		old_dma_wr <= i_dma_wr;
		old_reg_wr <= i_reg_wr;

		dma_wr <= 0;
		dma_ack <= 0;
		reg_wr <= 0;

		if(~old_dma_wr & i_dma_wr) dma_wr <= 1;
		if(~old_reg_wr & i_reg_wr) reg_wr <= 1;
		if((old_dma_wr & ~i_dma_wr) | (old_dma_rd & ~i_dma_rd)) dma_ack <= dma_en & bus_data_phase;
	end

	assign rdata = dack                ? cur_data         :
	               bus_rs == `RREG_CDR ? cur_data         :
	               bus_rs == `RREG_ICR ? icr_read         :
	               bus_rs == `RREG_MR  ? mr               :
	               bus_rs == `RREG_TCR ? { 4'h0, tcr }    :
	               bus_rs == `RREG_CSR ? csr              :
	               bus_rs == `RREG_BSR ? bsr              :
	               bus_rs == `RREG_IDR ? cur_data         :
	               bus_rs == `RREG_RST ? 8'hff            :
	               8'hff;

	always@(posedge clk) if((reg_wr && bus_rs == `WREG_ODR) || dma_wr) dout <= wdata;

	wire [7:0] cur_data = out_en ? dout : din;

	wire       out_en = icr[`ICR_A_DATA] | mr[`MR_ARB];

	wire [7:0] icr_read = { icr[`ICR_A_RST],
	                        icr_aip,
	                        icr_la,
	                        icr[`ICR_A_ACK],
	                        icr[`ICR_A_BSY],
	                        icr[`ICR_A_SEL],
	                        icr[`ICR_A_ATN],
	                        icr[`ICR_A_DATA] };

	always@(posedge clk or posedge reset) begin
		if (reset) begin
			icr <= 0;
		end else if (reg_wr && (bus_rs == `WREG_ICR)) begin
			icr <= wdata;
		end
	end
   
	always@(posedge clk or posedge reset) begin
		if (reset) mr <= 8'b0;
		else if (reg_wr && (bus_rs == `WREG_MR)) mr <= wdata;
	end
   
	always@(posedge clk or posedge reset) begin
		if (reset) tcr <= 4'b0;
		else if (reg_wr && (bus_rs == `WREG_TCR)) tcr <= wdata[3:0];
	end
   
	always@(posedge clk or posedge reset) begin
		if (reset) begin
			dma_en <= 0;
		end else begin
			if (!mr[`MR_DMA_MODE]) begin
				dma_en <= 0;
			end else if (reg_wr && (bus_rs == `WREG_DMAS)) begin
				dma_en <= 1;
			end else if (reg_wr && (bus_rs == `WREG_IDMAR)) begin
				dma_en <= 1;
			end
		end
	end

	assign csr = { scsi_rst, scsi_bsy, scsi_req & ~req_deferred, scsi_msg,
	               scsi_cd, scsi_io, scsi_sel, 1'b0 };	

	wire bsr_eodma = ~bus_data_phase;
	wire bsr_dmarq = (scsi_req | dma_wr_wait) & dma_en;
	wire bsr_perr = 1'b0;
	wire bsr_irq = irq_latch;
	wire bsr_pmatch = 
	         tcr[`TCR_A_MSG] == scsi_msg &&
	         tcr[`TCR_A_CD ] == scsi_cd  &&
	         tcr[`TCR_A_IO ] == scsi_io;

	reg  berr_latch;
	wire bsr_berr = berr_latch;
	wire [7:0] bsr = { bsr_eodma, bsr_dmarq, bsr_perr, bsr_irq,
	                   bsr_pmatch, bsr_berr, scsi_atn, scsi_ack };

	wire scsi_bsy = 
	    icr[`ICR_A_BSY] |
	    |target_bsy |
	    mr[`MR_ARB];

	wire icr_aip = mr[`MR_ARB];
	wire icr_la = 0;

	wire scsi_sel = icr[`ICR_A_SEL];
	wire scsi_rst = icr[`ICR_A_RST];
	wire scsi_ack = icr[`ICR_A_ACK] | dma_ack;
	wire scsi_atn = icr[`ICR_A_ATN];

	reg scsi_cd, scsi_io, scsi_msg, scsi_req;

	always @* begin
		integer i;
		scsi_cd = 0;
		scsi_io = 0;
		scsi_msg = 0;
		scsi_req = 0;
		din = 8'h55;

		for (i = 0; i < DEVS; i = i + 1) begin
			if (target_bsy[i]) begin
				scsi_cd = target_cd[i];
				scsi_io = target_io[i];
				scsi_msg = target_msg[i];
				scsi_req = target_req[i];
				din = target_dout[i];
			end
		end
	end

	/*
 ---- 5380 completion semantics (ported from MacLC_MiSTer) -------------
*/

	wire csr_rd = bus_cs & ~dack & ~iow & (bus_rs == `RREG_CSR);
	wire rst_rd = bus_cs & ~dack & ~iow & (bus_rs == `RREG_RST);

	reg req_deferred;
	reg [9:0] defer_age;
	reg old_req_bus_d;
	reg old_csr_rd_d;
	always @(posedge clk or posedge reset) begin
		if (reset) begin
			req_deferred  <= 1'b0;
			old_req_bus_d <= 1'b0;
			old_csr_rd_d  <= 1'b0;
		end else begin
			old_req_bus_d <= scsi_req;
			old_csr_rd_d  <= csr_rd;
			if (~old_req_bus_d & scsi_req)
				req_deferred <= 1'b1;
			else if (req_deferred & old_csr_rd_d & ~csr_rd)
				req_deferred <= 1'b0;
			if (!req_deferred) defer_age <= 10'd0;
			else if (~&defer_age) defer_age <= defer_age + 10'd1;
			if (&defer_age) req_deferred <= 1'b0;
			if (!scsi_req)
				req_deferred <= 1'b0;
		end
	end

	reg irq_latch;
	reg dma_armed;
	reg pmatch_d;
	reg old_rst_rd;
	always @(posedge clk or posedge reset) begin
		if (reset) begin
			irq_latch  <= 1'b0;
			dma_armed  <= 1'b0;
			pmatch_d   <= 1'b1;
			old_rst_rd <= 1'b0;
		end else begin
			old_rst_rd <= rst_rd;
			pmatch_d   <= bsr_pmatch;
			if (reg_wr && (bus_rs == `WREG_DMAS || bus_rs == `WREG_IDMAR))
				dma_armed <= 1'b1;
			if (~old_rst_rd & rst_rd)
				irq_latch <= 1'b0;
			if (dma_armed && pmatch_d && !bsr_pmatch) begin
				irq_latch <= 1'b1;
				dma_armed <= 1'b0;
			end
			if (scsi_rst) begin
				irq_latch <= 1'b0;
				dma_armed <= 1'b0;
			end
		end
	end

	reg berr_bsy_d;
	reg berr_rst_rd_d;
	always @(posedge clk or posedge reset) begin
		if (reset) begin
			berr_latch    <= 1'b0;
			berr_bsy_d    <= 1'b0;
			berr_rst_rd_d <= 1'b0;
		end else begin
			berr_bsy_d    <= scsi_bsy;
			berr_rst_rd_d <= rst_rd;
			if (~berr_rst_rd_d & rst_rd) berr_latch <= 1'b0;
			if (dma_en && berr_bsy_d && !scsi_bsy) berr_latch <= 1'b1;
			if (scsi_rst) berr_latch <= 1'b0;
		end
	end

	wire [DEVS-1:0] target_holdoff;

	wire [DEVS-1:0] target_bsy;
	wire [DEVS-1:0] target_msg;
	wire [DEVS-1:0] target_io;
	wire [DEVS-1:0] target_cd;
	wire [DEVS-1:0] target_req;
	wire      [7:0] target_dout[DEVS];
	wire signed [15:0] target_snd_l[DEVS];
	wire signed [15:0] target_snd_r[DEVS];

	generate
		genvar i;
		for (i = 0; i < DEVS; i = i + 1) begin : target
			scsi #(.ID((i == CD_DEV) ? 3'd3 : (i == 0) ? 3'd0 : 3'd5),
			       .CDROM((i == CD_DEV) ? 1 : 0), .WDOG_LOG(WDOG_LOG), .IOWDOG_LOG(IOWDOG_LOG),
			       .SPINUP_LOG(SPINUP_LOG)) target
			(
				.clk    ( clk ),
				.rst    ( scsi_rst ),
				.sys_rst( reset ),
				.bus_busy( |target_bsy ),
				.cd_enable( (i == CD_DEV) ? cd_enable : 1'b0 ),
				.sel    ( scsi_sel ),
				.atn    ( scsi_atn ),

				.ack    ( scsi_ack ),

				.bsy    ( target_bsy[i]  ),
				.msg    ( target_msg[i]  ),
				.cd     ( target_cd[i]   ),
				.io     ( target_io[i]   ),
				.req    ( target_req[i]  ),
				.dout   ( target_dout[i] ),

				.din    ( dout ),

				.img_mounted(img_mounted[i]),
				.img_blocks(img_size),
				.io_lba ( io_lba[i] ),
				.io_rd  ( io_rd[i] ),
				.io_wr  ( io_wr[i] ),
				.io_blk_cnt ( io_blk_cnt[i] ),
				.wr_batch   ( wr_batch ),
				.io_ack ( (i == CD_DEV) ? io_ack[i] : (io_ack[i] & target_bsy[i]) ),

				.sd_buff_addr( sd_buff_addr ),
				.sd_buff_addr_hi( sd_buff_addr_hi ),
				.sd_buff_dout( sd_buff_dout ),
				.sd_buff_din( sd_buff_din[i] ),
				.sd_buff_wr( sd_buff_wr & io_ack[i] ),

				.data_holdoff( target_holdoff[i] ),
				.cd_snd_l( target_snd_l[i] ),
				.cd_snd_r( target_snd_r[i] )
			);
		end
	endgenerate

	generate if (CD_DEV < DEVS) begin : g_cd_snd
		assign cd_snd_l = target_snd_l[CD_DEV];
		assign cd_snd_r = target_snd_r[CD_DEV];
	end else begin : g_no_cd_snd
		assign cd_snd_l = 16'sd0;
		assign cd_snd_r = 16'sd0;
	end endgenerate

endmodule
