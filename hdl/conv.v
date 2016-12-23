/**
 * conv.v
 */

module conv
#
(
  parameter DATA_WIDTH = 32,
  parameter ADDR_WIDTH = 18,
  parameter KNL_WIDTH = 5,
  parameter KNL_HEIGHT = 5,
  parameter KNL_SIZE = KNL_WIDTH * KNL_HEIGHT,  // unit: 32 bits
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

/* local parameters */
localparam  ST_IDLE = 3'd0, 
            ST_LD_KNLS = 3'd1, 
            ST_LD_IFMAP_FULL = 3'd2, 
            ST_LD_IFMAP_PART = 3'd3, 
            ST_CONV = 3'd4,
            ST_DONE = 3'd7;

/* global wires, registers and integers */
integer i, j;
reg [2:0] state, state_nx, state_ff;
wire knl_wts_last, knl_id_last;
wire ifmap_delta_x_last, ifmap_delta_y_last;
wire ifmap_base_x_last, ifmap_base_y_last;
wire ifmap_chnl_last;
wire ofmap_chnl_last;
wire ofmap_chnl_ff_last;

reg ifmap_chnl_last_ff;
reg ifmap_base_x_last_ff, ifmap_base_y_last_ff;
// delay one cycle to read and write psum of output feature map
reg [ADDR_WIDTH - 1:0] addr_in_ff;

/* wires and registers for kernels */
reg [DATA_WIDTH - 1:0] knls[0:KNL_MAXNUM * KNL_SIZE - 1];
reg [4:0] cnt_knl_id, cnt_knl_id_nx;      // kernel id
reg [4:0] cnt_knl_chnl, cnt_knl_chnl_nx;  // kernel channel
reg [4:0] cnt_knl_wts, cnt_knl_wts_nx;    // kernel weights

/* wires and registers for input feature map */
reg [DATA_WIDTH - 1:0] ifmap[0:KNL_SIZE - 1];
wire [4:0] cnt_ifmap_chnl;  // equals to cnt_knl_chnl
reg [5:0] cnt_ifmap_base_x, cnt_ifmap_base_x_nx;
reg [5:0] cnt_ifmap_base_y, cnt_ifmap_base_y_nx;
reg [2:0] cnt_ifmap_delta_x, cnt_ifmap_delta_x_nx;
reg [2:0] cnt_ifmap_delta_y, cnt_ifmap_delta_y_nx, cnt_ifmap_delta_y_ff;

/* wires and registers for output feature map */
reg [DATA_WIDTH - 1:0] mac;
reg [4:0] cnt_ofmap_chnl, cnt_ofmap_chnl_nx;  // output channel
reg [4:0] cnt_ofmap_chnl_ff;
reg [DATA_WIDTH - 1:0] products[0:KNL_SIZE - 1];
reg [DATA_WIDTH - 1:0] products_roff[0:KNL_SIZE - 1];

// TODO: read parameter from dram
wire [4:0] num_knls = 5'd16;
wire [4:0] depth = 5'd6;
wire [5:0] ifmap_width = 6'd14;
wire [5:0] ifmap_height = 6'd14;
wire [4:0] ifmap_depth = 5'd6;
wire [ADDR_WIDTH - 1:0] wts_base = 0;
wire [ADDR_WIDTH - 1:0] ifmap_base = 65536;
wire [ADDR_WIDTH - 1:0] ofmap_base = 131072;

/* forwarded wires */
assign cnt_ifmap_chnl = cnt_knl_chnl;

/* event flags */
assign knl_wts_last = (cnt_knl_wts == KNL_SIZE - 1);
assign knl_id_last = (cnt_knl_id == num_knls - 5'd1);
assign ifmap_delta_x_last = (cnt_ifmap_delta_x == KNL_WIDTH - 1);
assign ifmap_delta_y_last = (cnt_ifmap_delta_y == KNL_HEIGHT - 1);
assign ifmap_base_x_last = (cnt_ifmap_base_x == ifmap_width - KNL_WIDTH);
assign ifmap_base_y_last = (cnt_ifmap_base_y == ifmap_height - KNL_HEIGHT);
assign ifmap_chnl_last = (cnt_ifmap_chnl == ifmap_depth - 1);
assign ofmap_chnl_last = (cnt_ofmap_chnl == num_knls - 5'd1);
assign ofmap_chnl_ff_last = (cnt_ofmap_chnl_ff == num_knls - 5'd1);

/* delayed registers */
always@(posedge clk) begin
  if (~srstn)
    addr_in_ff <= 0;
  else 
    addr_in_ff <= addr_in;
end

always@(posedge clk) begin
  if (~srstn)
    cnt_ofmap_chnl_ff <= 0;
  else
    cnt_ofmap_chnl_ff <= cnt_ofmap_chnl;
end

always@(posedge clk) begin
  if (~srstn)
    cnt_ifmap_delta_y_ff <= 0;
  else
    cnt_ifmap_delta_y_ff <= cnt_ifmap_delta_y;
end

always@(posedge clk) begin
  if (~srstn)
    ifmap_base_x_last_ff <= 0;
  else
    ifmap_base_x_last_ff <= ifmap_base_x_last;
end

always@(posedge clk) begin
  if (~srstn)
    ifmap_base_y_last_ff <= 0;
  else
    ifmap_base_y_last_ff <= ifmap_base_y_last;
end

always@(posedge clk) begin
  if (~srstn)
    ifmap_chnl_last_ff <= 0;
  else
    ifmap_chnl_last_ff <= ifmap_chnl_last;
end

always@(posedge clk) begin
  if (~srstn)
    state_ff <= 0;
  else
    state_ff <= state;
end

/* finite state machine */
always@(posedge clk) begin
  /* state register */
  if (~srstn)
    state <= ST_IDLE;
  else
    state <= state_nx;
end

always@(*) begin
  /* next state logic */
  case (state)
  ST_IDLE: state_nx = (enable) ? ST_LD_KNLS : ST_IDLE;

  ST_LD_KNLS: state_nx = 
    (knl_wts_last & knl_id_last) ? ST_LD_IFMAP_FULL : ST_LD_KNLS;

  ST_LD_IFMAP_FULL: state_nx = 
    (ifmap_delta_x_last & ifmap_delta_y_last) ? ST_CONV : ST_LD_IFMAP_FULL;

  ST_LD_IFMAP_PART: state_nx = 
    (ifmap_delta_y_last) ? ST_CONV : ST_LD_IFMAP_PART;

  ST_CONV: state_nx =
    (~ofmap_chnl_ff_last) ? ST_CONV :
    (~ifmap_base_x_last_ff) ? ST_LD_IFMAP_PART :
    (~ifmap_base_y_last_ff) ? ST_LD_IFMAP_FULL :
    (~ifmap_chnl_last_ff) ? ST_LD_KNLS : ST_DONE;

  ST_DONE: state_nx = ST_IDLE;
  default: state_nx = ST_IDLE;
  endcase
end

always@(*) begin
  /* output logic: input memory address translator */
  case (state)
  ST_LD_KNLS: addr_in = wts_base + {
    cnt_knl_id[3:0], cnt_knl_chnl[3:0], cnt_knl_wts[4:0]};

  ST_LD_IFMAP_FULL: addr_in = ifmap_base + {
    cnt_ifmap_chnl[3:0], 
    cnt_ifmap_base_y[4:0] + {2'd0, cnt_ifmap_delta_y[2:0]},
    cnt_ifmap_base_x[4:0] + {2'd0, cnt_ifmap_delta_x[2:0]}}; 

  ST_LD_IFMAP_PART: addr_in = ifmap_base + {
    cnt_ifmap_chnl[3:0], 
    cnt_ifmap_base_y[4:0] + {2'd0, cnt_ifmap_delta_y[2:0]},
    cnt_ifmap_base_x[4:0] + {2'd0, cnt_ifmap_delta_x[2:0]} + KNL_WIDTH[4:0] - 5'd1};

  ST_CONV: addr_in = ofmap_base + {
    cnt_ofmap_chnl[3:0], cnt_ifmap_base_y[4:0], cnt_ifmap_base_x[4:0]};

  default: addr_in = 0;
  endcase
end

always@(*) begin
  /* output logic: output memory address translator */
  case (state)
  ST_CONV: addr_out = addr_in_ff;
  default: addr_out = 0;
  endcase
end

always@(*) begin
  /* output logic: dram enable signal */
  case (state)
  ST_LD_KNLS: begin
    dram_en_wr = 0;
    dram_en_rd = 1;
  end
  ST_LD_IFMAP_FULL: begin
    dram_en_wr = 0;
    dram_en_rd = 1;
  end
  ST_LD_IFMAP_PART: begin
    dram_en_wr = 0;
    dram_en_rd = 1;
  end
  ST_CONV: begin
    dram_en_wr = (state_ff == ST_CONV) ? 1 : 0;
    dram_en_rd = 1;
  end
  default: begin
    dram_en_wr = 0;
    dram_en_rd = 0;
  end
  endcase
end

/* output logic: done signal */
assign done = (state == ST_DONE);

/* convolution process */
assign data_out = data_in + mac;

always@(*) begin
  for (i = 0; i < KNL_HEIGHT; i = i + 1)
    for (j = 0; j < KNL_WIDTH; j = j + 1) begin
      products[i * KNL_WIDTH + j] = knls[(KNL_MAXNUM[4:0] - num_knls[4:0] + {1'b0, cnt_ofmap_chnl_ff[3:0]}) * KNL_SIZE + i * KNL_WIDTH + j] * ifmap[j * KNL_HEIGHT + i];
      products_roff[i * KNL_WIDTH + j] = {{16{products[i * KNL_WIDTH + j][DATA_WIDTH - 1]}}, products[i * KNL_WIDTH + j][DATA_WIDTH - 1:16]} + products[i * KNL_WIDTH + j][DATA_WIDTH - 1];
    end
end

always@(*) begin
  mac = 0;
  for (i = 0; i < KNL_HEIGHT; i = i + 1)
    for (j = 0; j < KNL_WIDTH; j = j + 1)
      mac = mac + products_roff[i * KNL_WIDTH + j];
end

/* weight register file */
always@(posedge clk) begin
  if (~srstn)
    for (i = 0; i < KNL_MAXNUM * KNL_SIZE; i = i + 1)
      knls[i] <= 0;
  else if (state_ff == ST_LD_KNLS) begin
    knls[KNL_MAXNUM * KNL_SIZE - 1] <= data_in;
    for (i = 0; i < KNL_MAXNUM * KNL_SIZE - 1; i = i + 1)
      knls[i] <= knls[i + 1];
  end
end

/* input feature map register file */
always@(posedge clk) begin
  if (~srstn)
    for (i = 0; i < KNL_SIZE; i = i + 1)
        ifmap[i] <= 0;
  else if (state_ff == ST_LD_IFMAP_FULL | state_ff == ST_LD_IFMAP_PART) begin
    ifmap[KNL_SIZE - 1] <= data_in;
    for (i = 0; i < KNL_SIZE - 1; i = i + 1)
      ifmap[i] <= ifmap[i + 1];
  end
end

/** 
 * counter to record how many weights we have loaded in one channel 
 * of one kernel
 */
always@(posedge clk) begin
  if (~srstn)
    cnt_knl_wts <= 0;
  else
    cnt_knl_wts <= cnt_knl_wts_nx;
end

always@(*) begin
  if (state == ST_LD_KNLS)
    if (knl_wts_last)
      cnt_knl_wts_nx = 5'd0;
    else
      cnt_knl_wts_nx = cnt_knl_wts + 5'd1;
  else
    cnt_knl_wts_nx = 5'd0;
end

/* counter to record which channel we are currently processing */
always@(posedge clk) begin
  if (~srstn)
    cnt_knl_chnl <= 0;
  else
    cnt_knl_chnl <= cnt_knl_chnl_nx;
end

always@(*) begin
  if (state == ST_IDLE)
    cnt_knl_chnl_nx = 0;
  else
    if (ifmap_base_x_last_ff & ifmap_base_y_last_ff & ofmap_chnl_ff_last)
      cnt_knl_chnl_nx = cnt_knl_chnl + 5'd1;
    else
      cnt_knl_chnl_nx = cnt_knl_chnl;
end

/* counter to record which kernel we are currently processing */
always@(posedge clk) begin
  if (~srstn)
    cnt_knl_id <= 0;
  else
    cnt_knl_id <= cnt_knl_id_nx;
end

always@(*) begin
  if (state == ST_LD_KNLS)
    if (knl_wts_last)
      if (knl_id_last)
        cnt_knl_id_nx = 0;
      else
        cnt_knl_id_nx = cnt_knl_id + 5'd1;
    else
      cnt_knl_id_nx = cnt_knl_id;
  else
    cnt_knl_id_nx = 0;
end

/* counter to record delta x */
always@(posedge clk) begin
  if (~srstn)
    cnt_ifmap_delta_x <= 0;
  else
    cnt_ifmap_delta_x <= cnt_ifmap_delta_x_nx;
end

always@(*) begin
  if (state == ST_LD_IFMAP_FULL)
    if (ifmap_delta_y_last)
      cnt_ifmap_delta_x_nx = cnt_ifmap_delta_x + 3'd1;
    else
      cnt_ifmap_delta_x_nx = cnt_ifmap_delta_x;
  else
    cnt_ifmap_delta_x_nx = 0;
end

/* counter to record delta y */
always@(posedge clk) begin
  if (~srstn)
    cnt_ifmap_delta_y <= 0;
  else
    cnt_ifmap_delta_y <= cnt_ifmap_delta_y_nx;
end

always@(*) begin
  if (state == ST_LD_IFMAP_FULL | state == ST_LD_IFMAP_PART)
    if (ifmap_delta_y_last)
      cnt_ifmap_delta_y_nx = 0;
    else
      cnt_ifmap_delta_y_nx = cnt_ifmap_delta_y + 3'd1;
  else
    cnt_ifmap_delta_y_nx = 0;
end

/* counter to record base x */
always@(posedge clk) begin
  if (~srstn)
    cnt_ifmap_base_x <= 0;
  else
    cnt_ifmap_base_x <= cnt_ifmap_base_x_nx;
end

always@(*) begin
  if (state == ST_LD_KNLS)
    cnt_ifmap_base_x_nx = 0;
  else
    if (ofmap_chnl_last)
      if (ifmap_base_x_last)
        cnt_ifmap_base_x_nx = 0;
      else
        cnt_ifmap_base_x_nx = cnt_ifmap_base_x + 6'd1;
    else
      cnt_ifmap_base_x_nx = cnt_ifmap_base_x;
end

/* counter to record base y */
always@(posedge clk) begin
  if (~srstn)
    cnt_ifmap_base_y <= 0;
  else
    cnt_ifmap_base_y <= cnt_ifmap_base_y_nx;
end

always@(*) begin
  if (state == ST_LD_KNLS)
    cnt_ifmap_base_y_nx = 0;
  else
    if (ifmap_base_x_last & ofmap_chnl_last)
      cnt_ifmap_base_y_nx = cnt_ifmap_base_y + 6'd1;
    else
      cnt_ifmap_base_y_nx = cnt_ifmap_base_y;
end

/* counter to record how many MACs we've done */
always@(posedge clk) begin
  if (~srstn)
    cnt_ofmap_chnl <= 0;
  else
    cnt_ofmap_chnl <= cnt_ofmap_chnl_nx;
end

always@(*) begin
  if (state == ST_CONV)
    if (ofmap_chnl_last)
      cnt_ofmap_chnl_nx = 0;
    else
      cnt_ofmap_chnl_nx = cnt_ofmap_chnl + 1;
  else
    cnt_ofmap_chnl_nx = 0;
end

endmodule

