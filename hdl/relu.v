/**
 * relu.v
 */

module relu
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
  output reg [ADDR_WIDTH - 1:0] addr_out,
  output reg dram_en_wr,
  output reg dram_en_rd,
  output wire done
);

localparam  ST_IDLE = 3'd0,
            ST_LD_
