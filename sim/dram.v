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
integer i;

// Port A for write
always @(posedge clk) begin
  if (en_wr) data[addr_wr] <= data_in;
end

// Port B for read
always@(posedge clk) begin
  if (en_rd)
    data_out <= data[addr_rd];
  else
    data_out <= 0;
end

always @(posedge clk) begin
  if (~srstn) valid <= 0;
  else valid <= en_rd;
end

/* initialize dram */
initial begin
  for (i = 0; i < 2**ADDR_WIDTH; i = i + 1)
    data[i] = 0;
end

task load_img;
begin
  $readmemh("../data/img.dat", data);
end
endtask

task load_out1;
begin
  $readmemh("../data/out1.dat", data);
end
endtask

task load_l0_pre_data;
begin
  $readmemh("../data/l0_pre.param", data);
  $readmemh("../data/l0.wt", data);
  $readmemh("../data/l0.bs", data);
end
endtask

task load_l0_post_data;
begin
  $readmemh("../data/l0_post.param", data);
end
endtask

task load_l1_data;
begin
  $readmemh("../data/l1.param", data);
end
endtask

task load_l2_pre_data;
begin
  $readmemh("../data/l2_pre.param", data);
  $readmemh("../data/l2.wt", data);
  $readmemh("../data/l2.bs", data);
end
endtask

task load_l2_post_data;
begin
  $readmemh("../data/l2_post.param", data);
end
endtask

task load_l3_data;
begin
  $readmemh("../data/l3.param", data);
end
endtask

task load_l4_l5_data;
begin
  $readmemh("../data/l4.wt", data);
  $readmemh("../data/l4.bs", data);
  $readmemh("../data/l5.wt", data);
  $readmemh("../data/l5.bs", data);
end
endtask

task print_result;
input [ADDR_WIDTH - 1:0] base;
input [4:0] width;
input [4:0] height;
input [4:0] depth;
integer i, j, k, p, n;
reg [DATA_WIDTH-1:0] ans;
reg [DATA_WIDTH-1:0] golden [0:4800];
reg [DATA_WIDTH-1:0] biases [0:15];
begin
  //$readmemh("../data/out0.dat.unpad", golden);
  //$readmemh("../data/out1.dat.unpad", golden);
  //$readmemh("../data/out2.dat.unpad", golden);
  $readmemh("../data/out3.dat.unpad", golden);
  n = 0;
  for (i = 0; i < depth; i = i + 1)
    for (j = 0; j < height; j = j + 1)
      for (k = 0; k < width; k = k + 1) begin
        p = base + i * 1024 + j * 32 + k;
        ans = data[p];

        //if ((ans - golden[n]) < 2 | (golden[n] - ans) < 2)
        if (ans === golden[n])
          $display("%d: %x === %x", n, ans, golden[n]);
        else begin
          $display("%d: %x !== %x", n, ans, golden[n]);
          $finish;
        end
        n = n + 1;
      end
end
endtask

task check_result;
reg [DATA_WIDTH-1:0] golden [0:9];
reg [DATA_WIDTH-1:0] ans;
integer i;
begin
  $readmemh("../data/out5.dat.unpad", golden);
  for (i = 0; i < 10; i = i + 1) begin
    ans = data[131072 + i]; 
    if (ans === golden[i])
      $display("%d: %x === %x", i, ans, golden[i]);
    else begin
      $display("%d: %x !== %x", i, ans, golden[i]);
      $finish;
    end 
  end 
end
endtask

endmodule
