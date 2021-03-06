/**
 * test_top.v
 */
`timescale  1ns/10ps
module test_top;

parameter CYCLE = 10;
parameter END_CYCLE = 100000;
parameter DATA_WIDTH = 32;
parameter ADDR_WIDTH = 18;

reg clk;
reg srstn;
reg enable;
wire dram_en_wr, dram_en_rd;
wire dram_valid;
reg rdy_data;
wire done;
wire done_conv, done_relu, done_pool;
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

`ifdef POSTSIM
  CHIP CHIP0(
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
`else
  lenet lenet(
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
`endif

always #(CYCLE / 2) clk = ~clk;

/* test pattern feeder */
initial begin
  clk = 0;
  srstn = 1;
  enable = 0;
  rdy_data = 0;
  @(negedge clk);
  srstn = 0;
  @(negedge clk);
  srstn = 1;
  @(negedge clk);
  dram_0.load_img;
  //dram_0.load_out1;
  $display("%d ns: Finish reading input data", $time);

  /* one pulse enable */
  @(negedge clk);
  enable = 1;
  @(negedge clk);
  enable = 0;
  $display("%d ns: Enabling", $time);
  dram_0.load_l0_pre_data;
  @(negedge clk);
  rdy_data = 1;
  @(negedge clk);
  rdy_data = 0;
  wait(done_one_layer == 1);
  $display("%d ns: Layer 0 (convolution) done", $time);

  dram_0.load_l0_post_data;
  @(negedge clk);
  rdy_data = 1;
  @(negedge clk);
  rdy_data = 0;
  wait(done_one_layer == 1);
  $display("%d ns: Layer 0 (bias/relu) done", $time);

  dram_0.load_l1_data;
  @(negedge clk);
  rdy_data = 1;
  @(negedge clk);
  rdy_data = 0;
  @(negedge clk);
  wait(done_one_layer == 1);
  $display("%d ns: Layer 1 (max pooling) done", $time);

  dram_0.load_l2_pre_data;
  @(negedge clk);
  rdy_data = 1;
  @(negedge clk);
  rdy_data = 0;
  wait(done_one_layer == 1);
  $display("%d ns: Layer 2 (convolution) done", $time);

  dram_0.load_l2_post_data;
  @(negedge clk);
  rdy_data = 1;
  @(negedge clk);
  rdy_data = 0;
  wait(done_one_layer == 1);
  $display("%d ns: Layer 2 (bias/relu) done", $time);

  dram_0.load_l3_data;
  @(negedge clk);
  rdy_data = 1;
  @(negedge clk);
  rdy_data = 0;
  @(negedge clk);
  wait(done_one_layer == 1);
  $display("%d ns: Layer 3 (max pooling) done", $time);

  dram_0.load_l4_l5_data;
  @(negedge clk);
  rdy_data = 1;
  @(negedge clk);
  rdy_data = 0;
  @(negedge clk);
  wait(done_one_layer == 1);
  $display("%d ns: Layer 4 and 5 (fully connected) done", $time);
end

/* result checker */
initial begin
  wait(srstn == 0);
  wait(srstn == 1);
  wait(done == 1);
  //dram_0.print_result(131072, 28, 28, 6);
  //dram_0.print_result(65536, 14, 14, 6);
  //dram_0.print_result(131072, 10, 10, 16);
  //dram_0.print_result(65536, 5, 5, 16);
  dram_0.check_result;
  #(CYCLE);
  $finish;
end

/* watch dog */
initial begin
  #(CYCLE * END_CYCLE);
  $display("%d ns: End cycle reached", $time);
  $finish;
end

initial begin
  `ifdef GATESIM
    while (1) begin
      #(CYCLE * 10000);
      $display("%d ns: Gate simulation is still working", $time);
    end
  `elsif POSTSIM
    while (1) begin
      #(CYCLE * 10000);
      $display("%d ns: Post simulation is still working", $time);
    end
  `endif
end


/* fsdb */
initial begin
  `ifdef GATESIM
  //  $fsdbDumpfile("gatesim.fsdb");
  //  $fsdbDumpvars();
    $sdf_annotate("../syn/netlist/lenet_syn.sdf",lenet);
  `elsif POSTSIM
  //  $fsdbDumpfile("postsim.fsdb");
  //  $fsdbDumpvars();
    $sdf_annotate("../icc/post_layout/CHIP_layout.sdf",CHIP0);
  `elsif DUMP
    $fsdbDumpfile("presim.fsdb");
    $fsdbDumpvars();
  `elsif DUMPMDA
    $fsdbDumpfile("presim.fsdb");
    $fsdbDumpvars(0, test_top, "+mda");
  `endif
end

endmodule
