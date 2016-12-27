/**
 * max_pool.v
 */

module max_pool
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
  output reg [DATA_WIDTH - 1:0] data_out,
  output reg [ADDR_WIDTH - 1:0] addr_in,
  output reg [ADDR_WIDTH - 1:0] addr_out,
  output reg dram_en_wr,
  output reg dram_en_rd,
  output wire done
);

localparam  ST_IDLE = 3'd0,
            ST_LD_PARAM = 3'd1,
            ST_POOL = 3'd3,
            ST_DONE = 3'd4;

localparam  PARAM_BASE = 0,
            OFMAP_BASE = 65536,
            IFMAP_BASE = 131072;

/* global regs, wires and integers */
reg [DATA_WIDTH - 1:0] ifmap[0:3];
reg [2:0] state, state_nx;
wire ifmap_base_x_last, ifmap_base_y_last, ifmap_z_last;
wire ifmap_delta_x_last, ifmap_delta_y_last;
reg [ADDR_WIDTH - 1:0] addr_out_buf[0:1];
reg [ADDR_WIDTH - 1:0] addr_out_buf_nx;
reg [DATA_WIDTH - 1:0] data_out_nx;
reg pixel_rdy[0:2];
reg pool_done;
integer i;
// TODO: replace delta x and y with one 2-bits reg

/* regs for pooling */
reg [5:0] cnt_ifmap_base_x, cnt_ifmap_base_x_nx;
reg cnt_ifmap_delta_x, cnt_ifmap_delta_x_nx;
reg [5:0] cnt_ifmap_base_y, cnt_ifmap_base_y_nx;
reg cnt_ifmap_delta_y, cnt_ifmap_delta_y_nx;
reg [5:0] cnt_ifmap_z, cnt_ifmap_z_nx;

/* wire for comparison */
wire ifmap0_lt_ifmap1, ifmap_2_lt_ifmap3;
wire [DATA_WIDTH - 1:0] ifmap01_max, ifmap23_max;

// TODO: read parameters from dram
wire [5:0] ifmap_width = 6'd10;
wire [5:0] ifmap_height = 6'd10;
wire [4:0] ifmap_depth = 5'd16;

