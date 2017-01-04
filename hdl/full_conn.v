/**
 * full_conn.v
 */

module full_conn
#
(
  parameter DATA_WIDTH = 32, 
  parameter ADDR_WIDTH = 18 
)
(
  input clk,
  input srstn,
  input enable,
  input dram_valid,
  input [DATA_WIDTH - 1:0] data_in,
  output [DATA_WIDTH - 1:0] data_out,
  output reg [ADDR_WIDTH - 1:0] addr_in,
  output [ADDR_WIDTH - 1:0] addr_out,
  output dram_en_wr,
  output dram_en_rd,
  output wire done
);

/* local parameters */
localparam  IDX_IDLE     = 0,
            IDX_LD_IFMAP = 1,
            IDX_MAC_PS1  = 2,    // multiply and accumulate, phase 1
            IDX_BIAS_PS1 = 3,   // bias and relu, phase 1
            IDX_MAC_PS2  = 4,    // multiply and accumulate, phase 2
            IDX_BIAS_PS2 = 5,   // bias and relu, phase 2
            IDX_DONE     = 6;

localparam  ST_IDLE     = 7'b0000001,
            ST_LD_IFMAP = 7'b0000010,
            ST_MAC_PS1  = 7'b0000100, // multiply and accumulate, phase 1
            ST_BIAS_PS1 = 7'b0001000, // bias and relu, phase 1
            ST_MAC_PS2  = 7'b0010000, // multiply and accumulate, phase 2
            ST_BIAS_PS2 = 7'b0100000, // bias and relu, phase 2
            ST_DONE     = 7'b1000000;

localparam  WT_BASE_PS1 = 18'd0,
            BS_BASE_PS1 = 18'd48000,
            WT_BASE_PS2 = 18'd50000,
            BS_BASE_PS2 = 18'd51200,
            IFMAP_BASE  = 18'd65536,
            OFMAP_BASE  = 18'd131072;

localparam  NUM_KNLS_PS1 = 120,
            WIDTH_PS1    = 5,
            HEIGHT_PS1   = 5,
            AREA_PS1     = 25,
            DEPTH_PS1    = 16,
            SIZE_PS1     = 400,

            NUM_KNLS_PS2 = 10,
            WIDTH_PS2    = 1,
            HEIGHT_PS2   = 1,
            AREA_PS2     = 1,
            DEPTH_PS2    = 120,
            SIZE_PS2     = 120;

localparam  IDX_NUM_KNLS_PS1_LAST = 7'd119,
            IDX_WIDTH_PS1_LAST    = 3'd4,
            IDX_HEIGHT_PS1_LAST   = 3'd4,
            IDX_DEPTH_PS1_LAST    = 4'd15,
            IDX_SIZE_PS1_LAST     = 9'd399,
            IDX_NUM_KNLS_PS2_LAST = 4'd9,
            IDX_SIZE_PS2_LAST     = 7'd119;

/* global regs and integers */
reg [6:0] state, state_nx;
integer i;

/* regs and wires for storing output feature map */
reg signed [DATA_WIDTH-1:0] ofmap_tmp[0:NUM_KNLS_PS1-1];

/* regs and wires for loading input feature map */
reg signed [DATA_WIDTH-1:0] ifmap[0:SIZE_PS1-1];
reg [2:0] cnt_ifmap_x, cnt_ifmap_x_nx;
reg [2:0] cnt_ifmap_y, cnt_ifmap_y_nx;
reg [3:0] cnt_ifmap_z, cnt_ifmap_z_nx;
wire ifmap_x_last, ifmap_y_last, ifmap_z_last;
wire ifmap_last;
reg en_ld_ifmap;

/* regs and wires for loading weights */
reg signed [DATA_WIDTH-1:0] wt1;
reg signed [DATA_WIDTH-1:0] wt2;
reg [8:0] cnt_wt1, cnt_wt1_nx;
reg [8:0] cnt_wt2, cnt_wt2_nx;
reg [8:0] cnt_wt1_ff[0:1];
reg [8:0] cnt_wt2_ff[0:1];
wire wt1_last, wt2_last;
reg en_ld_wt1, en_ld_wt2;
reg valid_prod1, valid_prod2;

/* regs and wires for loading biases */
reg [DATA_WIDTH-1:0] bs1;
reg [DATA_WIDTH-1:0] bs2;
reg [6:0] cnt_bs1, cnt_bs1_nx;
reg [3:0] cnt_bs2, cnt_bs2_nx;
reg [6:0] cnt_bs1_ff[0:1];
reg [3:0] cnt_bs2_ff[0:1];
wire bs1_last, bs2_last;
reg en_ld_bs1, en_ld_bs2;
reg valid_bs1, valid_bs2;

