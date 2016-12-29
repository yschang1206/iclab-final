/**
 * conv.v
 */

module conv
#
(/**
 * conv.v
 */

module conv
#
(
  parameter DATA_WIDTH = 32,
  parameter ADDR_WIDTH = 18,
  parameter KNL_WIDTH = 5'd5,
  parameter KNL_HEIGHT = 5'd5,
  parameter KNL_SIZE = 5'd25,  // unit: 32 bits
  parameter KNL_MAXNUM = 5'd16
)
(
  input clk,
  input srstn,
  input enable,
  input dram_valid,
  input [DATA_WIDTH - 1:0] data_in,
  output [DATA_WIDTH - 1:0] data_out,
  output [ADDR_WIDTH - 1:0] addr_in,
  output [ADDR_WIDTH - 1:0] addr_out,
  output dram_en_wr,
  output dram_en_rd,
  output done
);

/* local parameters */

/* global wires, registers and integers */
integer i, j;

/* enable for some states */
wire en_ld_knl;
wire en_ld_ifmap;
wire disable_acc;

/* registers for parameters */
wire [5:0] num_knls;

/* wires and registers for kernels */
reg [DATA_WIDTH - 1:0] knls[0:400 - 1];

/* wires and registers for input feature map */
reg [DATA_WIDTH - 1:0] ifmap[0:KNL_SIZE - 1];

/* wires and registers for output feature map */
wire [DATA_WIDTH - 1:0] mac;

wire [4:0] cnt_ofmap_chnl_ff;
reg signed [DATA_WIDTH - 1:0] prod [0:KNL_SIZE - 1];
reg signed [DATA_WIDTH - 1:0] prod_roff[0:KNL_SIZE - 1];


reg [8:0] addr_knl_prod_nx [0:24];
reg [8:0] addr_knl_prod [0:24];
wire [8:0] addr_knl_tmp;
assign addr_knl_tmp = (5'd16 - num_knls[4:0] + cnt_ofmap_chnl_ff) * 5'd25;
                  //  (KNL_MAXNUM - num_knls[4:0] + {1'b0, cnt_ofmap_chnl_ff[3:0]}) * KNL_SIZE
always@(*) begin
  addr_knl_prod_nx[0] = addr_knl_tmp + 9'd0;
  addr_knl_prod_nx[1] = addr_knl_tmp + 9'd1;
  addr_knl_prod_nx[2] = addr_knl_tmp + 9'd2;
  addr_knl_prod_nx[3] = addr_knl_tmp + 9'd3;
  addr_knl_prod_nx[4] = addr_knl_tmp + 9'd4;
  addr_knl_prod_nx[5] = addr_knl_tmp + 9'd5;
  addr_knl_prod_nx[6] = addr_knl_tmp + 9'd6;
  addr_knl_prod_nx[7] = addr_knl_tmp + 9'd7;
  addr_knl_prod_nx[8] = addr_knl_tmp + 9'd8;
  addr_knl_prod_nx[9] = addr_knl_tmp + 9'd9;
  addr_knl_prod_nx[10] = addr_knl_tmp + 9'd10;
  addr_knl_prod_nx[11] = addr_knl_tmp + 9'd11;
  addr_knl_prod_nx[12] = addr_knl_tmp + 9'd12;
  addr_knl_prod_nx[13] = addr_knl_tmp + 9'd13;
  addr_knl_prod_nx[14] = addr_knl_tmp + 9'd14;
  addr_knl_prod_nx[15] = addr_knl_tmp + 9'd15;
  addr_knl_prod_nx[16] = addr_knl_tmp + 9'd16;
  addr_knl_prod_nx[17] = addr_knl_tmp + 9'd17;
  addr_knl_prod_nx[18] = addr_knl_tmp + 9'd18;
  addr_knl_prod_nx[19] = addr_knl_tmp + 9'd19;
  addr_knl_prod_nx[20] = addr_knl_tmp + 9'd20;
  addr_knl_prod_nx[21] = addr_knl_tmp + 9'd21;
  addr_knl_prod_nx[22] = addr_knl_tmp + 9'd22;
  addr_knl_prod_nx[23] = addr_knl_tmp + 9'd23;
  addr_knl_prod_nx[24] = addr_knl_tmp + 9'd24;
end

/* convolution process */
assign data_out = (disable_acc) ? mac : data_in + mac;

always@(*) begin
  for (i = 0; i < 5; i = i+1) begin
    for (j = 0; j < 5; j = j+1) begin
      prod[i*5 + j] = knls[addr_knl_prod_nx[i*5 + j]] * ifmap[j*5 + i];
      prod_roff[i*5 + j] = prod[i*5 + j] >>> 16;
    end
  end
end

assign mac =  prod_roff[0] + prod_roff[1] + prod_roff[2] + prod_roff[3] + prod_roff[4] +
              prod_roff[5] + prod_roff[6] + prod_roff[7] + prod_roff[8] + prod_roff[9] + 
              prod_roff[10] + prod_roff[11] + prod_roff[12] + prod_roff[13] + prod_roff[14] +
              prod_roff[15] + prod_roff[16] + prod_roff[17] + prod_roff[18] + prod_roff[19] +
              prod_roff[20] + prod_roff[21] + prod_roff[22] + prod_roff[23] + prod_roff[24];


/* weight register file */
always @(posedge clk) begin
  if (en_ld_knl) begin
    knls[KNL_MAXNUM*KNL_SIZE - 1] <= data_in;
    for (i = 0; i < KNL_MAXNUM*KNL_SIZE - 1; i = i+1)
      knls[i] <= knls[i+1];
  end
end

/* input feature map register file */
always @(posedge clk) begin
  if (en_ld_ifmap) begin
    ifmap[KNL_SIZE - 1] <= data_in;
    for (i = 0; i < KNL_SIZE-1; i = i+1)
      ifmap[i] <= ifmap[i+1];
  end
end

endmodule

  parameter DATA_WIDTH = 32,
  parameter ADDR_WIDTH = 18,
  parameter KNL_WIDTH = 5'd5,
  parameter KNL_HEIGHT = 5'd5,
  parameter KNL_SIZE = 5'd25,  // unit: 32 bits
  parameter KNL_MAXNUM = 5'd16
)
(
  input clk,
  input srstn,
  input enable,
  input dram_valid,
  input [DATA_WIDTH - 1:0] data_in,
  output [DATA_WIDTH - 1:0] data_out,
  output [ADDR_WIDTH - 1:0] addr_in,
  output [ADDR_WIDTH - 1:0] addr_out,
  output dram_en_wr,
  output dram_en_rd,
  output done
);

/* local parameters */

/* global wires, registers and integers */
integer i, j;

/* Enable for some states */
wire en_ld_knl;
wire en_ld_ifmap;

/* registers for parameters */
wire [5:0] num_knls;

/* wires and registers for kernels */
reg [DATA_WIDTH - 1:0] knls[0:400 - 1];

/* wires and registers for input feature map */
reg [DATA_WIDTH - 1:0] ifmap[0:KNL_SIZE - 1];

/* wires and registers for output feature map */
reg [DATA_WIDTH - 1:0] mac;
wire [4:0] cnt_ofmap_chnl_ff;
reg [DATA_WIDTH - 1:0] products[0:KNL_SIZE - 1];
reg [DATA_WIDTH - 1:0] products_roff[0:KNL_SIZE - 1];

conv_ctrl conv_ctrl
(
  // I/O for top module
  .clk(clk),
  .srstn(srstn),
  .enable(enable),
  .data_in(data_in),
  .addr_in(addr_in),
  .addr_out(addr_out),
  .dram_en_wr(dram_en_wr),
  .dram_en_rd(dram_en_rd),
  .done(done),

  // I/O for conv
  .en_ld_knl(en_ld_knl),
  .en_ld_ifmap(en_ld_ifmap),
  .num_knls(num_knls),
  .cnt_ofmap_chnl_ff(cnt_ofmap_chnl_ff)
);

/* convolution process */
assign data_out = data_in + mac;


reg [8:0] addr_knl_prod [0:24];
wire [4:0] addr_knl_tmp;
assign addr_knl_tmp = KNL_MAXNUM - num_knls[4:0] + {1'b0, cnt_ofmap_chnl_ff[3:0]};
always@(*) begin
  for (i = 0; i < KNL_HEIGHT; i = i+1) begin
    for (j = 0; j < KNL_WIDTH; j = j+1) begin
      addr_knl_prod[i*KNL_WIDTH + j] = addr_knl_tmp*KNL_SIZE + i*KNL_WIDTH + j;
    end
  end
end

always@(*) begin
  for (i = 0; i < KNL_HEIGHT; i = i+1) begin
    for (j = 0; j < KNL_WIDTH; j = j+1) begin
      products[i*KNL_WIDTH + j] = knls[addr_knl_prod[i*KNL_WIDTH + j]] * ifmap[j*KNL_HEIGHT + i];
      products_roff[i*KNL_WIDTH + j] = {{16{products[i*KNL_WIDTH + j][DATA_WIDTH - 1]}}, products[i*KNL_WIDTH + j][DATA_WIDTH - 1:16]} + {31'd0, products[i*KNL_WIDTH + j][DATA_WIDTH - 1]};
    end
  end
end

always@(*) begin
  mac = 0;
  for (i = 0; i < KNL_HEIGHT; i = i+1)
    for (j = 0; j < KNL_WIDTH; j = j+1)
      mac = mac + products_roff[i * KNL_WIDTH + j];
end

/* weight register file */
always @(posedge clk) begin
  if (en_ld_knl) begin
    knls[KNL_MAXNUM*KNL_SIZE - 1] <= data_in;
    for (i = 0; i < KNL_MAXNUM*KNL_SIZE - 1; i = i+1)
      knls[i] <= knls[i+1];
  end
end

/* input feature map register file */
always @(posedge clk) begin
  if (en_ld_ifmap) begin
    ifmap[KNL_SIZE - 1] <= data_in;
    for (i = 0; i < KNL_SIZE-1; i = i+1)
      ifmap[i] <= ifmap[i+1];
  end
end

endmodule
