module conv_ctrl
#
(
  parameter DATA_WIDTH = 32,
  parameter ADDR_WIDTH = 18,
  parameter KNL_WIDTH = 5'd5,
  parameter KNL_HEIGHT = 5'd5,
  parameter KNL_SIZE = 5'd25,  // unit: 32 bits
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
  output [4:0] num_knls,
  output reg [3:0] cnt_ofmap_chnl,
  output reg en_mac
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

localparam  IDX_PARAM_LAST = 4'd9,    // by NUM_PARAM = 10
            IDX_DELTA_X_LAST = 3'd4,  // by KNL_WIDTH = 5
            IDX_DELTA_Y_LAST = 3'd4,  // by KNL_HEIGHT = 5
            IDX_KNL_WTS_LAST = 5'd24; // by KNL_SIZE = 25

localparam  IDX_KNLS   = 0, 
            IDX_DEPTH  = 1,
            IDX_HEIGHT = 2, 
            IDX_WIDTH  = 3;

/* global wires, registers and integers */
integer i, j;
reg [6:0] state, state_nx;  // 7-stages
wire knl_wts_last, knl_id_last;
wire ifmap_delta_x_last, ifmap_delta_y_last;
wire ifmap_base_x_last, ifmap_base_y_last;
wire ifmap_chnl_last;
wire ifmap_chnl_first;
wire ofmap_chnl_last;
wire [4:0] idx_knls_last;
wire [4:0] idx_depth_last;
wire [5:0] idx_height_last;
wire [5:0] idx_width_last;

reg ifmap_chnl_last_ff;
reg ifmap_base_x_last_ff, ifmap_base_y_last_ff;
reg ofmap_chnl_last_ff;

// delay one cycle to read and write psum of output feature map
reg [ADDR_WIDTH - 1:0] addr_in_ff;

/* wires and registers for parameters */
reg [3:0] cnt_param, cnt_param_nx;
reg [5:0] param_data [0:3];

wire [4:0] ifmap_depth; // with num_knls
wire [5:0] ifmap_height, ifmap_width; // 6-bits (Max:6'd32)
wire param_last;
reg param_last_ff;

/* connection table */
reg [15:0] conn_tbl[0:5];

/* wires and registers for kernels */
reg [3:0] cnt_knl_id, cnt_knl_id_nx;      // kernel id
reg [3:0] cnt_knl_chnl, cnt_knl_chnl_nx;  // kernel channel
reg [4:0] cnt_knl_wts, cnt_knl_wts_nx;    // kernel weights

/* wires and registers for input feature map */
wire [3:0] cnt_ifmap_chnl;  // equals to cnt_knl_chnl
reg [4:0] cnt_ifmap_base_x, cnt_ifmap_base_x_nx; // 5-bits (Max:5'd31)
reg [4:0] cnt_ifmap_base_y, cnt_ifmap_base_y_nx; // 5-bits (Max:5'd31)
reg [2:0] cnt_ifmap_delta_x, cnt_ifmap_delta_x_nx;
reg [2:0] cnt_ifmap_delta_y, cnt_ifmap_delta_y_nx;

/* wires and registers for output feature map */
reg [3:0] cnt_ofmap_chnl_nx;  // output channel

/* enable for some states */
reg en_ld_ifmap_nx;
reg en_mac_buf [0:1];

/* pipeline delay signals*/
reg [3:0] en_conv;
reg [3:0] cnt_ofmap_chnl_ff [0:1];

/* forwarded wires */
assign cnt_ifmap_chnl = cnt_knl_chnl;

/* event flags */
assign idx_knls_last   = num_knls - 5'd1;
assign idx_depth_last  = ifmap_depth - 5'd1;
assign idx_width_last  = ifmap_width - 6'd5;
assign idx_height_last = ifmap_height - 6'd5;

assign knl_wts_last = (cnt_knl_wts == IDX_KNL_WTS_LAST);
assign knl_id_last  = (cnt_knl_id == idx_knls_last[3:0]);
assign ifmap_delta_x_last = (cnt_ifmap_delta_x == IDX_DELTA_X_LAST);
assign ifmap_delta_y_last = (cnt_ifmap_delta_y == IDX_DELTA_Y_LAST);
assign ifmap_base_x_last  = (cnt_ifmap_base_x == idx_width_last[4:0]);
assign ifmap_base_y_last  = (cnt_ifmap_base_y == idx_height_last[4:0]);
assign ifmap_chnl_last    = (cnt_ifmap_chnl == idx_depth_last[3:0]);
assign ifmap_chnl_first   = (cnt_ifmap_chnl == 4'd0);
assign ofmap_chnl_last    = (cnt_ofmap_chnl_ff[1] == idx_knls_last[3:0]);
assign param_last = (cnt_param == IDX_PARAM_LAST);

/* delayed registers */
always@(posedge clk) begin
  if (~srstn) begin
    addr_in_ff <= 0;
    param_last_ff <= 0;
    ifmap_base_x_last_ff <= 0;
    ifmap_base_y_last_ff <= 0;
    ifmap_chnl_last_ff <= 0;
    en_ld_knl <= 0;
    en_ld_ifmap <= 0;
    disable_acc <= 0;
    state <= ST_IDLE;
  end
  else begin
    addr_in_ff <= addr_in;
    param_last_ff <= param_last;
    ifmap_base_x_last_ff <= ifmap_base_x_last;
    ifmap_base_y_last_ff <= ifmap_base_y_last;
    ifmap_chnl_last_ff <= ifmap_chnl_last;
    en_ld_knl <= state[IDX_LD_KNLS];
    en_ld_ifmap <= en_ld_ifmap_nx;
    disable_acc <= ifmap_chnl_first;
    state <= state_nx;
  end
end

always@(posedge clk) begin
  if (~srstn) begin
    ofmap_chnl_last_ff <= 0;
    cnt_ofmap_chnl_ff[0] <= 0;
    cnt_ofmap_chnl_ff[1] <= 0;
    en_conv[0] <= 0;
    en_conv[1] <= 0;
    en_conv[2] <= 0;
    en_conv[3] <= 0;
  end
  else begin
    ofmap_chnl_last_ff <= ofmap_chnl_last;
    cnt_ofmap_chnl_ff[0] <= cnt_ofmap_chnl;
    cnt_ofmap_chnl_ff[1] <= cnt_ofmap_chnl_ff[0];
    en_conv[0] <= state[IDX_CONV];
    en_conv[1] <= en_conv[0];
    en_conv[2] <= en_conv[1];
    en_conv[3] <= en_conv[2];
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
    5'b10000 : addr_in = PARAM_BASE + {14'd0, cnt_param};
    5'b01000 : addr_in = WTS_BASE + {5'd0,
                        cnt_knl_id, cnt_knl_chnl, cnt_knl_wts};
    5'b00100 : addr_in = IFMAP_BASE + {4'd0, cnt_ifmap_chnl, 
                        cnt_ifmap_base_y + {2'd0, cnt_ifmap_delta_y},
                        cnt_ifmap_base_x + {2'd0, cnt_ifmap_delta_x}}; 
    5'b00010 : addr_in = IFMAP_BASE + {4'd0, cnt_ifmap_chnl, 
                        cnt_ifmap_base_y + {2'd0, cnt_ifmap_delta_y},
                        cnt_ifmap_base_x + {2'd0, cnt_ifmap_delta_x} + 5'd4};
    5'b00001 : addr_in = OFMAP_BASE + {4'd0,
                        cnt_ofmap_chnl_ff[1], cnt_ifmap_base_y, cnt_ifmap_base_x};
    default: addr_in = 0;
  endcase
end

always @(*) begin // output logic: output memory address translator
  if (state[IDX_CONV]) addr_out = addr_in_ff;
  else                 addr_out = 0;
end

always @(*) begin // output logic: dram enable signal
  if (state[IDX_CONV] & en_conv[3]) dram_en_wr = 1'b1;
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

/* enable signal for connection table */
always@(posedge clk) begin
  if (~srstn) begin
    en_mac_buf[0] <= 0;
    en_mac_buf[1] <= 0;
    en_mac <= 0;
  end
  else begin
    en_mac_buf[0] <= conn_tbl[cnt_ifmap_chnl][cnt_ofmap_chnl];
    en_mac_buf[1] <= en_mac_buf[0];
    en_mac <= en_mac_buf[0];
  end
end

/* parameter register file and wires */
assign num_knls     = param_data[IDX_KNLS][4:0]; 
assign ifmap_depth  = param_data[IDX_DEPTH][4:0];
assign ifmap_height = param_data[IDX_HEIGHT];
assign ifmap_width  = param_data[IDX_WIDTH];

always @(posedge clk) begin
  if (~srstn) begin
    conn_tbl[5] <= 0;
    conn_tbl[4] <= 0;
    conn_tbl[3] <= 0;
    conn_tbl[2] <= 0;
    conn_tbl[1] <= 0;
    conn_tbl[0] <= 0;
    param_data[IDX_KNLS]   <= 0;
    param_data[IDX_DEPTH]  <= 0;
    param_data[IDX_HEIGHT] <= 0;
    param_data[IDX_WIDTH]  <= 0;
  end
  else if (state[IDX_LD_PARAM]) begin
    conn_tbl[5] <= data_in[15:0];
    conn_tbl[4] <= conn_tbl[5];
    conn_tbl[3] <= conn_tbl[4];
    conn_tbl[2] <= conn_tbl[3];
    conn_tbl[1] <= conn_tbl[2];
    conn_tbl[0] <= conn_tbl[1];
    param_data[IDX_KNLS]   <= conn_tbl[0][5:0];
    param_data[IDX_DEPTH]  <= param_data[IDX_KNLS];
    param_data[IDX_HEIGHT] <= param_data[IDX_DEPTH];
    param_data[IDX_WIDTH]  <= param_data[IDX_HEIGHT];
  end
end

/* counter registers */
always @(posedge clk) begin
  if (~srstn) begin
    cnt_param <= 0;
    cnt_knl_wts <= 0;
    cnt_knl_chnl <= 0;
    cnt_knl_id <= 0;
    cnt_ifmap_delta_x <= 0;
    cnt_ifmap_delta_y <= 0;
    cnt_ifmap_base_x <= 0;
    cnt_ifmap_base_y <= 0;
    cnt_ofmap_chnl <= 0;
  end
  else begin
    cnt_param <= cnt_param_nx;
    cnt_knl_wts <= cnt_knl_wts_nx;
    cnt_knl_chnl <= cnt_knl_chnl_nx;
    cnt_knl_id <= cnt_knl_id_nx;
    cnt_ifmap_delta_x <= cnt_ifmap_delta_x_nx;
    cnt_ifmap_delta_y <= cnt_ifmap_delta_y_nx;
    cnt_ifmap_base_x <= cnt_ifmap_base_x_nx;
    cnt_ifmap_base_y <= cnt_ifmap_base_y_nx;
    cnt_ofmap_chnl <= cnt_ofmap_chnl_nx;
  end
end

always @(*) begin // counter to record how many parameters have been read
  if (state[IDX_LD_PARAM]) cnt_param_nx = cnt_param + 4'd1;
  else cnt_param_nx = 4'd0;
end

always @(*) begin // counter to record how many weights we have loaded in one channel of one kernel
  if (state[IDX_LD_KNLS] & !knl_wts_last) cnt_knl_wts_nx = cnt_knl_wts + 5'd1;
  else cnt_knl_wts_nx = 5'd0;
end

always @(*) begin // counter to record which channel we are currently processing
  case ({state[IDX_IDLE], ifmap_base_x_last_ff, ifmap_base_y_last_ff, ofmap_chnl_last_ff}) // synopsys parallel_case
    4'b0000 : cnt_knl_chnl_nx = cnt_knl_chnl;
    4'b0001 : cnt_knl_chnl_nx = cnt_knl_chnl;
    4'b0010 : cnt_knl_chnl_nx = cnt_knl_chnl;
    4'b0011 : cnt_knl_chnl_nx = cnt_knl_chnl;
    4'b0100 : cnt_knl_chnl_nx = cnt_knl_chnl;
    4'b0101 : cnt_knl_chnl_nx = cnt_knl_chnl;
    4'b0110 : cnt_knl_chnl_nx = cnt_knl_chnl;
    4'b0111 : cnt_knl_chnl_nx = cnt_knl_chnl + 4'd1;
    default : cnt_knl_chnl_nx = 4'd0;
  endcase
end

always @(*) begin // counter to record which kernel we are currently processing
  case ({state[IDX_LD_KNLS], knl_wts_last, knl_id_last}) // synopsys parallel_case
    3'b100  : cnt_knl_id_nx = cnt_knl_id;
    3'b101  : cnt_knl_id_nx = cnt_knl_id;
    3'b110  : cnt_knl_id_nx = cnt_knl_id + 4'd1;
    default : cnt_knl_id_nx = 4'd0;
  endcase
end

always@(*) begin // counter to record delta x
  case ({state[IDX_LD_IFMAP_FULL], ifmap_delta_y_last}) // synopsys parallel_case
    2'b10   : cnt_ifmap_delta_x_nx = cnt_ifmap_delta_x;
    2'b11   : cnt_ifmap_delta_x_nx = cnt_ifmap_delta_x + 3'd1;
    default : cnt_ifmap_delta_x_nx = 3'd0;
  endcase
end

always @(*) begin // counter to record delta y
  case ({state[IDX_LD_IFMAP_FULL], state[IDX_LD_IFMAP_PART], ifmap_delta_y_last}) // synopsys parallel_case
    3'b010  : cnt_ifmap_delta_y_nx = cnt_ifmap_delta_y + 3'd1;
    3'b100  : cnt_ifmap_delta_y_nx = cnt_ifmap_delta_y + 3'd1;
    3'b110  : cnt_ifmap_delta_y_nx = cnt_ifmap_delta_y + 3'd1;
    default : cnt_ifmap_delta_y_nx = 3'd0;
  endcase
end

always @(*) begin // counter to record base x
  case ({state[IDX_LD_KNLS], ifmap_base_x_last, ofmap_chnl_last}) // synopsys parallel_case
    3'b000  : cnt_ifmap_base_x_nx = cnt_ifmap_base_x;
    3'b001  : cnt_ifmap_base_x_nx = cnt_ifmap_base_x + 5'd1;
    3'b010  : cnt_ifmap_base_x_nx = cnt_ifmap_base_x;
    default : cnt_ifmap_base_x_nx = 5'd0;
  endcase
end

always @(*) begin // counter to record base y
  case ({state[IDX_LD_KNLS], ifmap_base_x_last, ofmap_chnl_last}) // synopsys parallel_case
    3'b000  : cnt_ifmap_base_y_nx = cnt_ifmap_base_y;
    3'b001  : cnt_ifmap_base_y_nx = cnt_ifmap_base_y;
    3'b010  : cnt_ifmap_base_y_nx = cnt_ifmap_base_y;
    3'b011  : cnt_ifmap_base_y_nx = cnt_ifmap_base_y + 5'd1;
    default : cnt_ifmap_base_y_nx = 5'd0;
  endcase
end

always @(*) begin // counter to record how many MACs we've done
  if (en_conv[0] & !ofmap_chnl_last) cnt_ofmap_chnl_nx = cnt_ofmap_chnl + 4'd1;
  else cnt_ofmap_chnl_nx = 4'd0;
end

endmodule