/* regs to store products and macs */
reg signed [DATA_WIDTH-1:0] prod1, prod1_roff;
reg signed [DATA_WIDTH-1:0] prod2, prod2_roff;
reg signed [DATA_WIDTH-1:0] mac1, mac1_nx;
wire signed [DATA_WIDTH-1:0] mac1_bs, mac1_relu;
reg signed [DATA_WIDTH-1:0] mac2, mac2_nx;
wire signed [DATA_WIDTH-1:0] mac2_bs, mac2_relu;
reg [DATA_WIDTH-1:0] ofmap_tmp_head;

/* event flags */
assign ifmap_x_last = (cnt_ifmap_x == IDX_WIDTH_PS1_LAST);
assign ifmap_y_last = (cnt_ifmap_y == IDX_HEIGHT_PS1_LAST);
assign ifmap_z_last = (cnt_ifmap_z == IDX_DEPTH_PS1_LAST);
assign ifmap_last = (ifmap_x_last & ifmap_y_last & ifmap_z_last);
assign wt1_last = (cnt_wt1 == IDX_SIZE_PS1_LAST);
assign bs1_last = (cnt_bs1 == IDX_NUM_KNLS_PS1_LAST);
assign wt2_last = (cnt_wt2 == IDX_SIZE_PS2_LAST);
assign bs2_last = (cnt_bs2 == IDX_NUM_KNLS_PS2_LAST);


always @(posedge clk) begin
  if (~srstn) state <= ST_IDLE;
  else        state <= state_nx;
end

always@(*) begin // finite state machine
  case (state)
    ST_IDLE:      state_nx = (enable) ? ST_LD_IFMAP : ST_IDLE;
    ST_LD_IFMAP:  state_nx = (ifmap_last) ? ST_MAC_PS1 : ST_LD_IFMAP;
    ST_MAC_PS1:   state_nx = (wt1_last) ? ST_BIAS_PS1 : ST_MAC_PS1;
    ST_BIAS_PS1:  state_nx = (bs1_last) ? ST_MAC_PS2 : ST_MAC_PS1;
    ST_MAC_PS2:   state_nx = (wt2_last) ? ST_BIAS_PS2 : ST_MAC_PS2; 
    ST_BIAS_PS2:  state_nx = (bs2_last) ? ST_DONE : ST_MAC_PS2;
    ST_DONE:      state_nx = ST_IDLE;
    default:      state_nx = ST_IDLE;
  endcase
end

assign done = state[IDX_DONE]; // output logic: done signal

wire [17:0] cnt_bs1_prod_addr, cnt_bs2_prod_addr;

assign cnt_bs1_prod_addr = cnt_bs1 * 9'd400;
assign cnt_bs2_prod_addr = cnt_bs2 * 7'd120;
always@(*) begin // output logic: input memory address translator
  case ({state[IDX_LD_IFMAP], state[IDX_MAC_PS1], state[IDX_BIAS_PS1], state[IDX_MAC_PS2], state[IDX_BIAS_PS2]}) // synopsys parallel_case
    5'b10000: addr_in = IFMAP_BASE + {4'd0, cnt_ifmap_z, {2'd0, cnt_ifmap_y}, {2'd0, cnt_ifmap_x}};
    5'b01000: addr_in = WT_BASE_PS1 + {9'd0, cnt_wt1} + cnt_bs1_prod_addr;
    5'b00100: addr_in = BS_BASE_PS1 + {11'd0, cnt_bs1};
    5'b00010: addr_in = WT_BASE_PS2 + {9'd0, cnt_wt2} + cnt_bs2_prod_addr;
    5'b00001: addr_in = BS_BASE_PS2 + {14'd0, cnt_bs2};
    default:  addr_in = 0;
  endcase
end

