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
localparam  ST_IDLE = 3'd0,
            ST_LD_IFMAP = 3'd1,
            ST_MAC_PS1 = 3'd2,    // multiply and accumulate, phase 1
            ST_BIAS_PS1 = 3'd3,   // bias and relu, phase 1
            ST_MAC_PS2 = 3'd4,    // multiply and accumulate, phase 2
            ST_BIAS_PS2 = 3'd5,   // bias and relu, phase 2
            ST_DONE = 3'd7;

localparam  WT_BASE_PS1 = 18'd0,
            BS_BASE_PS1 = 18'd48000,
            WT_BASE_PS2 = 18'd50000,
            BS_BASE_PS2 = 18'd51200,
            IFMAP_BASE = 18'd65536,
            OFMAP_BASE = 18'd131072;

localparam  NUM_KNLS_PS1 = 120,
            WIDTH_PS1 = 5,
            HEIGHT_PS1 = 5,
            AREA_PS1 = 25,
            DEPTH_PS1 = 16,
            SIZE_PS1 = 400,
            NUM_KNLS_PS2 = 10,
            WIDTH_PS2 = 1,
            HEIGHT_PS2 = 1,
            AREA_PS2 = 1,
            DEPTH_PS2 = 120,
            SIZE_PS2 = 120;
            
/* global regs and integers */
reg [2:0] state, state_nx;
integer i;

/* regs and wires for storing output feature map */
reg signed [DATA_WIDTH-1:0] ofmap_tmp[0:NUM_KNLS_PS1-1];

/* regs and wires for loading input feature map */
reg signed [DATA_WIDTH-1:0] ifmap[0:SIZE_PS1-1];
reg [2:0] cnt_ifmap_x, cnt_ifmap_x_nx;
reg [2:0] cnt_ifmap_y, cnt_ifmap_y_nx;
reg [4:0] cnt_ifmap_z, cnt_ifmap_z_nx;
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

/* event flags */
assign ifmap_x_last = (cnt_ifmap_x == WIDTH_PS1 - 1);
assign ifmap_y_last = (cnt_ifmap_y == HEIGHT_PS1 - 1);
assign ifmap_z_last = (cnt_ifmap_z == DEPTH_PS1 - 1);
assign ifmap_last = (ifmap_x_last & ifmap_y_last & ifmap_z_last);
assign wt1_last = (cnt_wt1 == SIZE_PS1 - 1);
assign bs1_last = (cnt_bs1 == NUM_KNLS_PS1 - 1);
assign wt2_last = (cnt_wt2 == SIZE_PS2 - 1);
assign bs2_last = (cnt_bs2 == NUM_KNLS_PS2 - 1);

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

/* output logic: done signal */
assign done = (state == ST_DONE);

