module floppy_loader
(
	input         clk_sys,
	input         reset,

	input         img_mounted,
	input  [63:0] img_size,
	input         img_readonly,

	output reg [31:0] sd_lba,
	output reg        sd_rd,
	input              sd_ack,

	input        [7:0] sd_buff_addr,
	input       [15:0] sd_buff_dout,
	input               sd_buff_wr,

	output reg  [21:0] wr_addr,
	output reg  [15:0] wr_data,
	output reg          wr_req,
	input                wr_ack,

	output reg          done,
	output reg  [63:0]  loaded_size,
	output reg           readonly_latched,
	output              busy
);

localparam IDLE         = 3'd0,
           SD_ASSERT    = 3'd1,
           SD_WAIT_ACK  = 3'd2,
           SD_WAIT_DONE = 3'd3,
           DRAIN_FETCH  = 3'd4,
           DRAIN_ASSERT = 3'd5,
           DRAIN_WAIT   = 3'd6,
           DONE_PULSE   = 3'd7;
reg [2:0] state;

assign busy = (state != IDLE);

reg [15:0] buf_mem [0:255];
reg [15:0] buf_rd;
always @(posedge clk_sys) buf_rd <= buf_mem[word_idx];

reg  [7:0] word_idx;
reg [11:0] sector;
reg [11:0] nsect;

reg mount_pending;
reg img_mounted_d;
always @(posedge clk_sys) begin
	img_mounted_d <= img_mounted;
	if (reset) mount_pending <= 1'b0;
	else if (img_mounted && !img_mounted_d && img_size != 0) mount_pending <= 1'b1;
	else if (state == IDLE && mount_pending) mount_pending <= 1'b0;
end

always @(posedge clk_sys) begin
	done <= 1'b0;

	if (reset) begin
		state   <= IDLE;
		sd_rd   <= 1'b0;
		wr_req  <= 1'b0;
	end else begin
		case (state)
		IDLE: if (mount_pending) begin
			loaded_size      <= img_size;
			readonly_latched <= img_readonly;
			nsect            <= img_size[20:9];
			sector           <= 12'd0;
			state            <= SD_ASSERT;
		end

		SD_ASSERT: begin
			sd_lba <= {20'd0, sector};
			sd_rd  <= 1'b1;
			state  <= SD_WAIT_ACK;
		end

		SD_WAIT_ACK: if (sd_ack) state <= SD_WAIT_DONE;

		SD_WAIT_DONE: begin
			if (sd_buff_wr && sd_ack) buf_mem[sd_buff_addr] <= {sd_buff_dout[7:0], sd_buff_dout[15:8]};
			if (!sd_ack) begin
				sd_rd    <= 1'b0;
				word_idx <= 8'd0;
				state    <= DRAIN_FETCH;
			end
		end

		DRAIN_FETCH: state <= DRAIN_ASSERT;

		DRAIN_ASSERT: begin
			wr_addr <= {sector, 9'd0} + {word_idx, 1'b0};
			wr_data <= buf_rd;
			wr_req  <= 1'b1;
			state   <= DRAIN_WAIT;
		end

		DRAIN_WAIT: if (wr_ack) begin
			wr_req <= 1'b0;
			if (word_idx == 8'd255) begin
				if (sector == nsect - 12'd1) state <= DONE_PULSE;
				else begin
					sector <= sector + 12'd1;
					state  <= SD_ASSERT;
				end
			end else begin
				word_idx <= word_idx + 8'd1;
				state    <= DRAIN_FETCH;
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
