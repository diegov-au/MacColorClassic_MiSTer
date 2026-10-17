module floppy_write_committer
(
	input         clk,
	input         rst,

	input             sector_valid,
	input      [21:0] sector_addr,
	output reg [8:0]  buf_addr,
	input      [7:0]  buf_data,

	output reg [21:0] wr_addr,
	output reg [15:0] wr_data,
	output reg        wr_req,
	input             wr_ack,

	output            busy,
	output reg        done,
	output     [21:0] committed_addr,

	output      [7:0] sd_buf_addr,
	output     [15:0] sd_buf_data,
	output             sd_buf_wr
);

	assign committed_addr = base_addr;
	assign sd_buf_addr    = word_idx;
	assign sd_buf_data    = wr_data;
	assign sd_buf_wr      = wr_req;

localparam IDLE       = 3'd0,
           FETCH_LO   = 3'd1,
           FETCH_HI   = 3'd2,
           ASSERT     = 3'd3,
           WAIT       = 3'd4,
           DONE_PULSE = 3'd5;
reg [2:0] state;

assign busy = (state != IDLE);

reg [21:0] base_addr;
reg [7:0]  word_idx;
reg [7:0]  byte_lo;

always @(*) begin
	case (state)
		FETCH_HI: buf_addr = {word_idx, 1'b1};
		default:  buf_addr = {word_idx, 1'b0};
	endcase
end

always @(posedge clk) begin
	done <= 1'b0;

	if (rst) begin
		state  <= IDLE;
		wr_req <= 1'b0;
	end else begin
		case (state)
		IDLE: if (sector_valid) begin
			base_addr <= sector_addr;
			word_idx  <= 8'd0;
			state     <= FETCH_LO;
		end

		FETCH_LO: state <= FETCH_HI;

		FETCH_HI: begin
			byte_lo <= buf_data;
			state   <= ASSERT;
		end

		ASSERT: begin
			wr_addr <= base_addr + {word_idx, 1'b0};
			wr_data <= {byte_lo, buf_data};
			wr_req  <= 1'b1;
			state   <= WAIT;
		end

		WAIT: if (wr_ack) begin
			wr_req <= 1'b0;
			if (word_idx == 8'd255) begin
				state <= DONE_PULSE;
			end else begin
				word_idx <= word_idx + 8'd1;
				state    <= FETCH_LO;
			end
		end

		DONE_PULSE: begin
			done  <= 1'b1;
			state <= IDLE;
		end

		default: state <= IDLE;
		endcase
	end
end

endmodule
