/**
 * pe.v
 */

module pe
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
  input [DATA_WIDTH - 1:0] data_in,
  output [DATA_WIDTH - 1:0] data_out,

  // I/O for controller
  input en_ld_knl,
  input en_ld_ifmap,
  input disable_acc,
  input [4:0] num_knls,
  input [3:0] cnt_ofmap_chnl,
  input en_mac
);

/* local parameters */
/* global wires, registers and integers */
integer i, j;


/* wires and registers for kernels */
reg signed [DATA_WIDTH - 1:0] knls[0:400 - 1];

/* wires and registers for input feature map */
reg signed [DATA_WIDTH - 1:0] ifmap[0:KNL_SIZE - 1];

/* wires and registers for output feature map */
wire signed [DATA_WIDTH - 1:0] mac_nx;
reg signed [DATA_WIDTH - 1:0] mac;

reg signed [DATA_WIDTH - 1:0] prod [0:KNL_SIZE - 1];
reg signed [DATA_WIDTH - 1:0] prod_roff[0:KNL_SIZE - 1];
wire signed [DATA_WIDTH - 1:0] prods;

wire [4:0] addr_knl_prod_tmp;
wire [3:0] addr_knl_prod_nx;
reg [3:0] addr_knl_prod;
assign addr_knl_prod_tmp = 5'd16 - num_knls + {1'd0,cnt_ofmap_chnl};
                  //  KNL_MAXNUM - num_knls + cnt_ofmap_chnl_ff
assign addr_knl_prod_nx = addr_knl_prod_tmp[3:0];

always @(posedge clk) begin
  addr_knl_prod <= addr_knl_prod_nx;
end
/* convolution process */
always@(posedge clk) begin
  if (~srstn) mac <= 0;
  else        mac <= mac_nx;
end

reg signed [DATA_WIDTH - 1:0] knls_ff [0:24];
reg signed [DATA_WIDTH - 1:0] knls_data [0:24];

always @(*) begin
  for (i = 0; i < 25; i = i+1) begin
    case (addr_knl_prod) // synopsys parallel_case
      4'd0 : knls_data[i] = knls[0+i];
      4'd1 : knls_data[i] = knls[25+i];
      4'd2 : knls_data[i] = knls[50+i];
      4'd3 : knls_data[i] = knls[75+i];
      4'd4 : knls_data[i] = knls[100+i];
      4'd5 : knls_data[i] = knls[125+i];
      4'd6 : knls_data[i] = knls[150+i];
      4'd7 : knls_data[i] = knls[175+i];
      4'd8 : knls_data[i] = knls[200+i];
      4'd9 : knls_data[i] = knls[225+i];
      4'd10 : knls_data[i] = knls[250+i];
      4'd11 : knls_data[i] = knls[275+i];
      4'd12 : knls_data[i] = knls[300+i];
      4'd13 : knls_data[i] = knls[325+i];
      4'd14 : knls_data[i] = knls[350+i];
      default : knls_data[i] = knls[375+i];
    endcase
  end
end

/* ------------------------------------------------------------- */
always @(posedge clk) begin
  if (~srstn) begin
    for (i = 0; i < 25; i=i+1) begin
      knls_ff[i] <= 0;
    end
  end
  else begin
    for (i = 0; i < 25; i=i+1) begin
      knls_ff[i] <= knls_data[i];
    end
  end
end 

assign data_out = (disable_acc) ? mac : data_in + mac;

always@(*) begin
  for (i = 0; i < 5; i = i+1) begin
    for (j = 0; j < 5; j = j+1) begin
      prod[i*5 + j] = knls_ff[i*5 + j] * ifmap[j*5 + i];
      prod_roff[i*5 + j] = prod[i*5 + j] >>> 16;
    end
  end
end

assign prods = prod_roff[0] + prod_roff[1] + prod_roff[2] + prod_roff[3] + prod_roff[4] +
                prod_roff[5] + prod_roff[6] + prod_roff[7] + prod_roff[8] + prod_roff[9] + 
                prod_roff[10] + prod_roff[11] + prod_roff[12] + prod_roff[13] + prod_roff[14] +
                prod_roff[15] + prod_roff[16] + prod_roff[17] + prod_roff[18] + prod_roff[19] +
                prod_roff[20] + prod_roff[21] + prod_roff[22] + prod_roff[23] + prod_roff[24];

/* connection table */
assign mac_nx = (en_mac) ? prods : 0;


/* weight register file */
always @(posedge clk) begin
  if (~srstn) begin
    for (i = 0; i < KNL_MAXNUM*KNL_SIZE; i = i+1)
      knls[i] <= 0;
  end
  else if (en_ld_knl) begin
    knls[KNL_MAXNUM*KNL_SIZE - 1] <= data_in;
    for (i = 0; i < KNL_MAXNUM*KNL_SIZE - 1; i = i+1)
      knls[i] <= knls[i+1];
  end
end

/* input feature map register file */
always @(posedge clk) begin
  if (~srstn) begin
    for (i = 0; i < KNL_SIZE; i = i+1)
      ifmap[i] <= 0;
  end
  else if (en_ld_ifmap) begin
    ifmap[KNL_SIZE - 1] <= data_in;
    for (i = 0; i < KNL_SIZE-1; i = i+1)
      ifmap[i] <= ifmap[i+1];
  end
end

endmodule
