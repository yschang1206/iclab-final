/**
 * dram.v
 */
module dram
#
(
  parameter DATA_WIDTH = 32,
  parameter ADDR_WIDTH = 18,
  parameter DELAY_CYCLE = 1
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
reg [DATA_WIDTH-1:0] bias [0:5];
integer i;

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

/* initialize dram */
initial begin
  for (i = 0; i < 2**ADDR_WIDTH; i = i + 1)
    data[i] = 0;
end

// use task in top_tb.v ->  dram_0.data2dram;
task data2dram;
begin
  $readmemh("../data/weights.dat", data);
  $readmemh("../data/img.dat", data);
end
endtask

task print_result;
input [ADDR_WIDTH - 1:0] base;
input [4:0] width;
input [4:0] height;
input [4:0] depth;
integer i, j, k;
begin
  $readmemh("../data/biases.dat.unpad", bias);
  //for (i = 0; i < depth; i = i + 1)
    //for (j = 0; j < height; j = j + 1)
  for (i = 0; i < 1; i = i + 1)
    for (j = 0; j < 6; j = j + 1)
      for (k = 0; k < width; k = k + 1)
        $display("%x", data[base + i * 1024 + j * 32 + k] + bias[i]);
end
endtask

endmodule
