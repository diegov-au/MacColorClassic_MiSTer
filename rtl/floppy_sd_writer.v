module floppy_sd_writer #(
	parameter ACK_TIMEOUT_BITS = 24
) (
	input         clk,
	input         reset,

	input         img_mounted,

	input             commit_done,
	input      [21:0] commit_addr,
	input             commit_buf_wr,
	input      [7:0]  commit_buf_addr,
	input      [15:0] commit_buf_data,

	input             readonly,
	input             loader_busy,

	input      [12:0] size_blocks,

	output reg [31:0] sd_lba,
	output reg        sd_wr,
	input             sd_ack,

	input      [7:0]  sd_buff_addr,
	output     [15:0] sd_buff_din,

	output            busy
);

	reg [15:0] mem0 [0:255];
	reg [15:0] mem1 [0:255];

	reg        tail;
	reg        head;
	reg  [1:0] valid;
	reg [21:0] addr_q [0:1];

	always @(posedge clk) begin
		if (commit_buf_wr) begin
			if (tail == 1'b0) mem0[commit_buf_addr] <= commit_buf_data;
			else              mem1[commit_buf_addr] <= commit_buf_data;
		end
	end

	reg [15:0] mem0_do, mem1_do;
	always @(posedge clk) mem0_do <= mem0[sd_buff_addr];
	always @(posedge clk) mem1_do <= mem1[sd_buff_addr];
	wire [15:0] mem_do = (head == 1'b0) ? mem0_do : mem1_do;
	assign sd_buff_din = {mem_do[7:0], mem_do[15:8]};

	localparam P_IDLE      = 2'd0,
	           P_WAIT_ACK  = 2'd1,
	           P_WAIT_DONE = 2'd2;
	reg [1:0] pstate;

	reg [ACK_TIMEOUT_BITS-1:0] ackTimer;
	wire ackTimeout = &ackTimer;

	wire [12:0] lba_head     = addr_q[head][21:9];
	wire        lba_in_range = (size_blocks != 13'd0) && (lba_head < size_blocks);

	assign busy = (pstate != P_IDLE) || valid[0] || valid[1];

	always @(posedge clk) begin
		if (reset) begin
			pstate <= P_IDLE;
			sd_lba <= 32'd0;
			sd_wr  <= 1'b0;
			valid  <= 2'b00;
			head   <= 1'b0;
			tail   <= 1'b0;
			ackTimer <= 0;
		end else begin
			if (commit_done && !readonly) begin
				valid[tail]  <= 1'b1;
				addr_q[tail] <= commit_addr;
				tail         <= ~tail;
			end

			if (img_mounted) begin
				valid <= 2'b00;
				tail  <= head;
			end

			case (pstate)
			P_IDLE: if (valid[head] && !loader_busy) begin
				if (lba_in_range) begin
					sd_lba <= {19'd0, lba_head};
					sd_wr  <= 1'b1;
					pstate <= P_WAIT_ACK;
				end else begin
					valid[head] <= 1'b0;
					head        <= ~head;
				end
			end

			P_WAIT_ACK: if (sd_ack) begin
				sd_wr  <= 1'b0;
				pstate <= P_WAIT_DONE;
			end else if (ackTimeout) begin
				sd_wr  <= 1'b0;
				pstate <= P_IDLE;
			end else
				ackTimer <= ackTimer + 1'b1;

			P_WAIT_DONE: if (!sd_ack) begin
				valid[head] <= 1'b0;
				head        <= ~head;
				pstate      <= P_IDLE;
			end

			default: pstate <= P_IDLE;
			endcase

			if (pstate != P_WAIT_ACK) ackTimer <= 0;
		end
	end

endmodule
