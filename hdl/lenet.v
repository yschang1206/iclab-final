/** 
 * lenet.v
 */

module lenet
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
  input rdy_data,
  input [DATA_WIDTH - 1:0] data_in,
  output reg [DATA_WIDTH - 1:0] data_out,
  output reg [ADDR_WIDTH - 1:0] addr_in,
  output reg [ADDR_WIDTH - 1:0] addr_out,
  output reg dram_en_wr,
  output reg dram_en_rd,
  output done,
  output done_conv,
  output done_relu,
  output done_pool
);

localparam  ST_IDLE = 3'd0,
            ST_CONV = 3'd1,
            ST_RELU = 3'd2,
            ST_POOL = 3'd3,
            ST_DONE = 3'd7;

reg rdy_data_ff;

/* conv wires */
wire en_conv;
wire dram_valid_conv;
wire [DATA_WIDTH - 1:0] data_out_conv;
wire [ADDR_WIDTH - 1:0] addr_in_conv, addr_out_conv;
wire dram_en_wr_conv, dram_en_rd_conv;

conv conv(
  .clk(clk),
  .srstn(srstn),
  .enable(en_conv),
  .dram_valid(dram_valid),
  .data_in(data_in),
  .data_out(data_out_conv),
  .addr_in(addr_in_conv),
  .addr_out(addr_out_conv),
  .dram_en_wr(dram_en_wr_conv),
  .dram_en_rd(dram_en_rd_conv),
  .done(done_conv)
);

/* relu wires */
wire en_relu;
wire dram_valid_relu;
wire [DATA_WIDTH - 1:0] data_out_relu;
wire [ADDR_WIDTH - 1:0] addr_in_relu, addr_out_relu;
wire dram_en_wr_relu, dram_en_rd_relu;

relu relu(
  .clk(clk),
  .srstn(srstn),
  .enable(en_relu),
  .dram_valid(dram_valid),
  .data_in(data_in),
  .data_out(data_out_relu),
  .addr_in(addr_in_relu),
  .addr_out(addr_out_relu),
  .dram_en_wr(dram_en_wr_relu),
  .dram_en_rd(dram_en_rd_relu),
  .done(done_relu)
);

/* pooling wires */
wire en_pool;
wire dram_valid_pool;
wire [DATA_WIDTH - 1:0] data_out_pool;
wire [ADDR_WIDTH - 1:0] addr_in_pool, addr_out_pool;
wire dram_en_wr_pool, dram_en_rd_pool;

max_pool max_pool(
  .clk(clk),
  .srstn(srstn),
  .enable(en_pool),
  .dram_valid(dram_valid),
  .data_in(data_in),
  .data_out(data_out_pool),
  .addr_in(addr_in_pool),
  .addr_out(addr_out_pool),
  .dram_en_wr(dram_en_wr_pool),
  .dram_en_rd(dram_en_rd_pool),
  .done(done_pool)
);

/* global regs */
reg [2:0] state, state_nx;

/* finite state machine */
always@(posedge clk) begin
  /* state reigster */
  if (~srstn)
    state <= ST_IDLE;
  else
    state <= state_nx;
end

always@(*) begin
  /* next state logic */
  case (state)
    ST_IDLE: state_nx = (enable) ? ST_CONV : ST_IDLE;
    ST_CONV: state_nx = (done_conv) ? ST_RELU : ST_CONV;
    ST_RELU: state_nx = (done_relu) ? ST_POOL : ST_RELU;
    ST_POOL: state_nx = (done_pool) ? ST_DONE : ST_POOL;
    ST_DONE: state_nx = ST_IDLE;
    default: state_nx = ST_IDLE;
  endcase
end

always@(posedge clk) begin
  if (~srstn)
    rdy_data_ff <= 0;
  else
    rdy_data_ff <= rdy_data;
end

/* output logic: submodule enable signals */
assign en_conv = (state == ST_CONV & rdy_data_ff);
assign en_relu = (state == ST_RELU & rdy_data_ff);
assign en_pool = (state == ST_POOL & rdy_data_ff);

/* output logic: done signal */
assign done = (state == ST_DONE);

always@(*) begin
  /* output logic: forward signals */
  case (state)
    ST_CONV: begin
      data_out = data_out_conv;
      addr_in = addr_in_conv;
      addr_out = addr_out_conv;
      dram_en_wr = dram_en_wr_conv;
      dram_en_rd = dram_en_rd_conv;
    end
    ST_RELU: begin
      data_out = data_out_relu;
      addr_in = addr_in_relu;
      addr_out = addr_out_relu;
      dram_en_wr = dram_en_wr_relu;
      dram_en_rd = dram_en_rd_relu;
    end
    ST_POOL: begin
      data_out = data_out_pool;
      addr_in = addr_in_pool;
      addr_out = addr_out_pool;
      dram_en_wr = dram_en_wr_pool;
      dram_en_rd = dram_en_rd_pool;
    end
    default: begin
      data_out = 0;
      addr_in = 0;
      addr_out = 0;
      dram_en_wr = 0;
      dram_en_rd = 0;
    end
  endcase
end

endmodule
