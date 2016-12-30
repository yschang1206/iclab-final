/**
 * conv.v
 */

module conv
#
(
  parameter DATA_WIDTH = 32,
  parameter ADDR_WIDTH = 18,
  parameter KNL_WIDTH = 5'd5,
  parameter KNL_HEIGHT = 5'd5,
  parameter KNL_SIZE = 25,  // unit: 32 bits
  parameter KNL_MAXNUM = 16
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

wire en_ld_knl;
wire en_ld_ifmap;
wire disable_acc;
wire [4:0] num_knls;
wire [4:0] cnt_ofmap_chnl;
wire [5:0] param_in;
assign param_in = data_in[5:0];

conv_ctrl conv_ctrl
(
  // I/O for top module
  .clk(clk),
  .srstn(srstn),
  .enable(enable),
  .param_in(param_in),
  .addr_in(addr_in),
  .addr_out(addr_out),
  .dram_en_wr(dram_en_wr),
  .dram_en_rd(dram_en_rd),
  .done(done),

  // I/O for conv
  .en_ld_knl(en_ld_knl),
  .en_ld_ifmap(en_ld_ifmap),
  .disable_acc(disable_acc),
  .num_knls(num_knls),
  .cnt_ofmap_chnl(cnt_ofmap_chnl)
);

pe pe
(
  .clk(clk),
  .srstn(srstn),
  .data_in(data_in),
  .data_out(data_out),

  // I/O for controller
  .en_ld_knl(en_ld_knl),
  .en_ld_ifmap(en_ld_ifmap),
  .disable_acc(disable_acc),
  .num_knls(num_knls),
  .cnt_ofmap_chnl(cnt_ofmap_chnl)
);

endmodule
