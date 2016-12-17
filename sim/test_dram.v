/**
 * test_dram.v
 */

module test_dram;

parameter CYCLE = 10;
parameter END_CYCLE = 300;
parameter DATA_WIDTH = 32;
parameter ADDR_WIDTH = 18;

reg clk;
reg srstn;
reg en_conv;
wire dram_en_wr, dram_en_rd;
wire [ADDR_WIDTH - 1:0] dram_addr_wr, dram_addr_rd;
wire [DATA_WIDTH - 1:0] dram_data_wr, dram_data_rd;

/* dram model */
dram dram_0(
  .clk(clk),
  .srstn(srstn),
  .en_wr(dram_en_wr),
  .addr_wr(dram_addr_wr),
  .data_in(dram_data_wr),
  .en_rd(dram_en_rd),
  .addr_rd(dram_addr_rd),
  .valid(valid),
  .data_out(dram_data_rd)
);

/* convolutional layer */
conv_layer conv_layer(
  .clk(clk),
  .srstn(srstn),
  .enable(en_conv),
  .data_in(dram_data_rd),
  .data_out(dram_data_wr),
  .addr_in(dram_addr_rd),
  .addr_out(dram_addr_wr),
  .dram_en_wr(dram_en_wr),
  .dram_en_rd(dram_en_rd)
);

always #(CYCLE / 2) clk = ~clk;

/* test pattern feeder */
initial begin
  clk = 0;
  srstn = 1;
  en_conv = 0;
  @(negedge clk);
  srstn = 0;
  @(negedge clk);
  srstn = 1;
  @(negedge clk);
  dram_0.data2dram;
  $display("%d ns: Read input data finish", $time);
  /* one pulse enable */
  @(negedge clk);
  en_conv = 1;
  @(negedge clk);
  en_conv = 0;
end

/* result checker */
initial begin
end

/* watch dog */
initial begin
  #(CYCLE * END_CYCLE);
  $display("%d ns: End cycle reached", $time);
  $finish;
end

/* fsdb */
initial begin
  $fsdbDumpfile("test_dram.fsdb");
  $fsdbDumpvars(0, test_dram, "+mda");
end

endmodule
