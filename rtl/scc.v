`timescale 1ns / 100ps

module scc
(
	input clk,
	input cep,
	input cen,

	input	reset_hw,

	input	cs,
	input	we,
	input [1:0]	rs,
	input [7:0]	wdata,
	output [7:0]	rdata,
	output	_irq,

	input	rxd,
	output	txd,
	input	cts,
	output	rts,

	input	dcd_a,
	input	dcd_b,

	output	wreq
);

	reg [3:0]	rindex;
	reg [3:0]	rindex_latch;
	wire 		wreg_a;
	wire 		wreg_b;

	wire		reset_a;
	wire		reset_b;
	wire		reset;

	wire[7:0] 	data_a ;
	reg [7:0] 	data_b = 0;

	wire [7:0] 	rr0_a;
	wire [7:0] 	rr0_b;
	wire [7:0] 	rr1_a;
	wire [7:0] 	rr1_b;
	wire [7:0] 	rr2_b;
	wire [7:0] 	rr3_a;
	wire [7:0] 	rr10_a;
	wire [7:0] 	rr10_b;
	wire [7:0] 	rr15_a;
	wire [7:0] 	rr15_b;

	reg [7:0] 	wr1_a;
	reg [7:0] 	wr1_b;
	reg [7:0] 	wr2;
	reg [7:0] 	wr3_a;   /* synthesis keep */
	reg [7:0] 	wr3_b;
	reg [7:0] 	wr4_a;
	reg [7:0] 	wr4_b;
	reg [7:0] 	wr5_a;
	reg [7:0] 	wr5_b;
	reg [7:0] 	wr6_a;
	reg [7:0] 	wr6_b;
	reg [7:0] 	wr8_a;
	reg [7:0] 	wr8_b;
	reg [5:0] 	wr9;
	reg [7:0] 	wr10_a;
	reg [7:0] 	wr10_b;
	reg [7:0] 	wr12_a;
	reg [7:0] 	wr12_b;
	reg [7:0] 	wr13_a;
	reg [7:0] 	wr13_b;
	reg [7:0] 	wr14_a;
	reg [7:0] 	wr14_b;
	reg [7:0] 	wr15_a;
	reg [7:0] 	wr15_b;

	reg		latch_open_a;
	reg		latch_open_b;
	reg		cts_latch_a;
	reg		dcd_latch_a;
	reg		dcd_latch_b;
	wire		cts_ip_a;
	wire		dcd_ip_a;
	wire		dcd_ip_b;
	wire		do_latch_a;
	wire		do_latch_b;
	wire		do_extreset_a;
	wire		do_extreset_b;	

	wire		rx_irq_pend_a;
	wire		rx_irq_pend_b;
	wire		tx_irq_pend_a;
	wire		tx_irq_pend_b;
	reg		tx_ip_b = 1'b0;
	reg		hunt_b = 1'b0;
	wire		ex_irq_pend_a;
	wire		ex_irq_pend_b;
	reg		ex_irq_ip_a;
	reg		ex_irq_ip_b;
	wire [2:0] 	rr2_vec_stat;	

	reg [7:0] tx_data_a;
	reg wr8_wr_a;
	reg wr8_wr_b;
		
	assign wreg_a  = cs & we & (~rs[1]) &  rs[0];
	assign wreg_b  = cs & we & (~rs[1]) & ~rs[0];

	always@(posedge clk) if(~cs) rindex <= rindex_latch;

	reg wr_data_a;
	reg wr_data_b;
	
	reg rx_wr_a_latch;
	reg rx_first_a=1;
	always@(posedge clk ) begin
	
		if (rx_wr_a) begin
			rx_wr_a_latch<=1;
		end
	
		wr_data_a<=0;
		wr_data_b<=0;
		if (reset) begin
		  rindex_latch <= 0;
			tx_data_a<=0;
			data_b <= 0;
			rx_wr_a_latch<=0;
			wr_data_a<=0;
			rx_first_a<=1;
		end else if (cen && cs) begin
			if (!rs[1]) begin
				rindex_latch <= 0;

				if (we && rindex == 0) begin
					rindex_latch[2:0] <= wdata[2:0];
				  
					rindex_latch[3] <= (wdata[5:3] == 3'b001);
					if (wdata[5:3] == 3'b100)
						rx_first_a<=1;
				end
			end else begin
				if (we) begin
					if (rs[0]) begin 
						tx_data_a <= wdata;
						wr_data_a<=1;
					end
					else
						begin
						data_b <= wdata;
						wr_data_b<=1;
						end
					end
				else begin
					if (rs[0]) begin 
						rx_wr_a_latch<=0;
						rx_first_a<=0;
					end
					else begin
					
					end
				end
			end
		end
	end

	assign reset   = ((wreg_a | wreg_b) & (rindex == 9) & (wdata[7:6] == 2'b11)) | reset_hw;
	assign reset_a = ((wreg_a | wreg_b) & (rindex == 9) & (wdata[7:6] == 2'b10)) | reset;	
	assign reset_b = ((wreg_a | wreg_b) & (rindex == 9) & (wdata[7:6] == 2'b01)) | reset;

	always@(posedge clk or posedge reset_hw) begin
		if (reset_hw)
		  wr1_a <= 0;
		else if(cen) begin
			if (reset_a)
			  wr1_a <= { 2'b00, wr1_a[5], 2'b00, wr1_a[2], 2'b00 };
			else if (wreg_a && rindex == 1)
			  wr1_a <= wdata;
		end
	end
	always@(posedge clk or posedge reset_hw) begin
		if (reset_hw)
		  wr1_b <= 0;
		else if(cen) begin
			if (reset_b)
			  wr1_b <= { 2'b00, wr1_b[5], 2'b00, wr1_b[2], 2'b00 };
			else if (wreg_b && rindex == 1)
			  wr1_b <= wdata;
		end
	end

	always@(posedge clk or posedge reset_hw) begin
		if (reset_hw)
		  wr2 <= 0;
		else if (cen && (wreg_a || wreg_b) && rindex == 2)
		  wr2 <= wdata;			
	end

	always@(posedge clk or posedge reset_hw) begin
		if (reset_hw)
		  wr3_a <= 0;
		else if (cen && wreg_a && rindex == 3)
		  wr3_a <= wdata;
	end
	always@(posedge clk or posedge reset_hw) begin
		if (reset_hw)
		  wr3_b <= 0;		
		else if (cen && wreg_b && rindex == 3)
		  wr3_b <= wdata;
	end
	always@(posedge clk or posedge reset_hw) begin
		if (reset_hw)
		  wr4_a <= 0;
		else if (cen && wreg_a && rindex == 4)
		  wr4_a <= wdata;
	end
	always@(posedge clk or posedge reset_hw) begin
		if (reset_hw)
		  wr4_b <= 0;		
		else if (cen && wreg_b && rindex == 4)
		  wr4_b <= wdata;
	end

	always@(posedge clk or posedge reset_hw) begin
		if (reset_hw)
		  wr5_a <= 0;
		else if(cen) begin
			if (reset_a)
			  wr5_a <= { 1'b0, wr5_a[6:5], 4'b0000, wr5_a[0] };			
			else if (wreg_a && rindex == 5)
			  wr5_a <= wdata;
		end
	end
	always@(posedge clk or posedge reset_hw) begin
		if (reset_hw)
		  wr5_b <= 0;
		else if(cen) begin
			if (reset_b)
			  wr5_b <= { 1'b0, wr5_b[6:5], 4'b0000, wr5_b[0] };			
			else if (wreg_b && rindex == 5)
			  wr5_b <= wdata;
		end
	end

	always@(posedge clk or posedge reset_hw) begin
		if (reset_hw) begin
			wr8_a <= 0;
			wr8_wr_a <= 1'b0;
		end
		else if (cen && (rs[1] & we ) && rindex == 8) begin
			wr8_wr_a <= 1'b1;
			wr8_a <= wdata;			
		end
		else begin
	          wr8_wr_a <= 1'b0;
		end
	end

	always@(posedge clk or posedge reset_hw) begin
		if (reset_hw) begin
		  wr8_b <= 0;
	          wr8_wr_b <= 1'b0;
		end
		else if (cen && (wreg_b ) && rindex == 8)
		begin
	          wr8_wr_b <= 1'b1;
		  wr8_b <= wdata;			
		end
		else
		begin
	          wr8_wr_b <= 1'b0;
		end
	end
	
	always@(posedge clk or posedge reset_hw) begin
		if (reset_hw)
		  wr9 <= 0;
		else if (cen && (wreg_a || wreg_b) && rindex == 9)
		  wr9 <= wdata[5:0];			
	end

	always@(posedge clk or posedge reset) begin
		if (reset)
		  wr10_a <= 0;
		else if(cen) begin
			if (reset_a)
			  wr10_a <= { 1'b0, wr10_a[6:5], 5'b00000 };
			else if (wreg_a && rindex == 10)
			  wr10_a <= wdata;
		end		
	end
	always@(posedge clk or posedge reset) begin
		if (reset)
		  wr10_b <= 0;
		else if(cen) begin
			if (reset_b)
			  wr10_b <= { 1'b0, wr10_b[6:5], 5'b00000 };
			else if (wreg_b && rindex == 10)
			  wr10_b <= wdata;
		end		
	end

	always@(posedge clk or posedge reset_hw) begin
		if (reset_hw)
		  wr12_a <= 0;
		else if (cen && wreg_a && rindex == 12)
		  wr12_a <= wdata;
	end
	always@(posedge clk or posedge reset_hw) begin
		if (reset_hw)
		  wr12_b <= 0;		
		else if (cen && wreg_b && rindex == 12)
		  wr12_b <= wdata;
	end

	always@(posedge clk or posedge reset_hw) begin
		if (reset_hw)
		  wr13_a <= 0;
		else if (cen && wreg_a && rindex == 13)
		  wr13_a <= wdata;
	end
	always@(posedge clk or posedge reset_hw) begin
		if (reset_hw)
		  wr13_b <= 0;		
		else if (cen && wreg_b && rindex == 13)
		  wr13_b <= wdata;
	end

	always@(posedge clk or posedge reset_hw) begin
		if (reset_hw)
		  wr14_a <= 0;
		else if(cen) begin
			if (reset)
			  wr14_a <= { wr14_a[7:6], 6'b110000 };
			else if (reset_a)
			  wr14_a <= { wr14_a[7:6], 4'b1000, wr14_a[1:0] };
			else if (wreg_a && rindex == 14)
			  wr14_a <= wdata;
		end		
	end
	always@(posedge clk or posedge reset_hw) begin
		if (reset_hw)
		  wr14_b <= 0;
		else if(cen) begin
			if (reset)
			  wr14_b <= { wr14_b[7:6], 6'b110000 };
			else if (reset_b)
			  wr14_b <= { wr14_b[7:6], 4'b1000, wr14_b[1:0] };
			else if (wreg_b && rindex == 14)
			  wr14_b <= wdata;
		end		
	end

	always@(posedge clk or posedge reset) begin
		if (reset) begin
		  wr15_a <= 8'b11111000;
		  wr15_b <= 8'b11111000;
		end else if (cen && rindex == 15) begin
		  if(wreg_a) wr15_a <= wdata;			
		  if(wreg_b) wr15_b <= wdata;			
		end
	end
	
	assign rdata = rs[1] && rs[0]       ? data_a :
		       rs[1]                ? data_b :
		       rindex ==  0 && rs[0] ? rr0_a :
		       rindex ==  0          ? rr0_b :
		       rindex ==  1 && rs[0] ? rr1_a :
		       rindex ==  1          ? rr1_b :
		       rindex ==  2 && rs[0] ? wr2 :
		       rindex ==  2          ? rr2_b :
		       rindex ==  3 && rs[0] ? rr3_a :
		       rindex ==  3          ? 8'h00 :
		       rindex ==  4 && rs[0] ? rr0_a :
		       rindex ==  4          ? rr0_b :
		       rindex ==  5 && rs[0] ? rr1_a :
		       rindex ==  5          ? rr1_b :
		       rindex ==  6 && rs[0] ? wr2 :
		       rindex ==  6          ? rr2_b :
		       rindex ==  7 && rs[0] ? rr3_a :
		       rindex ==  7          ? 8'h00 :

		       rindex ==  8 && rs[0] ? data_a :
		       rindex ==  8          ? data_b :
		       rindex ==  9 && rs[0] ? wr13_a :
		       rindex ==  9          ? wr13_b :
		       rindex == 10 && rs[0] ? rr10_a :
		       rindex == 10          ? rr10_b :
		       rindex == 11 && rs[0] ? rr15_a :
		       rindex == 11          ? rr15_b :
		       rindex == 12 && rs[0] ? wr12_a :
		       rindex == 12          ? wr12_b :
		       rindex == 13 && rs[0] ? wr13_a :
		       rindex == 13          ? wr13_b :
		       rindex == 14 && rs[0] ? rr10_a :
		       rindex == 14          ? rr10_b :
		       rindex == 15 && rs[0] ? rr15_a :
		       rindex == 15          ? rr15_b : 8'hff;

	assign rr0_a = { 1'b0,
			 1'b1,
			 wr15_a[5] ? cts_latch_a : cts_a,
			 1'b0,
			 wr15_a[3] ? dcd_latch_a : dcd_a,
			 ~tx_busy_a,
			 1'b0,
			 rx_wr_a_latch
			 };
	assign rr0_b = { 1'b0,
			 1'b1,
			 1'b0,
			 hunt_b,
			 wr15_b[3] ? dcd_latch_b : dcd_b,
			 1'b1,
			 1'b0,
			 1'b0
			 };

	assign rr1_a = { 1'b0,
			 1'b0,
			 1'b0,
			 1'b0,
			 1'b0,
			 1'b1,
			 1'b1,
			 ~tx_busy_a
			 };
	
	assign rr1_b = { 1'b0,
			 1'b0,
			 1'b0,
			 1'b0,
			 1'b0,
			 1'b1,
			 1'b1,
			 1'b1
			 };
	
	assign rr2_b = { wr2[7],
			 wr9[4] ? rr2_vec_stat[0] : wr2[6],
			 wr9[4] ? rr2_vec_stat[1] : wr2[5],
			 wr9[4] ? rr2_vec_stat[2] : wr2[4],
			 wr9[4] ? wr2[3] : rr2_vec_stat[2],
			 wr9[4] ? wr2[2] : rr2_vec_stat[1],
			 wr9[4] ? wr2[1] : rr2_vec_stat[0],
			 wr2[0]
			 };
	
	assign rr3_a = { 2'b0,
			 rx_irq_pend_a,
			 tx_irq_pend_a,
			 ex_irq_pend_a,
			 rx_irq_pend_b,
			 tx_irq_pend_b,
			 ex_irq_pend_b
			};

	assign rr10_a = { 1'b0,
			  1'b0,
			  1'b0,
			  1'b0,
			  1'b0,
			  1'b0,
			  1'b0,
			  1'b0
			  };
	assign rr10_b = { 1'b0,
			  1'b0,
			  1'b0,
			  1'b0,
			  1'b0,
			  1'b0,
			  1'b0,
			  1'b0
			  };
	
	assign rr15_a = { wr15_a[7],
			  wr15_a[6],
			  wr15_a[5],
			  wr15_a[4],
			  wr15_a[3],
			  1'b0,
			  wr15_a[1],
			  1'b0
			  };

	assign rr15_b = { wr15_b[7],
			  wr15_b[6],
			  wr15_b[5],
			  wr15_b[4],
			  wr15_b[3],
			  1'b0,
			  wr15_b[1],
			  1'b0
			  };
	
reg tx_fin_pre;
reg tx_ip;
reg tx_mip;

always @(posedge clk) begin
	if (reset) begin
      tx_ip<=0;
      tx_mip<=0;
	end
	else begin
      tx_fin_pre<=tx_busy_a;
		 
		if (wr5_a[3] &  wr1_a[1] & tx_busy_a & ~tx_fin_pre) begin
			tx_ip<=~tx_mip;
			tx_mip<=0;
		end
		if (wreg_a & (rindex == 0) & (wdata[5:3] == 3'b111)) begin
			tx_ip<=0;
		end
		if (wreg_a & (rindex == 0) & (wdata[5:3] == 3'b101)) begin
          tx_mip<= ~tx_ip;
          tx_ip<=0;
		end
		if (wr5_a[3]==0)begin
			tx_mip<=0;
			tx_ip<=0;
		end
	end	
end

	 reg tx_busy_a_r;
	 reg tx_latch_a;
	 always @(posedge clk) begin
		tx_busy_a_r <= tx_busy_a;
		if (reset | reset_hw | reset_a)
			tx_latch_a<=0;
		else if  (tx_busy_a_r ==1 && tx_busy_a==0)
			tx_latch_a<=1;
		else if (wr_data_a)
			tx_latch_a<=0;
		else if (wreg_a & (rindex == 0) & (wdata[5:3] == 3'b010))
			tx_latch_a<=0;
	 end

	 wire wreq_n;

	assign rx_irq_pend_a =   wr3_a[0] & rx_wr_a_latch & (wr1_a[3] ^ wr1_a[4]) & ((wr1_a[3] & rx_first_a )|(wr1_a[4]));

	assign tx_irq_pend_a = tx_ip;

   wire cts_interrupt = wr1_a[0] &&  wr15_a[5] || (tx_busy_a_r ==1 && tx_busy_a==0) || (tx_busy_a_r ==0 && tx_busy_a==1);

	always @(posedge clk) begin
		if (reset_b) begin
			tx_ip_b <= 1'b0;
			hunt_b  <= 1'b0;
		end else begin
			if (wr_data_b && wr5_b[3] && wr1_b[1] && wr9[3]) tx_ip_b <= 1'b1;
			if (wreg_b && rindex == 0 && wdata[5:3] == 3'b101) tx_ip_b <= 1'b0;
			if (wreg_b && rindex == 5) tx_ip_b <= 1'b0;
			if (wreg_b && rindex == 3 && wdata[4]) hunt_b <= 1'b1;
			if (do_extreset_b) hunt_b <= 1'b0;
		end
	end

	assign ex_irq_pend_a = ex_irq_ip_a ; 
	assign rx_irq_pend_b = 0;
	assign tx_irq_pend_b = tx_ip_b & wr1_b[1];
	assign ex_irq_pend_b = ex_irq_ip_b;

	assign _irq = ~(wr9[3] & (rx_irq_pend_a |
				  
				  rx_irq_pend_b |
				  tx_irq_pend_a |
				  tx_irq_pend_b |
				  ex_irq_pend_a |
				  ex_irq_pend_b));

	assign rr2_vec_stat = rx_irq_pend_a ? 3'b110 :
			      tx_irq_pend_a ? 3'b100 :
			      ex_irq_pend_a ? 3'b101 :
			      rx_irq_pend_b ? 3'b010 :
			      tx_irq_pend_b ? 3'b000 :
			      ex_irq_pend_b ? 3'b001 : 3'b011;
	
	assign do_extreset_a = wreg_a & (rindex == 0) & (wdata[5:3] == 3'b010);
	assign do_extreset_b = wreg_b & (rindex == 0) & (wdata[5:3] == 3'b010);

	assign dcd_ip_a = (dcd_a != dcd_latch_a) & wr15_a[3];
	assign cts_ip_a = (cts_a != cts_latch_a) & wr15_a[5];
	assign dcd_ip_b = (dcd_b != dcd_latch_b) & wr15_b[3];

	assign do_latch_a = latch_open_a & (dcd_ip_a | cts_ip_a );
	assign do_latch_b = latch_open_b & (dcd_ip_b );

	reg [31:0] pclk_acc_a;
	reg [16:0] brg_cnt_a;
	reg        zc_pend_a;
	wire [32:0] pclk_sum_a = {1'b0, pclk_acc_a} + 33'd1035232487;
	always@(posedge clk or posedge reset) begin
		if (reset) begin
			pclk_acc_a <= 0;
			brg_cnt_a  <= 0;
			zc_pend_a  <= 0;
		end else begin
			pclk_acc_a <= pclk_sum_a[31:0];
			if (!(wr14_a[0] && wr14_a[1]))
				brg_cnt_a <= {1'b0, wr13_a, wr12_a};
			else if (pclk_sum_a[32]) begin
				if (brg_cnt_a == 0) begin
					brg_cnt_a <= {1'b0, wr13_a, wr12_a} + 17'd1;
					if (wr15_a[1]) zc_pend_a <= 1'b1;
				end else
					brg_cnt_a <= brg_cnt_a - 17'd1;
			end
			if (cep && zc_pend_a) zc_pend_a <= 1'b0;
		end
	end

	always@(posedge clk or posedge reset) begin
		if (reset)
		  ex_irq_ip_a <= 0;
		else if(cep) begin
			if (do_extreset_a)
			  ex_irq_ip_a <= 0;
			else if ((do_latch_a || zc_pend_a) && wr1_a[0])
			  ex_irq_ip_a <= 1;
		end
	end
	always@(posedge clk or posedge reset) begin
		if (reset)
		  ex_irq_ip_b <= 0;
		else if(cep) begin
			if (do_extreset_b)
			  ex_irq_ip_b <= 0;
			else if (do_latch_b && wr1_b[0])
			  ex_irq_ip_b <= 1;
		end
	end

	always@(posedge clk or posedge reset) begin
		if (reset)
		  latch_open_a <= 1;
		else if(cep) begin
			if (do_extreset_a)
			  latch_open_a <= 1;
			else if (do_latch_a)
			  latch_open_a <= 0;
		end
	end
	always@(posedge clk or posedge reset) begin
		if (reset)
		  latch_open_b <= 1;
		else if(cep) begin
			if (do_extreset_b)
			  latch_open_b <= 1;
			else if (do_latch_b)
			  latch_open_b <= 0;
		end
	end

	always@(posedge clk or posedge reset) begin
		if (reset) begin
			dcd_latch_a <= 0;
			cts_latch_a <= 0;
		end else if(cep) begin
			if (do_latch_a)
			  dcd_latch_a <= dcd_a;
			  cts_latch_a <= cts_a;
		end
	end
	always@(posedge clk or posedge reset) begin
		if (reset) begin
			dcd_latch_b <= 0;			
		end else if(cep) begin
			if (do_latch_b)
			  dcd_latch_b <= dcd_b;
		end
	end
	
wire parity_ena_a= wr4_a[0];
wire parity_even_a= wr4_a[1];
reg [1:0] stop_bits_a= 2'b00;
reg [1:0] bit_per_char_a = 2'b00;

reg [23:0] baud_divid_speed_a = 24'd282;
wire tx_busy_a;
wire rx_wr_a;
wire [30:0] uart_setup_rx_a = { 1'b0, bit_per_char_a, 1'b0, parity_ena_a, 1'b0, parity_even_a, baud_divid_speed_a  } ;
wire [30:0] uart_setup_tx_a = { 1'b0, bit_per_char_a, 1'b0, parity_ena_a, 1'b0, parity_even_a, baud_divid_speed_a  } ;
rxuart rxuart_a (
	.i_clk(clk), 
	.i_reset(reset_a|reset_hw), 
	.i_setup(uart_setup_rx_a), 
	.i_uart_rx(wr14_a[4] ? txd : rxd),
	.o_wr(rx_wr_a),
	.o_data(data_a),
	.o_break(break_a),
	.o_parity_err(parity_err_a), 
	.o_frame_err(frame_err_a), 
	.o_ck_uart()
	);
txuart txuart_a
	(
	.i_clk(clk), 
	.i_reset(reset_a|reset_hw), 
	.i_setup(uart_setup_tx_a), 
	.i_break(1'b0), 
	.i_wr(wr_data_a),
	.i_data(tx_data_a),
	.i_cts_n(1'b0), 
	.o_uart_tx(txd), 
	.o_busy(tx_busy_a));

	wire cts_a = ~tx_busy_a;
	
	assign rts = rx_wr_a_latch;
	assign wreq=1;
endmodule
