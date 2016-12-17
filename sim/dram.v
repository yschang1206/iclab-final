/**
 * dram.v
 */
module dram
#
(
  parameter DATA_WIDTH = 32,
  parameter ADDR_WIDTH = 18,
  parameter DELAY_CYCLE = 1,

  parameter WEIGHT_START_ADDR = 0,
  parameter WEIGHT_END_ADDR = 16383,
  parameter PAT_START_ADDR = 0,
  parameter PAT_END_ADDR = 0
)
(
  input clk,
  input srstn,
  // Port A for write
  input en_wr,
  input [ADDR_WIDTH-1:0] addr_wr,
  input [DATA_WIDTH-1:0] data_in,
  // Port B for read
  input en_rd,
  input [ADDR_WIDTH-1:0] addr_rd,
  output reg valid,
  output reg [DATA_WIDTH-1:0] data_out
);

// Declare the RAM variable
reg [DATA_WIDTH-1:0] data [0:2**ADDR_WIDTH-1];

// Port A for write
always @(posedge clk) begin
  if (en_wr) data[addr_wr] <= data_in;
end

// Port B for read
always @(posedge clk) begin
  if (en_rd) data_out <= data[addr_rd];
  else data_out <= 0;
end

always @(posedge clk) begin
  if (~srstn) valid <= 0;
  else valid <= en_rd;
end

// ====== DRAM connection =====
/*
dram dram_0(
  .clk(clk),
  .srstn(srstn),
  .en_wr(en_wr),
  .addr_wr(addr_wr),
  .data_in(data_in),
  .en_rd(en_rd),
  .addr_rd(addr_rd),
  .valid(valid),
  .data_out(data_out)
);
*/

// use task in top_tb.v ->  dram_0.data2dram;
task data2dram;
  begin
    $readmemh("../data/weights.dat", data, WEIGHT_START_ADDR, WEIGHT_END_ADDR);
    //$readmemh("pattern.dat", data, PAT_START_ADDR, PAT_END_ADDR);
  end
endtask

endmodule
