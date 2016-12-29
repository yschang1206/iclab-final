module conv_ctrl
#
(
  parameter DATA_WIDTH = 32,
  parameter ADDR_WIDTH = 18,
  parameter KNL_WIDTH = 5'd5,
  parameter KNL_HEIGHT = 5'd5,
  parameter KNL_SIZE = KNL_WIDTH * KNL_HEIGHT,  // unit: 32 bits
  parameter KNL_MAXNUM = 16
)
(
  // I/O for top module
  input clk,
  input srstn,
  input enable,
  input [DATA_WIDTH - 1:0] data_in,
  output reg [ADDR_WIDTH - 1:0] addr_in,
  output reg [ADDR_WIDTH - 1:0] addr_out,
  output reg dram_en_wr,
  output reg dram_en_rd,
  output wire done,

  // I/O for conv
  output reg en_ld_knl,
  output reg en_ld_ifmap,
  output reg disable_acc,
  output reg [5:0] num_knls,
  output reg [4:0] cnt_ofmap_chnl_ff
);

/* local parameters */
localparam  IDX_IDLE          = 0, 
            IDX_LD_PARAM      = 1,
            IDX_LD_KNLS       = 2, 
            IDX_LD_IFMAP_FULL = 3, 
            IDX_LD_IFMAP_PART = 4, 
            IDX_CONV          = 5,
            IDX_DONE          = 6;

localparam  ST_IDLE          = 7'b0000001, 
            ST_LD_PARAM      = 7'b0000010,
            ST_LD_KNLS       = 7'b0000100, 
            ST_LD_IFMAP_FULL = 7'b0001000, 
            ST_LD_IFMAP_PART = 7'b0010000, 
            ST_CONV          = 7'b0100000,
            ST_DONE          = 7'b1000000;

localparam  PARAM_BASE = 18'd0,
            WTS_BASE   = 18'd64,
            IFMAP_BASE = 18'd65536,
            OFMAP_BASE = 18'd131072;

localparam  NUM_PARAM = 6'd4; // TODO: add table

/* global wires, registers and integers */
integer i, j;
reg [7:0] state, state_nx;
wire knl_wts_last, knl_id_last;
wire ifmap_delta_x_last, ifmap_delta_y_last;
wire ifmap_base_x_last, ifmap_base_y_last;
wire ifmap_chnl_last;
wire ifmap_chnl_first;
wire ofmap_chnl_last;

reg ifmap_chnl_last_ff;
reg ifmap_base_x_last_ff, ifmap_base_y_last_ff;
reg ofmap_chnl_last_ff;
// delay one cycle to read and write psum of output feature map
reg [ADDR_WIDTH - 1:0] addr_in_ff;

/* registers for parameters */
reg [5:0] cnt_param, cnt_param_nx;
reg [5:0] ifmap_depth, ifmap_height, ifmap_width; // with num_knls
wire param_last;
reg param_last_ff;

/* wires and registers for kernels */
reg [4:0] cnt_knl_id, cnt_knl_id_nx;      // kernel id
reg [4:0] cnt_knl_chnl, cnt_knl_chnl_nx;  // kernel channel
reg [4:0] cnt_knl_wts, cnt_knl_wts_nx;    // kernel weights

/* wires and registers for input feature map */
wire [4:0] cnt_ifmap_chnl;  // equals to cnt_knl_chnl
reg [5:0] cnt_ifmap_base_x, cnt_ifmap_base_x_nx;
reg [5:0] cnt_ifmap_base_y, cnt_ifmap_base_y_nx;
reg [2:0] cnt_ifmap_delta_x, cnt_ifmap_delta_x_nx;
reg [2:0] cnt_ifmap_delta_y, cnt_ifmap_delta_y_nx;

/* wires and registers for output feature map */
reg [4:0] cnt_ofmap_chnl, cnt_ofmap_chnl_nx;  // output channel

/* enable for some states */
reg en_conv;
reg en_ld_ifmap_nx;

/* forwarded wires */
assign cnt_ifmap_chnl = cnt_knl_chnl;

