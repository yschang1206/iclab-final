/**
 * relu.v
 */

module relu
#
(
  parameter DATA_WIDTH = 32, 
  parameter ADDR_WIDTH = 18,
  parameter KNL_MAXNUM = 16
)
(
  input clk,
  input srstn,
  input enable,
  input dram_valid,
  input [DATA_WIDTH - 1:0] data_in,
  output [DATA_WIDTH - 1:0] data_out,
  output reg [ADDR_WIDTH - 1:0] addr_in,
  output reg [ADDR_WIDTH - 1:0] addr_out,
  output reg dram_en_wr,
  output reg dram_en_rd,
  output wire done
);

localparam  IDX_IDLE     = 0,
            IDX_LD_PARAM = 1,
            IDX_LD_BIAS  = 2,
            IDX_EVAL     = 3,
            IDX_DONE     = 4;

localparam  ST_IDLE     = 5'b00001,
            ST_LD_PARAM = 5'b00010,
            ST_LD_BIAS  = 5'b00100,
            ST_EVAL     = 5'b01000,
            ST_DONE     = 5'b10000;

localparam  PARAM_BASE = 18'd0,
            BIAS_BASE = 18'd61504,  // 64 + 16x120x32, 0xf040
            FMAP_BASE = 18'd131072;

localparam  NUM_PARAM = 2'd3;

localparam  IDX_DEPTH  = 0,
            IDX_HEIGHT = 1,
            IDX_WIDTH  = 2;

/* global regs, wires and integers */
reg [4:0] state, state_nx;
wire bs_last;
wire width_last;
wire height_last;
wire depth_last;
integer i;

/* regs and wires for loading parameter */
reg [1:0] cnt_param, cnt_param_nx;
wire param_last;
reg param_last_ff;

/* regs for loading bias */
reg [DATA_WIDTH - 1:0] biases[0:KNL_MAXNUM - 1];
reg [3:0] cnt_bs, cnt_bs_nx;

/* wires / regs for evaluation */
wire [DATA_WIDTH - 1:0] pixel;
wire done_eval_nx;
reg [5:0] cnt_width, cnt_width_nx;
reg [5:0] cnt_height, cnt_height_nx;
reg [5:0] cnt_depth, cnt_depth_nx, cnt_depth_ff;
reg valid_bias;
reg en_eval;
reg done_eval;

// TODO: read parameters from dram
//localparam fmap_width = 6'd10;
//localparam fmap_height = 6'd10;
//localparam fmap_depth = 5'd16;
reg [5:0] fmap_data [0:2];
wire [5:0] fmap_width;
wire [5:0] fmap_height;
wire [5:0] fmap_depth;

/* event flags */
assign param_last = (cnt_param == NUM_PARAM - 1);
assign bs_last = (cnt_bs == KNL_MAXNUM - 1); // assign bs_last = (cnt_bs == fmap_depth - 1);
assign width_last = (cnt_width == fmap_width-1);
assign height_last = (cnt_height == fmap_height-1);
assign depth_last = (cnt_depth == fmap_depth-1);

/* finite state machine */
always @(posedge clk) begin
  if (~srstn) state <= ST_IDLE;
  else        state <= state_nx;
end

always@(*) begin
  case (state)
    ST_IDLE:     state_nx = (enable) ? ST_LD_PARAM : ST_IDLE;
    ST_LD_PARAM: state_nx = (param_last_ff) ? ST_LD_BIAS : ST_LD_PARAM;
    ST_LD_BIAS:  state_nx = (bs_last) ? ST_EVAL : ST_LD_BIAS;
    ST_EVAL:     state_nx = (done_eval) ? ST_DONE : ST_EVAL;
    ST_DONE:     state_nx = ST_IDLE;
    default:     state_nx = ST_IDLE;
  endcase
end

