/**
 * conv_layer.v
 */

module conv_layer
#
(
  parameter DATA_WIDTH = 32,
  parameter ADDR_WIDTH = 18,
  parameter KNL_SIZE = 25,  // in unit: 32 bits
  parameter KNL_MAXNUM = 16
)
(
  input clk,
  input srstn,
  input enable,
  input [DATA_WIDTH - 1:0] data_in,
  output reg [DATA_WIDTH - 1:0] data_out,
  output reg [ADDR_WIDTH - 1:0] addr_in,
  output reg [ADDR_WIDTH - 1:0] addr_out,
  output reg dram_en_wr,
  output reg dram_en_rd
);

/* local parameters */
localparam  ST_IDLE = 3'd0, 
            ST_LD_KNLS = 3'd1, 
            ST_LD_IFMAP = 3'd2, 
            ST_CONV = 3'd3,
            ST_DONE = 3'd4;

/* integers */
integer i, j;
/* wires and registers */
reg [2:0] state, state_nx;
reg [DATA_WIDTH - 1:0] knls[0:KNL_MAXNUM - 1][0:KNL_SIZE - 1];
reg [4:0] cnt_knl_id, cnt_knl_id_nx;      // kernel id
reg [4:0] cnt_knl_chnl, cnt_knl_chnl_nx;  // kernel channel
reg [4:0] cnt_knl_wts, cnt_knl_wts_nx;    // kernel weights
// TODO: read parameter from dram
wire [4:0] num_knls = 5'd6;
wire [4:0] depth = 2;
wire [ADDR_WIDTH - 1:0] wts_base = 0;
wire [ADDR_WIDTH - 1:0] ifmaps_base;
wire [ADDR_WIDTH - 1:0] ofmaps_base;

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
    (cnt_knl_wts == (KNL_SIZE - 1) & cnt_knl_id == (num_knls - 5'd1)) ?
    ST_LD_IFMAP : ST_LD_KNLS;
  ST_LD_IFMAP: state_nx = ST_CONV;
  ST_CONV: state_nx = (cnt_knl_chnl == depth) ? ST_DONE : ST_LD_KNLS;
  ST_DONE: state_nx = ST_DONE;
  default: state_nx = ST_IDLE;
  endcase
end

always@(*) begin
  /* output logic: memory address translator */
  case (state)
  ST_LD_KNLS: addr_in = wts_base + 
    {cnt_knl_id[3:0], cnt_knl_chnl[3:0], cnt_knl_wts[4:0]};
  default: addr_in = 0;
  endcase
end

always@(*) begin
  /* output logic: dram enable signal */
  case (state)
  ST_LD_KNLS: begin
    dram_en_wr = 0;
    dram_en_rd = 1;
  end
  default: begin
    dram_en_wr = 0;
    dram_en_rd = 0;
  end
  endcase
end

/* weight registers file */
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
  if (state == ST_LD_KNLS) begin
    if (cnt_knl_wts == KNL_SIZE - 5'd1)
      cnt_knl_wts_nx = 5'd0;
    else
      cnt_knl_wts_nx = cnt_knl_wts + 5'd1;
  end
  else
    cnt_knl_wts_nx = 5'd0;
end

/* counter to record which channel we are currently loading */
always@(posedge clk) begin
  if (~srstn)
    cnt_knl_chnl <= 0;
  else
    cnt_knl_chnl <= cnt_knl_chnl_nx;
end

always@(*) begin
  if (state_nx == ST_LD_KNLS & state == ST_CONV)
    cnt_knl_chnl_nx = cnt_knl_chnl + 5'd1;
  else
    cnt_knl_chnl_nx = cnt_knl_chnl;
end

/* counter to record which kernel we are currently loading */
always@(posedge clk) begin
  if (~srstn)
    cnt_knl_id <= 0;
  else
    cnt_knl_id <= cnt_knl_id_nx;
end

always@(*) begin
  if (state == ST_LD_KNLS)
    if (cnt_knl_wts == KNL_SIZE - 5'd1)
      if (cnt_knl_id == num_knls - 5'd1)
        cnt_knl_id_nx = 0;
      else
        cnt_knl_id_nx = cnt_knl_id + 5'd1;
    else
      cnt_knl_id_nx = cnt_knl_id;
  else
    cnt_knl_id_nx = 0;
end

endmodule

