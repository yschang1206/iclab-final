/**
 * conv_layer.v
 */

module conv_layer
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
reg [2:0] state, state_nx;
wire knl_wts_last, knl_id_last;
wire ifmap_delta_x_last, ifmap_delta_y_last;
wire ifmap_base_x_last, ifmap_base_y_last;
wire ifmap_chnl_last;
wire ofmap_chnl_last;
// delay one cycle for data to be loaded in reg files
reg ld_knls_to_ld_ifmap_full_ff;
reg ld_ifmap_full_to_ld_conv_ff;
reg ld_ifmap_part_to_ld_conv_ff;
// delay two cycles to read and write psum of output feature map
reg conv_to_next_ff[1:0];
reg [ADDR_WIDTH - 1:0] addr_in_ff[0:1];

/* wires and registers for kernels */
reg [DATA_WIDTH - 1:0] knls[0:KNL_MAXNUM - 1][0:KNL_SIZE - 1];
reg [6:0] cnt_knl_id, cnt_knl_id_nx;      // kernel id
reg [4:0] cnt_knl_chnl, cnt_knl_chnl_nx;  // kernel channel
reg [4:0] cnt_knl_wts, cnt_knl_wts_nx;    // kernel weights

/* wires and registers for input feature map */
reg [DATA_WIDTH - 1:0] ifmap[0:KNL_HEIGHT - 1][0:KNL_WIDTH - 1];
wire [4:0] cnt_ifmap_chnl;  // equals to cnt_knl_chnl
reg [5:0] cnt_ifmap_base_x, cnt_ifmap_base_x_nx;
reg [5:0] cnt_ifmap_base_y, cnt_ifmap_base_y_nx;
reg [2:0] cnt_ifmap_delta_x, cnt_ifmap_delta_x_nx;
reg [2:0] cnt_ifmap_delta_y, cnt_ifmap_delta_y_nx;

/* wires and registers for output feature map */
reg [DATA_WIDTH - 1:0] macs;
reg [4:0] cnt_ofmap_chnl, cnt_ofmap_chnl_nx;  // output channel
reg [4:0] cnt_ofmap_chnl_ff[0:1];
reg [2 * DATA_WIDTH - 1:0] product;

// TODO: read parameter from dram
wire [6:0] num_knls = 7'd6;
wire [4:0] depth = 1;
wire [5:0] ifmap_width = 6'd32;
wire [5:0] ifmap_height = 6'd32;
wire [4:0] ifmap_depth = 5'd1;
wire [ADDR_WIDTH - 1:0] wts_base = 0;
wire [ADDR_WIDTH - 1:0] ifmap_base = 3072;
wire [ADDR_WIDTH - 1:0] ofmap_base = 4096;

/* forwarded wires */
assign cnt_ifmap_chnl = cnt_knl_chnl;

