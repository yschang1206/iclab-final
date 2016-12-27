/**
 * test_dram.v
 */

module test_dram;

parameter CYCLE = 10;
parameter END_CYCLE = 40000000;
parameter DATA_WIDTH = 32;
parameter ADDR_WIDTH = 18;

reg clk;
reg srstn;
reg enable;
wire dram_en_wr, dram_en_rd;
wire dram_valid;
wire done;
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
  .valid(dram_valid),
  .data_out(dram_data_rd)
);

lenet lenet(
  .clk(clk),
  .srstn(srstn),
  .enable(enable),
  .dram_valid(dram_valid),
  .data_in(dram_data_rd),
  .data_out(dram_data_wr),
  .addr_in(dram_addr_rd),
  .addr_out(dram_addr_wr),
  .dram_en_wr(dram_en_wr),
  .dram_en_rd(dram_en_rd),
  .done(done)
);

always #(CYCLE / 2) clk = ~clk;

/* test pattern feeder */
initial begin
  clk = 0;
  srstn = 1;
  enable = 0;
  @(negedge clk);
  srstn = 0;
  @(negedge clk);
  srstn = 1;
  @(negedge clk);
  dram_0.data2dram;
  $display("%d ns: Read input data finish", $time);
  /* one pulse enable */
  @(negedge clk);
  enable = 1;
  @(negedge clk);
  enable = 0;
end

/* result checker */
initial begin
  wait(srstn == 0);
  wait(srstn == 1);
  wait(done == 1);
  //dram_0.print_result(131072, 10, 10, 16);
  dram_0.print_result(65536, 5, 5, 16);
  #(CYCLE);
  $finish;
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