/* output memory address translator */
assign addr_out = OFMAP_BASE + {14'd0, cnt_bs2_ff[1]};

assign dram_en_rd = ~state[IDX_IDLE];
assign dram_en_wr = valid_bs2;

/* input feature map register file */
always@(posedge clk) begin
  if (en_ld_ifmap) begin
    ifmap[SIZE_PS1 - 1] <= data_in;
    for (i = 0; i < SIZE_PS1 - 1; i = i+1)
      ifmap[i] <= ifmap[i+1];
  end
  else if (valid_prod1) begin
    ifmap[SIZE_PS1 - 1] <= ifmap[0];
    for (i = 0; i < SIZE_PS1 - 1; i = i+1)
      ifmap[i] <= ifmap[i+1];
  end
end

/* register file to store feature map after phase 1 */
always @(posedge clk) begin
  /* only reset the first flip flop */
  if (~srstn)
    ofmap_tmp[NUM_KNLS_PS1 - 1] <= 0;
  else if (valid_bs1 | valid_prod2) 
    ofmap_tmp[NUM_KNLS_PS1 - 1] <= ofmap_tmp_head;
end
always @(posedge clk) begin
  if (valid_bs1 | valid_prod2) begin
    for (i = 0; i < NUM_KNLS_PS1 - 1; i = i+1)
      ofmap_tmp[i] <= ofmap_tmp[i+1];
  end
end
always@(*) begin
  case ({valid_bs1, valid_prod2})
    2'b01:
      ofmap_tmp_head = ofmap_tmp[0];
    2'b10:
      ofmap_tmp_head = mac1_relu;
    default:
      ofmap_tmp_head = 0;
  endcase
end

/* weight and biase flip flops */
always @(posedge clk) begin
  if (~srstn) wt1 <= 0;
  else if (en_ld_wt1) wt1 <= data_in;
end

always @(posedge clk) begin
  if (~srstn) wt2 <= 0;
  else if (en_ld_wt2) wt2 <= data_in;
end

always @(posedge clk) begin
  if (~srstn) bs1 <= 0;
  else if (en_ld_bs1) bs1 <= data_in;
end

always @(posedge clk) begin
  if (~srstn) bs2 <= 0;
  else if (en_ld_bs2) bs2 <= data_in;
end

/* write the result back to dram */
assign data_out = mac2_relu;

/* enable signals */
always@(posedge clk) begin
  if (~srstn) begin
    en_ld_ifmap <= 0;
    en_ld_wt1 <= 0;
    en_ld_wt2 <= 0;
    en_ld_bs1 <= 0;
    en_ld_bs2 <= 0;
  end
  else begin
    en_ld_ifmap <= state[IDX_LD_IFMAP];
    en_ld_wt1 <= state[IDX_MAC_PS1];
    en_ld_wt2 <= state[IDX_MAC_PS2];
    en_ld_bs1 <= state[IDX_BIAS_PS1];
    en_ld_bs2 <= state[IDX_BIAS_PS2];
  end
end

/* valid signals */
always@(posedge clk) begin
  if (~srstn) begin
    valid_prod1 <= 0;
    valid_prod2 <= 0;
    valid_bs1 <= 0;
    valid_bs2 <= 0;
  end
  else begin
    valid_prod1 <= en_ld_wt1;
    valid_prod2 <= en_ld_wt2;
    valid_bs1 <= en_ld_bs1;
    valid_bs2 <= en_ld_bs2;
  end
end

/* delayed signals */
always@(posedge clk) begin
  if (~srstn) begin
    cnt_wt1_ff[0] <= 0;
    cnt_wt1_ff[1] <= 0;
    cnt_wt2_ff[0] <= 0;
    cnt_wt2_ff[1] <= 0;
    cnt_bs1_ff[0] <= 0;
    cnt_bs1_ff[1] <= 0;
    cnt_bs2_ff[0] <= 0;
    cnt_bs2_ff[1] <= 0;
  end
  else begin
    cnt_wt1_ff[0] <= cnt_wt1;
    cnt_wt1_ff[1] <= cnt_wt1_ff[0];
    cnt_wt2_ff[0] <= cnt_wt2;
    cnt_wt2_ff[1] <= cnt_wt2_ff[0];
    cnt_bs1_ff[0] <= cnt_bs1;
    cnt_bs1_ff[1] <= cnt_bs1_ff[0];
    cnt_bs2_ff[0] <= cnt_bs2;
    cnt_bs2_ff[1] <= cnt_bs2_ff[0];
  end
end

/* multiply */
always@(*) begin
  prod1 = wt1 * ifmap[0];
  prod1_roff = prod1 >>> 16;
  prod2 = wt2 * ofmap_tmp[0];
  prod2_roff = prod2 >>> 16;
end

/* accumulate */
always @(posedge clk) begin
  if (~srstn) begin
    mac1 <= 0;
    mac2 <= 0;
  end
  else begin
    mac1 <= mac1_nx;
    mac2 <= mac2_nx;
  end
end

assign mac1_bs = mac1 + bs1;
assign mac1_relu = (mac1_bs[DATA_WIDTH-1]) ? 0 : mac1_bs;
always @(*) begin
  case ({valid_bs1, valid_prod1})
    2'b00:    mac1_nx = mac1;
    2'b01:    mac1_nx = mac1 + prod1_roff;
    default:  mac1_nx = 0;
  endcase
end

assign mac2_bs = mac2 + bs2;
assign mac2_relu = (mac2_bs[DATA_WIDTH-1]) ? 0 : mac2_bs;
always @(*) begin
  case ({valid_bs2, valid_prod2})
    2'b00:    mac2_nx = mac2;
    2'b01:    mac2_nx = mac2 + prod2_roff;
    default:  mac2_nx = 0;
  endcase
end

always @(posedge clk) begin
  if (~srstn) begin
    cnt_ifmap_x <= 0;
    cnt_ifmap_y <= 0;
    cnt_ifmap_z <= 0;
  end
  else begin
    cnt_ifmap_x <= cnt_ifmap_x_nx;
    cnt_ifmap_y <= cnt_ifmap_y_nx;
    cnt_ifmap_z <= cnt_ifmap_z_nx;
  end
end

always @(*) begin // counter to record the x-axis of currently loading ifmap
  case ({state[IDX_LD_IFMAP], ifmap_x_last}) // synopsys parallel_case
    2'b10   : cnt_ifmap_x_nx = cnt_ifmap_x + 1;
    2'b11   : cnt_ifmap_x_nx = 0;
    default : cnt_ifmap_x_nx = cnt_ifmap_x;
  endcase
end

always @(*) begin // counter to record the y-axis of currently loading ifmap
  case ({state[IDX_LD_IFMAP], ifmap_x_last, ifmap_y_last}) // synopsys parallel_case
    3'b100   : cnt_ifmap_y_nx = cnt_ifmap_y;
    3'b101   : cnt_ifmap_y_nx = cnt_ifmap_y;
    3'b110   : cnt_ifmap_y_nx = cnt_ifmap_y + 1;
    default : cnt_ifmap_y_nx = 0;
  endcase
end

always @(*) begin // counter to record the z-axis of currently loading ifmap
  case ({state[IDX_LD_IFMAP], ifmap_x_last, ifmap_y_last}) // synopsys parallel_case
    3'b100   : cnt_ifmap_z_nx = cnt_ifmap_z;
    3'b101   : cnt_ifmap_z_nx = cnt_ifmap_z;
    3'b110   : cnt_ifmap_z_nx = cnt_ifmap_z;
    3'b111   : cnt_ifmap_z_nx = cnt_ifmap_z + 4'd1;
    default : cnt_ifmap_z_nx = 0;
  endcase
end

always@(posedge clk) begin
  if (~srstn) begin
    cnt_wt1 <= 0;
    cnt_bs1 <= 0;
    cnt_wt2 <= 0;
    cnt_bs2 <= 0;
  end
  else begin
    cnt_wt1 <= cnt_wt1_nx;
    cnt_bs1 <= cnt_bs1_nx;
    cnt_wt2 <= cnt_wt2_nx;
    cnt_bs2 <= cnt_bs2_nx;
  end
end

always @(*) begin // counter to record how many weights have been loaded in phase 1
  case ({state[IDX_MAC_PS1], wt1_last}) // synopsys parallel_case
    2'b10   : cnt_wt1_nx = cnt_wt1 + 1;
    2'b11   : cnt_wt1_nx = 0;
    default : cnt_wt1_nx = cnt_wt1;
  endcase
end

always @(*) begin // counter to record how many biases have been loaded in phase 1
  case ({state[IDX_BIAS_PS1], bs1_last}) // synopsys parallel_case
    2'b10   : cnt_bs1_nx = cnt_bs1 + 1;
    2'b11   : cnt_bs1_nx = 0;
    default : cnt_bs1_nx = cnt_bs1;
  endcase
end

always @(*) begin // counter to record how many weights have been loaded in phase 2
  case ({state[IDX_MAC_PS2], wt2_last}) // synopsys parallel_case
    2'b10   : cnt_wt2_nx = cnt_wt2 + 1;
    2'b11   : cnt_wt2_nx = 0;
    default : cnt_wt2_nx = cnt_wt2;
  endcase
end

always @(*) begin // counter to record how many biases have been loaded in phase 2
  case ({state[IDX_BIAS_PS2], bs2_last}) // synopsys parallel_case
    2'b10   : cnt_bs2_nx = cnt_bs2 + 1;
    2'b11   : cnt_bs2_nx = 0;
    default : cnt_bs2_nx = cnt_bs2;
  endcase
end

endmodule