always@(*) begin
  /* output logic: input memory address translator */
  case (state)
    ST_LD_PARAM: addr_in = PARAM_BASE + {16'd0, cnt_param};
    ST_LD_BIAS:  addr_in = BIAS_BASE + {14'd0, cnt_bs};
    ST_EVAL:     addr_in = FMAP_BASE + {4'd0, cnt_depth[3:0], cnt_height[4:0], cnt_width[4:0]};
    default:     addr_in = 0;
  endcase
end

always @(*) begin // output logic: dram enable signal
  if (state[IDX_EVAL] & en_eval) dram_en_wr = 1'b1;
  else dram_en_wr = 1'b0;
end

always @(*) begin // output logic: dram enable signal
  if (state[IDX_IDLE] | state[IDX_DONE]) dram_en_rd = 1'b0;
  else dram_en_rd = 1'b1;
end

assign done = state[IDX_DONE];

always @(posedge clk) begin
  if (~srstn) addr_out <= 0;
  else        addr_out <= addr_in;
end

always @(posedge clk) begin
  if (~srstn) en_eval <= 0;
  else        en_eval <= state[IDX_EVAL];
end

always @(posedge clk) begin
  if (~srstn) valid_bias <= 0;
  else        valid_bias <= state[IDX_LD_BIAS];
end

assign done_eval_nx = width_last & height_last & depth_last;
always @(posedge clk) begin
  if (~srstn) done_eval <= 0;
  else        done_eval <= done_eval_nx;
end

/* delayed registers */
always @(posedge clk) begin
  if (~srstn) param_last_ff <= 0;
  else        param_last_ff <= param_last;
end

/* evalution: bias -> relu */
assign pixel = data_in + biases[cnt_depth_ff];
assign data_out = pixel[DATA_WIDTH - 1] ? 0 : pixel;  // discard negative value

/* register file to store biases */
always @(posedge clk) begin
  if (~srstn) begin
    for(i = 0; i < KNL_MAXNUM; i = i + 1)
      biases[i] <= 0;
  end
  else if (valid_bias) begin
    biases[KNL_MAXNUM - 1] <= data_in;
    for(i = 0; i < KNL_MAXNUM - 1; i = i + 1)
      biases[i] <= biases[i + 1];
  end
end

/* register file to store parameters */
assign fmap_depth  = fmap_data[IDX_DEPTH];
assign fmap_height = fmap_data[IDX_HEIGHT];
assign fmap_width  = fmap_data[IDX_WIDTH];

always @(posedge clk) begin
  if (~srstn) begin
    fmap_data[IDX_DEPTH]  <= 0;
    fmap_data[IDX_HEIGHT] <= 0;
    fmap_data[IDX_WIDTH]  <= 0;
  end
  else if (state[IDX_LD_PARAM]) begin
    fmap_data[IDX_DEPTH]  <= data_in[5:0];
    fmap_data[IDX_HEIGHT] <= fmap_data[IDX_DEPTH];
    fmap_data[IDX_WIDTH]  <= fmap_data[IDX_HEIGHT];
  end
end

/* counter to record how many parameters have been read */
always @(posedge clk) begin
  if (~srstn) cnt_param <= 0;
  else        cnt_param <= cnt_param_nx;
end
always @(*) begin
  if (state[IDX_LD_PARAM]) cnt_param_nx = cnt_param + 1;
  else cnt_param_nx = 0;
end

/* counter to record id of the currently loading bias */
always @(posedge clk) begin
  if (~srstn) cnt_bs <= 0;
  else        cnt_bs <= cnt_bs_nx;
end
always @(*) begin
  if (state[IDX_LD_BIAS]) cnt_bs_nx = cnt_bs + 1;
  else cnt_bs_nx = 0;
end

always @(posedge clk) begin // delayed register
  if (~srstn) cnt_depth_ff <= 0;
  else        cnt_depth_ff <= cnt_depth;
end

/* counter to record x-axis of the currently processing pixel */
always @(posedge clk) begin
  if (~srstn) cnt_width <= 0;
  else        cnt_width <= cnt_width_nx;
end
always @(*) begin
  case ({state[IDX_EVAL], width_last}) // synopsys parallel_case
    2'b10   : cnt_width_nx = cnt_width + 1;
    default : cnt_width_nx = 0;
  endcase
end

/* counter to record y-axis of the currently processing pixel */
always @(posedge clk) begin
  if (~srstn) cnt_height <= 0;
  else        cnt_height <= cnt_height_nx;
end
always @(*) begin
  case ({state[IDX_EVAL], width_last, height_last}) // synopsys parallel_case
    3'b100   : cnt_height_nx = cnt_height;
    3'b101   : cnt_height_nx = cnt_height;
    3'b110   : cnt_height_nx = cnt_height + 1;
    default : cnt_height_nx = 0;
  endcase
end

/* counter to record z-axis of the currently processing pixel */
always @(posedge clk) begin
  if (~srstn) cnt_depth <= 0;
  else cnt_depth <= cnt_depth_nx;
end
always @(*) begin
  case ({state[IDX_EVAL], width_last, height_last}) // synopsys parallel_case
    3'b100   : cnt_depth_nx = cnt_depth;
    3'b101   : cnt_depth_nx = cnt_depth;
    3'b110   : cnt_depth_nx = cnt_depth;
    3'b111   : cnt_depth_nx = cnt_depth + 1;
    default : cnt_depth_nx = 0;
  endcase
end

endmodule