always@(*) begin
  /* output logic: input memory address translator */
  case (state)
    ST_LD_IFMAP: addr_in = IFMAP_BASE + {4'd0, cnt_ifmap_z[3:0],
                           {2'd0, cnt_ifmap_y[2:0]}, {2'd0, cnt_ifmap_x[2:0]}};
    ST_MAC_PS1:  addr_in = WT_BASE_PS1 + {9'd0, cnt_wt1} + cnt_bs1 * 9'd400;
    ST_BIAS_PS1: addr_in = BS_BASE_PS1 + {11'd0, cnt_bs1};
    ST_MAC_PS2:  addr_in = WT_BASE_PS2 + {9'd0, cnt_wt2} + cnt_bs2 * 7'd120;
    ST_BIAS_PS2: addr_in = BS_BASE_PS2 + {14'd0, cnt_bs2};
    default:     addr_in = 0;
  endcase
end

/* output memory address translator */
assign addr_out = OFMAP_BASE + {14'd0, cnt_bs2_ff[1]};

/*
always@(*) begin
  case (state)
    ST_LD_IFMAP: begin
      dram_en_rd = 1;
      dram_en_wr = 0;
    end
    ST_MAC_PS1: begin
      dram_en_rd = 1;
      dram_en_wr = 0;
    end
    ST_BIAS_PS1: begin
      dram_en_rd = 1;
      dram_en_wr = 0;
    end
    ST_MAC_PS2: begin
      dram_en_rd = 1;
      dram_en_wr = 0;
    end
    ST_BIAS_PS2: begin
      dram_en_rd = 1;
      dram_en_wr = valid_bs2;
    end
    default: begin
      dram_en_rd = 0;
      dram_en_wr = 0;
    end
  endcase
end
*/

assign dram_en_rd = (state == ST_IDLE) ? 0 : 1;
assign dram_en_wr = valid_bs2;

/* weights register file */
always@(posedge clk) begin
  if (~srstn)
    for (i = 0; i < SIZE_PS1; i = i + 1)
      ifmap[i] <= 0;
  else if (en_ld_ifmap) begin
    ifmap[SIZE_PS1 - 1] <= data_in;
    for (i = 0; i < SIZE_PS1 - 1; i = i + 1)
      ifmap[i] <= ifmap[i + 1];
  end
end

/* register file to store feature map after phase 1 */
always@(posedge clk) begin
  if (~srstn)
    for (i = 0; i < NUM_KNLS_PS1; i = i + 1)
      ofmap_tmp[i] <= 0;
  else if (valid_bs1)
    for (i = 0; i < NUM_KNLS_PS1; i = i + 1)
      if (cnt_bs1_ff[1] == i)
        ofmap_tmp[i] <= mac1_relu;
end

always@(posedge clk) begin
  if (~srstn) wt1 <= 0;
  else if (en_ld_wt1) wt1 <= data_in;
end

always@(posedge clk) begin
  if (~srstn) wt2 <= 0;
  else if (en_ld_wt2) wt2 <= data_in;
end

always@(posedge clk) begin
  if (~srstn) bs1 <= 0;
  else if (en_ld_bs1) bs1 <= data_in;
end

always@(posedge clk) begin
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
    en_ld_ifmap <= (state == ST_LD_IFMAP);
    en_ld_wt1 <= (state == ST_MAC_PS1);
    en_ld_wt2 <= (state == ST_MAC_PS2);
    en_ld_bs1 <= (state == ST_BIAS_PS1);
    en_ld_bs2 <= (state == ST_BIAS_PS2);
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
  prod1 = wt1 * ifmap[cnt_wt1_ff[1]];
  prod1_roff = prod1 >>> 16;
  prod2 = wt2 * ofmap_tmp[cnt_wt2_ff[1]];
  prod2_roff = prod2 >>> 16;
end

/* accumulate */
always@(posedge clk) begin
  if (~srstn) mac1 <= 0;
  else        mac1 <= mac1_nx;
end

assign mac1_bs = mac1 + bs1;
assign mac1_relu = (mac1_bs[DATA_WIDTH-1]) ? 0 : mac1_bs;
always@(*) begin
  case ({valid_bs1, valid_prod1})
    2'b00:    mac1_nx = mac1;
    2'b01:    mac1_nx = mac1 + prod1_roff;
    2'b10:    mac1_nx = 0;
    default:  mac1_nx = 0;
  endcase
end

always@(posedge clk) begin
  if (~srstn) mac2 <= 0;
  else        mac2 <= mac2_nx;
end

assign mac2_bs = mac2 + bs2;
assign mac2_relu = (mac2_bs[DATA_WIDTH-1]) ? 0 : mac2_bs;
always@(*) begin
  case ({valid_bs2, valid_prod2})
    2'b00:    mac2_nx = mac2;
    2'b01:    mac2_nx = mac2 + prod2_roff;
    2'b10:    mac2_nx = 0;
    default:  mac2_nx = 0;
  endcase
end

/*
always@(*) begin
  case ({valid_bs2, valid_prod2})
    2'b01: begin
      for (i = 0; i < NUM_KNLS_PS2; i = i + 1)
        mac2_nx[i] = mac2[i] + prod2_roff;
    end
    2'b10: begin
      for (i = 0; i < NUM_KNLS_PS2; i = i + 1)
        //mac2_nx[i] = mac2[i] + bs2;
        mac2_nx[i] = pixel2_tmp[i][DATA_WIDTH-1] ? 0 : pixel2_tmp[i];
    end
    default:  begin
      for (i = 0; i < NUM_KNLS_PS2; i = i + 1)
        mac2_nx[i] = 0;
    end
  endcase
end
*/

/* counter to record the x-axis of currently loading ifmap */
always@(posedge clk) begin
  if (~srstn) cnt_ifmap_x <= 0;
  else        cnt_ifmap_x <= cnt_ifmap_x_nx;
end

always@(*) begin
  if (state == ST_LD_IFMAP)
    if (ifmap_x_last)
      cnt_ifmap_x_nx = 0;
    else
      cnt_ifmap_x_nx = cnt_ifmap_x + 1;
  else
    cnt_ifmap_x_nx = 0;
end

/* counter to record the y-axis of currently loading ifmap */
always@(posedge clk) begin
  if (~srstn) cnt_ifmap_y <= 0;
  else        cnt_ifmap_y <= cnt_ifmap_y_nx;
end

always@(*) begin
  if (state == ST_LD_IFMAP)
    if (ifmap_x_last)
      if (ifmap_y_last)
        cnt_ifmap_y_nx = 0;
      else
        cnt_ifmap_y_nx = cnt_ifmap_y + 1;
    else
      cnt_ifmap_y_nx = cnt_ifmap_y;
  else
    cnt_ifmap_y_nx = 0;
end

/* counter to record the z-axis of currently loading ifmap */
always@(posedge clk) begin
  if (~srstn) cnt_ifmap_z <= 0;
  else        cnt_ifmap_z <= cnt_ifmap_z_nx;
end

always@(*) begin
  if (state == ST_LD_IFMAP)
    if (ifmap_x_last & ifmap_y_last)
      cnt_ifmap_z_nx = cnt_ifmap_z + 1;
    else
      cnt_ifmap_z_nx = cnt_ifmap_z;
  else
    cnt_ifmap_z_nx = 0;
end

/* counter to record how many weights have been loaded in phase 1 */
always@(posedge clk) begin
  if (~srstn) cnt_wt1 <= 0;
  else        cnt_wt1 <= cnt_wt1_nx;
end

always@(*) begin
  if (state == ST_MAC_PS1)
    if (wt1_last)
      cnt_wt1_nx = 0;
    else
      cnt_wt1_nx = cnt_wt1 + 1;
  else
    cnt_wt1_nx = 0;
end

/* counter to record how many biases have been loaded in phase 1 */
always@(posedge clk) begin
  if (~srstn) cnt_bs1 <= 0;
  else        cnt_bs1 <= cnt_bs1_nx;
end

always@(*) begin
  if (state == ST_BIAS_PS1)
    if (bs1_last)
      cnt_bs1_nx = 0;
    else
      cnt_bs1_nx = cnt_bs1 + 1;
  else
    cnt_bs1_nx = cnt_bs1;
end

/* counter to record how many weights have been loaded in phase 2 */
always@(posedge clk) begin
  if (~srstn) cnt_wt2 <= 0;
  else        cnt_wt2 <= cnt_wt2_nx;
end

always@(*) begin
  if (state == ST_MAC_PS2)
    if (wt2_last)
      cnt_wt2_nx = 0;
    else
      cnt_wt2_nx = cnt_wt2 + 1;
  else
    cnt_wt2_nx = 0;
end

/* counter to record how many biases have been loaded in phase 2 */
always@(posedge clk) begin
  if (~srstn) cnt_bs2 <= 0;
  else        cnt_bs2 <= cnt_bs2_nx;
end

always@(*) begin
  if (state == ST_BIAS_PS2)
    if (bs2_last)
      cnt_bs2_nx = 0;
    else
      cnt_bs2_nx = cnt_bs2 + 1;
  else
    cnt_bs2_nx = cnt_bs2;
end

endmodule

