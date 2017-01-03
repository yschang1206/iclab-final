// Wrap the synthesized netlist 

module CHIP
(
  input clk,
  input srstn,
  input enable,
  input dram_valid,
  input rdy_data,
  input [31:0] data_in,
  output reg [31:0] data_out,
  output reg [17:0] addr_in,
  output reg [17:0] addr_out,
  output reg dram_en_wr,
  output reg dram_en_rd,
  output done,
  output reg done_one_layer
);

  lenet U0(
    .clk(clk),
    .srstn(srstn),
    .enable(enable),
    .dram_valid(dram_valid),
    .rdy_data(rdy_data),
    .data_in(dram_data_rd),
    .data_out(dram_data_wr),
    .addr_in(dram_addr_rd),
    .addr_out(dram_addr_wr),
    .dram_en_wr(dram_en_wr),
    .dram_en_rd(dram_en_rd),
    .done(done),
    .done_one_layer(done_one_layer)
  );
  
endmodule