/* event flags */
assign knl_wts_last = (cnt_knl_wts == KNL_SIZE-1);
assign knl_id_last  = (cnt_knl_id + 1  == num_knls);
assign ifmap_delta_x_last = (cnt_ifmap_delta_x == KNL_WIDTH-1);
assign ifmap_delta_y_last = (cnt_ifmap_delta_y == KNL_HEIGHT-1);
assign ifmap_base_x_last  = (cnt_ifmap_base_x + KNL_WIDTH  == ifmap_width);
assign ifmap_base_y_last  = (cnt_ifmap_base_y + KNL_HEIGHT == ifmap_height);
assign ifmap_chnl_last    = (cnt_ifmap_chnl + 1 == ifmap_depth);
assign ifmap_chnl_first   = (cnt_ifmap_chnl == 0);
assign ofmap_chnl_last    = (cnt_ofmap_chnl + 1 == num_knls);
assign param_last = (cnt_param == NUM_PARAM-1);

/* delayed registers */
always@(posedge clk) begin
  if (~srstn) begin
    addr_in_ff <= 0;
    param_last_ff <= 0;
    cnt_ofmap_chnl_ff <= 0;
    ifmap_base_x_last_ff <= 0;
    ifmap_base_y_last_ff <= 0;
    ifmap_chnl_last_ff <= 0;
    ofmap_chnl_last_ff <= 0;
    en_conv <= 0;
    en_ld_knl <= 0;
    en_ld_ifmap <= 0;
    disable_acc <= 0;
    state <= ST_IDLE;
  end
  else begin
    addr_in_ff <= addr_in;
    param_last_ff <= param_last;
    cnt_ofmap_chnl_ff <= cnt_ofmap_chnl;
    ifmap_base_x_last_ff <= ifmap_base_x_last;
    ifmap_base_y_last_ff <= ifmap_base_y_last;
    ifmap_chnl_last_ff <= ifmap_chnl_last;
    ofmap_chnl_last_ff <= ofmap_chnl_last;
    en_conv <= state[IDX_CONV];
    en_ld_knl <= state[IDX_LD_KNLS];
    en_ld_ifmap <= en_ld_ifmap_nx;
    disable_acc <= ifmap_chnl_first;
    state <= state_nx;
  end
end

always@(*) begin
  /* next state logic */
  case (state)
    ST_IDLE: state_nx = (enable) ? ST_LD_PARAM : ST_IDLE;

    ST_LD_PARAM: state_nx = (param_last_ff) ? ST_LD_KNLS : ST_LD_PARAM;

    ST_LD_KNLS: state_nx = (knl_wts_last & knl_id_last) ? ST_LD_IFMAP_FULL : ST_LD_KNLS;

    ST_LD_IFMAP_FULL: state_nx = (ifmap_delta_x_last & ifmap_delta_y_last) ? ST_CONV : ST_LD_IFMAP_FULL;

    ST_LD_IFMAP_PART: state_nx = (ifmap_delta_y_last) ? ST_CONV : ST_LD_IFMAP_PART;

    ST_CONV: state_nx = (~ofmap_chnl_last_ff)   ? ST_CONV :
                        (~ifmap_base_x_last_ff) ? ST_LD_IFMAP_PART :
                        (~ifmap_base_y_last_ff) ? ST_LD_IFMAP_FULL :
                        (~ifmap_chnl_last_ff)   ? ST_LD_KNLS : ST_DONE;

    ST_DONE: state_nx = ST_IDLE;
    default: state_nx = ST_IDLE;
  endcase
end