/* event flags */
assign knl_wts_last = (cnt_knl_wts == KNL_SIZE - 1);
assign knl_id_last = (cnt_knl_id == num_knls - 7'd1);
assign ifmap_delta_x_last = (cnt_ifmap_delta_x == KNL_WIDTH - 1);
assign ifmap_delta_y_last = (cnt_ifmap_delta_y == KNL_HEIGHT - 1);
assign ifmap_base_x_last = (cnt_ifmap_base_x == ifmap_width - KNL_WIDTH);
assign ifmap_base_y_last = (cnt_ifmap_base_y == ifmap_height - KNL_HEIGHT);
assign ifmap_chnl_last = (cnt_ifmap_chnl == ifmap_depth - 1);
assign ofmap_chnl_last = (cnt_ofmap_chnl == num_knls - 7'd1);

/* delayed registers */
always@(posedge clk) begin
  if (~srstn)
    ld_knls_to_ld_ifmap_full_ff <= 0;
  else
    ld_knls_to_ld_ifmap_full_ff <= knl_wts_last & knl_id_last;
end

always@(posedge clk) begin
  if (~srstn)
    ld_ifmap_full_to_ld_conv_ff <= 0;
  else
    ld_ifmap_full_to_ld_conv_ff <= ifmap_delta_x_last * ifmap_delta_y_last;
end

always@(posedge clk) begin
  if (~srstn)
    ld_ifmap_part_to_ld_conv_ff <= 0;
  else
    ld_ifmap_part_to_ld_conv_ff <= ifmap_delta_y_last;
end

always@(posedge clk) begin
  if (~srstn) begin
    conv_to_next_ff[0] <= 0;
    conv_to_next_ff[1] <= 0;
  end
  else begin
    conv_to_next_ff[0] <= ofmap_chnl_last;
    conv_to_next_ff[1] <= conv_to_next_ff[0];
  end
end

always@(posedge clk) begin
  if (~srstn) begin
    addr_in_ff[0] <= 0;
    addr_in_ff[1] <= 0;
  end
  else begin
    addr_in_ff[0] <= addr_in;
    addr_in_ff[1] <= addr_in_ff[0];
  end
end

always@(posedge clk) begin
  if (~srstn) begin
    cnt_ofmap_chnl_ff[0] <= 0;
    cnt_ofmap_chnl_ff[1] <= 0;
  end
  else begin
    cnt_ofmap_chnl_ff[0] <= cnt_ofmap_chnl;
    cnt_ofmap_chnl_ff[1] <= cnt_ofmap_chnl_ff[0];
  end
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
    (ld_knls_to_ld_ifmap_full_ff) ? ST_LD_IFMAP_FULL : ST_LD_KNLS;

  ST_LD_IFMAP_FULL: state_nx = 
    (ld_ifmap_full_to_ld_conv_ff) ? ST_CONV : ST_LD_IFMAP_FULL;

  ST_LD_IFMAP_PART: state_nx = 
    (ld_ifmap_part_to_ld_conv_ff) ? ST_CONV : ST_LD_IFMAP_PART;

  ST_CONV: state_nx =
    (~conv_to_next_ff[1]) ? ST_CONV :
    (~ifmap_base_x_last) ? ST_LD_IFMAP_PART :
    (~ifmap_base_y_last) ? ST_LD_IFMAP_FULL :
    (~ifmap_chnl_last) ? ST_LD_KNLS : ST_DONE;

  ST_DONE: state_nx = ST_IDLE;
  default: state_nx = ST_IDLE;
  endcase
end

always@(*) begin
  /* output logic: input memory address translator */
  case (state)
  ST_LD_KNLS: addr_in = wts_base + {
    cnt_knl_id[6:0], cnt_knl_chnl[3:0], cnt_knl_wts[4:0]};

  ST_LD_IFMAP_FULL: addr_in = ifmap_base + {
    cnt_ifmap_chnl[3:0], 
    cnt_ifmap_base_x[4:0] + {2'd0, cnt_ifmap_delta_x[2:0]}, 
    cnt_ifmap_base_y[4:0] + {2'd0, cnt_ifmap_delta_y[2:0]}};

  ST_LD_IFMAP_PART: addr_in = ifmap_base + {
    cnt_ifmap_chnl[3:0], 
    cnt_ifmap_base_x[4:0] + {2'd0, cnt_ifmap_delta_x[2:0]}, 
    cnt_ifmap_base_y[4:0] + {2'd0, cnt_ifmap_delta_y[2:0]}};

  ST_CONV: addr_in = ofmap_base + {
    cnt_ofmap_chnl[3:0], cnt_ifmap_base_x[4:0], cnt_ifmap_base_y[4:0]};

  default: addr_in = 0;
  endcase
end

always@(*) begin
  /* output logic: output memory address translator */
  case (state)
  ST_CONV: addr_out = addr_in_ff[1];
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
    dram_en_wr = 1;
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
assign data_out = data_in + macs;

always@(*) begin
  macs = 0;
  for (i = 0; i < KNL_HEIGHT; i = i + 1)
    for (j = 0; j < KNL_WIDTH; j = j + 1) begin
      product = knls[cnt_ofmap_chnl_ff[1]][i * KNL_HEIGHT + j] * ifmap[i][j];
      macs = macs + {{16{product[63]}}, product[63:48]};
    end
end

/* weight register file */
always@(posedge clk) begin
  if (~srstn)
    for (i = 0; i < KNL_MAXNUM; i = i + 1)
      for (j = 0; j < KNL_SIZE; j = j + 1)
        knls[i][j] <= 0;
  else begin
    if (state == ST_LD_KNLS) begin
      knls[0][0] <= data_in;
      for (i = 1; i < KNL_MAXNUM; i = i + 1)
        knls[i][0] <= knls[i - 1][KNL_SIZE - 1];
      for (i = 0; i < KNL_MAXNUM; i = i + 1)
        for (j = 1; j < KNL_SIZE; j = j + 1)
          knls[i][j] <= knls[i][j - 1];
    end
  end
end

/* input feature map register file */
always@(posedge clk) begin
  if (~srstn)
    for (i = 0; i < KNL_HEIGHT; i = i + 1)
      for (j = 0; j < KNL_WIDTH; j = j + 1)
        ifmap[i][j] <= 0;
  else
    if (state == ST_LD_IFMAP_FULL | state == ST_LD_IFMAP_PART)
      for (i = 0; i < KNL_HEIGHT; i = i + 1)
        if (cnt_ifmap_delta_y == i) begin
          ifmap[i][0] <= data_in;
          for (j = 1; j < KNL_WIDTH; j = j + 1)
            ifmap[i][j] <= ifmap[i][j - 1];
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
    if (ifmap_base_x_last & ifmap_base_y_last & ofmap_chnl_last)
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
        cnt_knl_id_nx = cnt_knl_id + 7'd1;
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
    cnt_ofmap_chnl_nx = cnt_ofmap_chnl + 1;
  else
    cnt_ofmap_chnl_nx = 0;
end

endmodule

