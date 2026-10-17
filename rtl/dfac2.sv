module dfac2 #(
	parameter [6:0] ADDR = 7'h6F
) (
	input  wire        clk,
	input  wire        reset,

	input  wire        scl,
	input  wire        sda,
	output reg         sda_o,

	output reg  [7:0]  reg_addr,
	output reg  [7:0]  reg_data,
	output reg         reg_wr
);

localparam [1:0] S_IDLE = 2'd0,
                 S_RX   = 2'd1,
                 S_ACK  = 2'd2;

reg  [1:0] state;
reg  [3:0] bitcnt;
reg  [7:0] shreg;
reg        first;
reg        sub;
reg        scl_d, sda_d;

wire start    = scl && scl_d && sda_d && !sda;
wire stop     = scl && scl_d && !sda_d && sda;
wire scl_rise = scl && !scl_d;
wire scl_fall = !scl && scl_d;

always @(posedge clk) begin
	scl_d  <= scl;
	sda_d  <= sda;
	reg_wr <= 1'b0;

	if (start) begin
		state  <= S_RX;
		bitcnt <= 4'd0;
		first  <= 1'b1;
		sda_o  <= 1'b1;
	end
	else if (stop) begin
		state <= S_IDLE;
		sda_o <= 1'b1;
	end
	else case (state)
		S_RX: begin
			if (scl_rise) begin
				shreg  <= {shreg[6:0], sda};
				bitcnt <= bitcnt + 4'd1;
			end
			else if (scl_fall && bitcnt == 4'd8) begin
				if (first) begin
					if (shreg[7:1] == ADDR) begin
						sda_o <= 1'b0;
						state <= S_ACK;
						sub   <= !shreg[0];
					end
					else
						state <= S_IDLE;
					first <= shreg[0];
				end
				else begin
					sda_o <= 1'b0;
					state <= S_ACK;
					if (sub) begin
						reg_addr <= shreg;
						sub      <= 1'b0;
					end
					else begin
						reg_data <= shreg;
						reg_wr   <= 1'b1;
					end
				end
			end
		end

		S_ACK: begin
			if (scl_fall) begin
				sda_o  <= 1'b1;
				bitcnt <= 4'd0;
				state  <= first ? S_IDLE : S_RX;
			end
		end

		default: ;
	endcase

	if (reg_wr)
		reg_addr <= reg_addr + 8'd1;

	if (reset) begin
		state <= S_IDLE;
		sda_o <= 1'b1;
		sub   <= 1'b0;
		first <= 1'b0;
	end
end

endmodule