always@(*) begin // input memory address translator
  case ({state[IDX_LD_PARAM], state[IDX_LD_KNLS], state[IDX_LD_IFMAP_FULL], state[IDX_LD_IFMAP_PART], state[IDX_CONV]}) // synopsys parallel_case
    5'b10000 : addr_in = PARAM_BASE + {12'd0, cnt_param};
    5'b01000 : addr_in = WTS_BASE + {5'd0,
                        cnt_knl_id[3:0], cnt_knl_chnl[3:0], cnt_knl_wts[4:0]};
    5'b00100 : addr_in = IFMAP_BASE + {4'd0, cnt_ifmap_chnl[3:0], 
                        cnt_ifmap_base_y[4:0] + {2'd0, cnt_ifmap_delta_y[2:0]},
                        cnt_ifmap_base_x[4:0] + {2'd0, cnt_ifmap_delta_x[2:0]}}; 
    5'b00010 : addr_in = IFMAP_BASE + {4'd0, cnt_ifmap_chnl[3:0], 
                        cnt_ifmap_base_y[4:0] + {2'd0, cnt_ifmap_delta_y[2:0]},
                        cnt_ifmap_base_x[4:0] + {2'd0, cnt_ifmap_delta_x[2:0]} + KNL_WIDTH - 5'd1};
    5'b00001 : addr_in = OFMAP_BASE + {4'd0,
                        cnt_ofmap_chnl[3:0], cnt_ifmap_base_y[4:0], cnt_ifmap_base_x[4:0]};
    default: addr_in = 0;
  endcase
end

always @(*) begin // output logic: output memory address translator
  if (state[IDX_CONV]) addr_out = addr_in_ff;
  else                 addr_out = 0;
end

always @(*) begin // output logic: dram enable signal
  if (state[IDX_CONV] & en_conv) dram_en_wr = 1'b1;
  else dram_en_wr = 1'b0;
end

always @(*) begin // output logic: dram enable signal
  if (state[IDX_IDLE] | state[IDX_DONE]) dram_en_rd = 1'b0;
  else dram_en_rd = 1'b1;
end

always @(*) begin // enable for load ifmap
  if (state[IDX_LD_IFMAP_FULL] | state[IDX_LD_IFMAP_PART]) en_ld_ifmap_nx = 1'b1;
  else en_ld_ifmap_nx = 1'b0;
end

/* output logic: done signal */
assign done = state[IDX_DONE];

/* parameter register file */
always @(posedge clk) begin
  if (state[IDX_LD_PARAM]) begin
    num_knls <= data_in[5:0];
    ifmap_depth <= num_knls;
    ifmap_height <= ifmap_depth;
    ifmap_width <= ifmap_height;
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

/*
 * counter to record how many weights we have loaded in one channel 
 * of one kernel
 */
always @(posedge clk) begin
  if (~srstn) cnt_knl_wts <= 0;
  else        cnt_knl_wts <= cnt_knl_wts_nx;
end
always @(*) begin
  if (state[IDX_LD_KNLS] & !knl_wts_last) cnt_knl_wts_nx = cnt_knl_wts + 5'd1;
  else cnt_knl_wts_nx = 5'd0;
end

/* counter to record which channel we are currently processing */
always@(posedge clk) begin
  if (~srstn) cnt_knl_chnl <= 0;
  else        cnt_knl_chnl <= cnt_knl_chnl_nx;
end
always @(*) begin
  case ({state[IDX_IDLE], ifmap_base_x_last_ff, ifmap_base_y_last_ff, ofmap_chnl_last_ff}) // synopsys parallel_case
    4'b0000 : cnt_knl_chnl_nx = cnt_knl_chnl;
    4'b0001 : cnt_knl_chnl_nx = cnt_knl_chnl;
    4'b0010 : cnt_knl_chnl_nx = cnt_knl_chnl;
    4'b0011 : cnt_knl_chnl_nx = cnt_knl_chnl;
    4'b0100 : cnt_knl_chnl_nx = cnt_knl_chnl;
    4'b0101 : cnt_knl_chnl_nx = cnt_knl_chnl;
    4'b0110 : cnt_knl_chnl_nx = cnt_knl_chnl;
    4'b0111 : cnt_knl_chnl_nx = cnt_knl_chnl + 5'd1;
    default : cnt_knl_chnl_nx = 0;
  endcase
end

/* counter to record which kernel we are currently processing */
always@(posedge clk) begin
  if (~srstn) cnt_knl_id <= 0;
  else        cnt_knl_id <= cnt_knl_id_nx;
end
always @(*) begin
  case ({state[IDX_LD_KNLS], knl_wts_last, knl_id_last}) // synopsys parallel_case
    3'b100  : cnt_knl_id_nx = cnt_knl_id;
    3'b101  : cnt_knl_id_nx = cnt_knl_id;
    3'b110  : cnt_knl_id_nx = cnt_knl_id + 5'd1;
    default : cnt_knl_id_nx = 0;
  endcase
end

/* counter to record delta x */
always@(posedge clk) begin
  if (~srstn) cnt_ifmap_delta_x <= 0;
  else        cnt_ifmap_delta_x <= cnt_ifmap_delta_x_nx;
end
always@(*) begin
  case ({state[IDX_LD_IFMAP_FULL], ifmap_delta_y_last}) // synopsys parallel_case
    2'b10   : cnt_ifmap_delta_x_nx = cnt_ifmap_delta_x;
    2'b11   : cnt_ifmap_delta_x_nx = cnt_ifmap_delta_x + 3'd1;
    default : cnt_ifmap_delta_x_nx = 0;
  endcase
end

/* counter to record delta y */
always @(posedge clk) begin
  if (~srstn) cnt_ifmap_delta_y <= 0;
  else        cnt_ifmap_delta_y <= cnt_ifmap_delta_y_nx;
end
always @(*) begin
  case ({state[IDX_LD_IFMAP_FULL], state[IDX_LD_IFMAP_PART], ifmap_delta_y_last}) // synopsys parallel_case
    3'b010  : cnt_ifmap_delta_y_nx = cnt_ifmap_delta_y + 3'd1;
    3'b100  : cnt_ifmap_delta_y_nx = cnt_ifmap_delta_y + 3'd1;
    3'b110  : cnt_ifmap_delta_y_nx = cnt_ifmap_delta_y + 3'd1;
    default : cnt_ifmap_delta_y_nx = 0;
  endcase
end

/* counter to record base x */
always@(posedge clk) begin
  if (~srstn) cnt_ifmap_base_x <= 0;
  else        cnt_ifmap_base_x <= cnt_ifmap_base_x_nx;
end
always @(*) begin
  case ({state[IDX_LD_KNLS], ifmap_base_x_last, ofmap_chnl_last}) // synopsys parallel_case
    3'b000  : cnt_ifmap_base_x_nx = cnt_ifmap_base_x;
    3'b001  : cnt_ifmap_base_x_nx = cnt_ifmap_base_x + 6'd1;
    3'b010  : cnt_ifmap_base_x_nx = cnt_ifmap_base_x;
    default : cnt_ifmap_base_x_nx = 0;
  endcase
end

/* counter to record base y */
always@(posedge clk) begin
  if (~srstn) cnt_ifmap_base_y <= 0;
  else        cnt_ifmap_base_y <= cnt_ifmap_base_y_nx;
end
always @(*) begin
  case ({state[IDX_LD_KNLS], ifmap_base_x_last, ofmap_chnl_last}) // synopsys parallel_case
    3'b000  : cnt_ifmap_base_y_nx = cnt_ifmap_base_y;
    3'b001  : cnt_ifmap_base_y_nx = cnt_ifmap_base_y;
    3'b010  : cnt_ifmap_base_y_nx = cnt_ifmap_base_y;
    3'b011  : cnt_ifmap_base_y_nx = cnt_ifmap_base_y + 6'd1;
    default : cnt_ifmap_base_y_nx = 0;
  endcase
end

/* counter to record how many MACs we've done */
always @(posedge clk) begin
  if (~srstn) cnt_ofmap_chnl <= 0;
  else        cnt_ofmap_chnl <= cnt_ofmap_chnl_nx;
end
always @(*) begin
  if (state[IDX_CONV] & !ofmap_chnl_last) cnt_ofmap_chnl_nx = cnt_ofmap_chnl + 1;
  else cnt_ofmap_chnl_nx = 0;
end

endmodule