/* event flags */
assign ifmap_base_x_last = (cnt_ifmap_base_x == ifmap_width - 6'd2);
assign ifmap_base_y_last = (cnt_ifmap_base_y == ifmap_height - 6'd2);
assign ifmap_z_last = (cnt_ifmap_z == ifmap_depth - 1);
assign ifmap_delta_x_last = cnt_ifmap_delta_x;
assign ifmap_delta_y_last = cnt_ifmap_delta_y;

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
    ST_IDLE: state_nx = (enable) ? ST_LD_PARAM : ST_IDLE;
    ST_LD_PARAM: state_nx = ST_POOL;
    ST_POOL: state_nx = (pool_done) ? ST_DONE : ST_POOL;
    ST_DONE: state_nx = ST_IDLE;
    default: state_nx = ST_IDLE;
  endcase
end

always@(*) begin
  /* output logic: input memory address translator */
  case (state)
    ST_POOL: addr_in = IFMAP_BASE + {
      cnt_ifmap_z[3:0],
      cnt_ifmap_base_y[4:0] + {4'd0, cnt_ifmap_delta_y},
      cnt_ifmap_base_x[4:0] + {4'd0, cnt_ifmap_delta_x}};
    default: addr_in = 0;
  endcase
end

always@(posedge clk) begin
  if (~srstn)
    addr_out <= 0;
  else
    addr_out <= addr_out_buf[1];
end

always@(posedge clk) begin
  if (~srstn) begin
    addr_out_buf[0] <= 0;
    addr_out_buf[1] <= 0;
  end
  else begin
    addr_out_buf[0] <= addr_out_buf_nx;
    addr_out_buf[1] <= addr_out_buf[0];
  end
end

always@(*) begin
  /* output logic: output memory address translator */
  case (state)
    ST_POOL: addr_out_buf_nx = OFMAP_BASE + {
      cnt_ifmap_z[3:0],
      {1'd0, cnt_ifmap_base_y[4:1]},
      {1'd0, cnt_ifmap_base_x[4:1]}
    };
    default: addr_out_buf_nx = 0;
  endcase
end

always@(*) begin
  /* output logic: dram enable signal */
  case (state)
    ST_POOL: begin
      dram_en_wr = pixel_rdy[2];
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

always@(posedge clk) begin
  if (~srstn) begin
    pixel_rdy[0] <= 0;
    pixel_rdy[1] <= 0;
    pixel_rdy[2] <= 0;
  end
  else begin
    pixel_rdy[0] <= ifmap_delta_x_last & ifmap_delta_y_last;
    pixel_rdy[1] <= pixel_rdy[0];
    pixel_rdy[2] <= pixel_rdy[1];
  end
end

/* input feature map register file */
always@(posedge clk) begin
  if (~srstn)
    for (i = 0; i < 4; i = i + 1)
      ifmap[i] <= 0;
  else begin
    ifmap[3] <= data_in;
    for (i = 0; i < 3; i = i + 1)
      ifmap[i] <= ifmap[i + 1];
  end
end

always@(posedge clk) begin
  if (~srstn)
    pool_done <= 0;
  else
    pool_done <= ifmap_base_x_last & ifmap_base_y_last &
      ifmap_delta_x_last & ifmap_delta_y_last & ifmap_z_last;
end

/* find the maximum value among the four pixel */
always@(posedge clk) begin
  if (~srstn)
    data_out <= 0;
  else
    data_out <= data_out_nx;
end

assign ifmap0_lt_ifmap1 = (ifmap[0] >= ifmap[1]);
assign ifmap2_lt_ifmap3 = (ifmap[2] >= ifmap[3]);
assign ifmap01_max = ifmap0_lt_ifmap1 ? ifmap[0] : ifmap[1];
assign ifmap23_max = ifmap2_lt_ifmap3 ? ifmap[2] : ifmap[3];
always@(*) begin
  if (ifmap01_max >= ifmap23_max)
    data_out_nx = ifmap01_max;
  else
    data_out_nx = ifmap23_max;
end

/* counter to record the base x of the currently loading pixel */
always@(posedge clk) begin
  if (~srstn)
    cnt_ifmap_base_x <= 0;
  else
    cnt_ifmap_base_x <= cnt_ifmap_base_x_nx;
end

always@(*) begin
  if (state == ST_POOL)
    if (ifmap_delta_x_last & ifmap_delta_y_last)
      if (ifmap_base_x_last)
        cnt_ifmap_base_x_nx = 0;
      else
        cnt_ifmap_base_x_nx = cnt_ifmap_base_x + 6'd2;
    else
      cnt_ifmap_base_x_nx = cnt_ifmap_base_x;
  else
    cnt_ifmap_base_x_nx = 0;
end

/* counter to record the base y of the currently loading pixel */
always@(posedge clk) begin
  if (~srstn)
    cnt_ifmap_base_y <= 0;
  else
    cnt_ifmap_base_y <= cnt_ifmap_base_y_nx;
end

always@(*) begin
  if (state == ST_POOL)
    if (ifmap_delta_x_last & ifmap_delta_y_last & ifmap_base_x_last)
      if (ifmap_base_y_last)
        cnt_ifmap_base_y_nx = 0;
      else
        cnt_ifmap_base_y_nx = cnt_ifmap_base_y + 6'd2;
    else
      cnt_ifmap_base_y_nx = cnt_ifmap_base_y;
  else
    cnt_ifmap_base_y_nx = 0;
end

/* counter to record the z axis of the currently loading pixel */
always@(posedge clk) begin
  if (~srstn)
    cnt_ifmap_z <= 0;
  else
    cnt_ifmap_z <= cnt_ifmap_z_nx;
end

always@(*) begin
  if (state == ST_POOL)
    if (ifmap_delta_x_last & ifmap_delta_y_last & ifmap_base_x_last & ifmap_base_y_last)
      cnt_ifmap_z_nx = cnt_ifmap_z + 1;
    else
      cnt_ifmap_z_nx = cnt_ifmap_z;
  else
    cnt_ifmap_z_nx = 0;
end

/* counter to record the delta x of the currently loading pixel */
always@(posedge clk) begin
  if (~srstn)
    cnt_ifmap_delta_x <= 0;
  else
    cnt_ifmap_delta_x <= cnt_ifmap_delta_x_nx;
end

always@(*) begin
  if (state == ST_POOL)
    cnt_ifmap_delta_x_nx = cnt_ifmap_delta_x + 1;
  else
    cnt_ifmap_delta_x_nx = 0;
end

/* counter to record the delta y of the currently loading pixel */
always@(posedge clk) begin
  if (~srstn)
    cnt_ifmap_delta_y <= 0;
  else
    cnt_ifmap_delta_y <= cnt_ifmap_delta_y_nx;
end

always@(*) begin
  if (state == ST_POOL)
    if (ifmap_delta_x_last)
      cnt_ifmap_delta_y_nx = cnt_ifmap_delta_y + 1;
    else
      cnt_ifmap_delta_y_nx = cnt_ifmap_delta_y;
  else
    cnt_ifmap_delta_y_nx = 0;
end

endmodule

