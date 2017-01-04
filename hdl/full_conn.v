/**
 * full_conn.v
 */

module full_conn
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
  output [ADDR_WIDTH - 1:0] addr_out,
  output dram_en_wr,
  output dram_en_rd,
  output wire done
);

/* local parameters */
localparam  IDX_IDLE     = 0,
            IDX_LD_IFMAP = 1,
            IDX_MAC_PS1  = 2,    // multiply and accumulate, phase 1
            IDX_BIAS_PS1 = 3,   // bias and relu, phase 1
            IDX_MAC_PS2  = 4,    // multiply and accumulate, phase 2
            IDX_BIAS_PS2 = 5,   // bias and relu, phase 2
            IDX_DONE     = 6;

localparam  ST_IDLE     = 7'b0000001,
            ST_LD_IFMAP = 7'b0000010,
            ST_MAC_PS1  = 7'b0000100, // multiply and accumulate, phase 1
            ST_BIAS_PS1 = 7'b0001000, // bias and relu, phase 1
            ST_MAC_PS2  = 7'b0010000, // multiply and accumulate, phase 2
            ST_BIAS_PS2 = 7'b0100000, // bias and relu, phase 2
            ST_DONE     = 7'b1000000;

localparam  WT_BASE_PS1 = 18'd0,
            BS_BASE_PS1 = 18'd48000,
            WT_BASE_PS2 = 18'd50000,
            BS_BASE_PS2 = 18'd51200,
            IFMAP_BASE  = 18'd65536,
            OFMAP_BASE  = 18'd131072;

localparam  NUM_KNLS_PS1 = 120,
            WIDTH_PS1    = 5,
            HEIGHT_PS1   = 5,
            AREA_PS1     = 25,
            DEPTH_PS1    = 16,
            SIZE_PS1     = 400,

            NUM_KNLS_PS2 = 10,
            WIDTH_PS2    = 1,
            HEIGHT_PS2   = 1,
            AREA_PS2     = 1,
            DEPTH_PS2    = 120,
            SIZE_PS2     = 120;

localparam  IDX_NUM_KNLS_PS1_LAST = 7'd119,
            IDX_WIDTH_PS1_LAST    = 3'd4,
            IDX_HEIGHT_PS1_LAST   = 3'd4,
            IDX_DEPTH_PS1_LAST    = 4'd15,
            IDX_SIZE_PS1_LAST     = 9'd399,
            IDX_NUM_KNLS_PS2_LAST = 4'd9,
            IDX_SIZE_PS2_LAST     = 7'd119;

/* global regs and integers */
reg [6:0] state, state_nx;
integer i;

/* regs and wires for storing output feature map */
reg signed [DATA_WIDTH-1:0] ofmap_tmp[0:NUM_KNLS_PS1-1];

/* regs and wires for loading input feature map */
reg signed [DATA_WIDTH-1:0] ifmap[0:SIZE_PS1-1];
reg [2:0] cnt_ifmap_x, cnt_ifmap_x_nx;
reg [2:0] cnt_ifmap_y, cnt_ifmap_y_nx;
reg [3:0] cnt_ifmap_z, cnt_ifmap_z_nx;
wire ifmap_x_last, ifmap_y_last, ifmap_z_last;
wire ifmap_last;
reg en_ld_ifmap;

/* regs and wires for loading weights */
reg signed [DATA_WIDTH-1:0] wt1;
reg signed [DATA_WIDTH-1:0] wt2;
reg [8:0] cnt_wt1, cnt_wt1_nx;
reg [8:0] cnt_wt2, cnt_wt2_nx;
reg [8:0] cnt_wt1_ff[0:1];
reg [8:0] cnt_wt2_ff[0:1];
wire wt1_last, wt2_last;
reg en_ld_wt1, en_ld_wt2;
reg valid_prod1, valid_prod2;

/* regs and wires for loading biases */
reg [DATA_WIDTH-1:0] bs1;
reg [DATA_WIDTH-1:0] bs2;
reg [6:0] cnt_bs1, cnt_bs1_nx;
reg [3:0] cnt_bs2, cnt_bs2_nx;
reg [6:0] cnt_bs1_ff[0:1];
reg [3:0] cnt_bs2_ff[0:1];
wire bs1_last, bs2_last;
reg en_ld_bs1, en_ld_bs2;
reg valid_bs1, valid_bs2;

/* regs to store products and macs */
reg signed [DATA_WIDTH-1:0] prod1, prod1_roff;
reg signed [DATA_WIDTH-1:0] prod2, prod2_roff;
reg signed [DATA_WIDTH-1:0] mac1, mac1_nx;
wire signed [DATA_WIDTH-1:0] mac1_bs, mac1_relu;
reg signed [DATA_WIDTH-1:0] mac2, mac2_nx;
wire signed [DATA_WIDTH-1:0] mac2_bs, mac2_relu;
reg signed [DATA_WIDTH-1:0] pixel_ps1;
reg signed [DATA_WIDTH-1:0] pixel_ps2;

/* event flags */
assign ifmap_x_last = (cnt_ifmap_x == IDX_WIDTH_PS1_LAST);
assign ifmap_y_last = (cnt_ifmap_y == IDX_HEIGHT_PS1_LAST);
assign ifmap_z_last = (cnt_ifmap_z == IDX_DEPTH_PS1_LAST);
assign ifmap_last = (ifmap_x_last & ifmap_y_last & ifmap_z_last);
assign wt1_last = (cnt_wt1 == IDX_SIZE_PS1_LAST);
assign bs1_last = (cnt_bs1 == IDX_NUM_KNLS_PS1_LAST);
assign wt2_last = (cnt_wt2 == IDX_SIZE_PS2_LAST);
assign bs2_last = (cnt_bs2 == IDX_NUM_KNLS_PS2_LAST);


always @(posedge clk) begin
  if (~srstn) state <= ST_IDLE;
  else        state <= state_nx;
end

always@(*) begin // finite state machine
  case (state)
    ST_IDLE:      state_nx = (enable) ? ST_LD_IFMAP : ST_IDLE;
    ST_LD_IFMAP:  state_nx = (ifmap_last) ? ST_MAC_PS1 : ST_LD_IFMAP;
    ST_MAC_PS1:   state_nx = (wt1_last) ? ST_BIAS_PS1 : ST_MAC_PS1;
    ST_BIAS_PS1:  state_nx = (bs1_last) ? ST_MAC_PS2 : ST_MAC_PS1;
    ST_MAC_PS2:   state_nx = (wt2_last) ? ST_BIAS_PS2 : ST_MAC_PS2; 
    ST_BIAS_PS2:  state_nx = (bs2_last) ? ST_DONE : ST_MAC_PS2;
    ST_DONE:      state_nx = ST_IDLE;
    default:      state_nx = ST_IDLE;
  endcase
end

assign done = state[IDX_DONE]; // output logic: done signal

wire [17:0] cnt_bs1_prod_addr, cnt_bs2_prod_addr;

assign cnt_bs1_prod_addr = cnt_bs1 * 9'd400;
assign cnt_bs2_prod_addr = cnt_bs2 * 7'd120;
always@(*) begin // output logic: input memory address translator
  case ({state[IDX_LD_IFMAP], state[IDX_MAC_PS1], state[IDX_BIAS_PS1], state[IDX_MAC_PS2], state[IDX_BIAS_PS2]}) // synopsys parallel_case
    5'b10000: addr_in = IFMAP_BASE + {4'd0, cnt_ifmap_z, {2'd0, cnt_ifmap_y}, {2'd0, cnt_ifmap_x}};
    5'b01000: addr_in = WT_BASE_PS1 + {9'd0, cnt_wt1} + cnt_bs1_prod_addr;
    5'b00100: addr_in = BS_BASE_PS1 + {11'd0, cnt_bs1};
    5'b00010: addr_in = WT_BASE_PS2 + {9'd0, cnt_wt2} + cnt_bs2_prod_addr;
    5'b00001: addr_in = BS_BASE_PS2 + {14'd0, cnt_bs2};
    default:  addr_in = 0;
  endcase
end

/* output memory address translator */
assign addr_out = OFMAP_BASE + {14'd0, cnt_bs2_ff[1]};

assign dram_en_rd = ~state[IDX_IDLE];
assign dram_en_wr = valid_bs2;

/* input feature map register file */
always@(posedge clk) begin
  //if (~srstn)
  //  for (i = 0; i < SIZE_PS1; i = i + 1)
  //    ifmap[i] <= 0;
  //else 
  if (en_ld_ifmap) begin
    ifmap[SIZE_PS1 - 1] <= data_in;
    for (i = 0; i < SIZE_PS1 - 1; i = i+1)
      ifmap[i] <= ifmap[i+1];
  end
  else if (valid_prod1) begin
    ifmap[SIZE_PS1 - 1] <= ifmap[0];
    for (i = 0; i < SIZE_PS1 - 1; i = i+1)
      ifmap[i] <= ifmap[i+1];
  end
end

/* register file to store feature map after phase 1 */
always @(posedge clk) begin
  if (~srstn)
    ofmap_tmp[NUM_KNLS_PS1 - 1] <= 0;
  else if (valid_bs1) 
    ofmap_tmp[NUM_KNLS_PS1 - 1] <= mac1_relu;
  else if (valid_prod2) begin
    ofmap_tmp[NUM_KNLS_PS1 - 1] <= ofmap_tmp[0];
    for (i = 0; i < NUM_KNLS_PS1 - 1; i = i + 1)
      ofmap_tmp[i] <= ofmap_tmp[i + 1];
  end
end

always @(posedge clk) begin
  if (valid_bs1) begin
    for (i = 0; i < NUM_KNLS_PS1 - 1; i = i+1)
      ofmap_tmp[i] <= ofmap_tmp[i+1];
  end
end

always @(posedge clk) begin
  if (~srstn) wt1 <= 0;
  else if (en_ld_wt1) wt1 <= data_in;
end

always @(posedge clk) begin
  if (~srstn) wt2 <= 0;
  else if (en_ld_wt2) wt2 <= data_in;
end

always @(posedge clk) begin
  if (~srstn) bs1 <= 0;
  else if (en_ld_bs1) bs1 <= data_in;
end

always @(posedge clk) begin
  if (~srstn) bs2 <= 0;
  else if (en_ld_bs2) bs2 <= data_in;
end

/* write the result back to dram */
assign data_out = mac2_relu;

/* enable signals */
always@(posedge clk) begin
  if (~srstn) begin
    en_ld_ifmap <= 0;
    en_ld_wt1 <= 0;
    en_ld_wt2 <= 0;
    en_ld_bs1 <= 0;
    en_ld_bs2 <= 0;
  end
  else begin
    en_ld_ifmap <= state[IDX_LD_IFMAP];
    en_ld_wt1 <= state[IDX_MAC_PS1];
    en_ld_wt2 <= state[IDX_MAC_PS2];
    en_ld_bs1 <= state[IDX_BIAS_PS1];
    en_ld_bs2 <= state[IDX_BIAS_PS2];
  end
end

/* valid signals */
always@(posedge clk) begin
  if (~srstn) begin
    valid_prod1 <= 0;
    valid_prod2 <= 0;
    valid_bs1 <= 0;
    valid_bs2 <= 0;
  end
  else begin
    valid_prod1 <= en_ld_wt1;
    valid_prod2 <= en_ld_wt2;
    valid_bs1 <= en_ld_bs1;
    valid_bs2 <= en_ld_bs2;
  end
end

/* delayed signals */
always@(posedge clk) begin
  if (~srstn) begin
    cnt_wt1_ff[0] <= 0;
    cnt_wt1_ff[1] <= 0;
    cnt_wt2_ff[0] <= 0;
    cnt_wt2_ff[1] <= 0;
    cnt_bs1_ff[0] <= 0;
    cnt_bs1_ff[1] <= 0;
    cnt_bs2_ff[0] <= 0;
    cnt_bs2_ff[1] <= 0;
  end
  else begin
    cnt_wt1_ff[0] <= cnt_wt1;
    cnt_wt1_ff[1] <= cnt_wt1_ff[0];
    cnt_wt2_ff[0] <= cnt_wt2;
    cnt_wt2_ff[1] <= cnt_wt2_ff[0];
    cnt_bs1_ff[0] <= cnt_bs1;
    cnt_bs1_ff[1] <= cnt_bs1_ff[0];
    cnt_bs2_ff[0] <= cnt_bs2;
    cnt_bs2_ff[1] <= cnt_bs2_ff[0];
  end
end
reg signed [DATA_WIDTH-1:0] pixel_ps1_nx;
/* buffer input feature map */
always@(posedge clk) begin
  if (~srstn) begin
    pixel_ps1 <= 0;
    pixel_ps2 <= 0;
  end
  else
    pixel_ps1 <= pixel_ps1_nx;
    pixel_ps2 <= ofmap_tmp[cnt_wt2_ff[0]];
end

always @(*) begin
  case (cnt_wt1_ff[0])
    9'd0 : pixel_ps1_nx = ifmap[0];
    9'd1 : pixel_ps1_nx = ifmap[1];
    9'd2 : pixel_ps1_nx = ifmap[2];
    9'd3 : pixel_ps1_nx = ifmap[3];
    9'd4 : pixel_ps1_nx = ifmap[4];
    9'd5 : pixel_ps1_nx = ifmap[5];
    9'd6 : pixel_ps1_nx = ifmap[6];
    9'd7 : pixel_ps1_nx = ifmap[7];
    9'd8 : pixel_ps1_nx = ifmap[8];
    9'd9 : pixel_ps1_nx = ifmap[9];
    9'd10 : pixel_ps1_nx = ifmap[10];
    9'd11 : pixel_ps1_nx = ifmap[11];
    9'd12 : pixel_ps1_nx = ifmap[12];
    9'd13 : pixel_ps1_nx = ifmap[13];
    9'd14 : pixel_ps1_nx = ifmap[14];
    9'd15 : pixel_ps1_nx = ifmap[15];
    9'd16 : pixel_ps1_nx = ifmap[16];
    9'd17 : pixel_ps1_nx = ifmap[17];
    9'd18 : pixel_ps1_nx = ifmap[18];
    9'd19 : pixel_ps1_nx = ifmap[19];
    9'd20 : pixel_ps1_nx = ifmap[20];
    9'd21 : pixel_ps1_nx = ifmap[21];
    9'd22 : pixel_ps1_nx = ifmap[22];
    9'd23 : pixel_ps1_nx = ifmap[23];
    9'd24 : pixel_ps1_nx = ifmap[24];
    9'd25 : pixel_ps1_nx = ifmap[25];
    9'd26 : pixel_ps1_nx = ifmap[26];
    9'd27 : pixel_ps1_nx = ifmap[27];
    9'd28 : pixel_ps1_nx = ifmap[28];
    9'd29 : pixel_ps1_nx = ifmap[29];
    9'd30 : pixel_ps1_nx = ifmap[30];
    9'd31 : pixel_ps1_nx = ifmap[31];
    9'd32 : pixel_ps1_nx = ifmap[32];
    9'd33 : pixel_ps1_nx = ifmap[33];
    9'd34 : pixel_ps1_nx = ifmap[34];
    9'd35 : pixel_ps1_nx = ifmap[35];
    9'd36 : pixel_ps1_nx = ifmap[36];
    9'd37 : pixel_ps1_nx = ifmap[37];
    9'd38 : pixel_ps1_nx = ifmap[38];
    9'd39 : pixel_ps1_nx = ifmap[39];
    9'd40 : pixel_ps1_nx = ifmap[40];
    9'd41 : pixel_ps1_nx = ifmap[41];
    9'd42 : pixel_ps1_nx = ifmap[42];
    9'd43 : pixel_ps1_nx = ifmap[43];
    9'd44 : pixel_ps1_nx = ifmap[44];
    9'd45 : pixel_ps1_nx = ifmap[45];
    9'd46 : pixel_ps1_nx = ifmap[46];
    9'd47 : pixel_ps1_nx = ifmap[47];
    9'd48 : pixel_ps1_nx = ifmap[48];
    9'd49 : pixel_ps1_nx = ifmap[49];
    9'd50 : pixel_ps1_nx = ifmap[50];
    9'd51 : pixel_ps1_nx = ifmap[51];
    9'd52 : pixel_ps1_nx = ifmap[52];
    9'd53 : pixel_ps1_nx = ifmap[53];
    9'd54 : pixel_ps1_nx = ifmap[54];
    9'd55 : pixel_ps1_nx = ifmap[55];
    9'd56 : pixel_ps1_nx = ifmap[56];
    9'd57 : pixel_ps1_nx = ifmap[57];
    9'd58 : pixel_ps1_nx = ifmap[58];
    9'd59 : pixel_ps1_nx = ifmap[59];
    9'd60 : pixel_ps1_nx = ifmap[60];
    9'd61 : pixel_ps1_nx = ifmap[61];
    9'd62 : pixel_ps1_nx = ifmap[62];
    9'd63 : pixel_ps1_nx = ifmap[63];
    9'd64 : pixel_ps1_nx = ifmap[64];
    9'd65 : pixel_ps1_nx = ifmap[65];
    9'd66 : pixel_ps1_nx = ifmap[66];
    9'd67 : pixel_ps1_nx = ifmap[67];
    9'd68 : pixel_ps1_nx = ifmap[68];
    9'd69 : pixel_ps1_nx = ifmap[69];
    9'd70 : pixel_ps1_nx = ifmap[70];
    9'd71 : pixel_ps1_nx = ifmap[71];
    9'd72 : pixel_ps1_nx = ifmap[72];
    9'd73 : pixel_ps1_nx = ifmap[73];
    9'd74 : pixel_ps1_nx = ifmap[74];
    9'd75 : pixel_ps1_nx = ifmap[75];
    9'd76 : pixel_ps1_nx = ifmap[76];
    9'd77 : pixel_ps1_nx = ifmap[77];
    9'd78 : pixel_ps1_nx = ifmap[78];
    9'd79 : pixel_ps1_nx = ifmap[79];
    9'd80 : pixel_ps1_nx = ifmap[80];
    9'd81 : pixel_ps1_nx = ifmap[81];
    9'd82 : pixel_ps1_nx = ifmap[82];
    9'd83 : pixel_ps1_nx = ifmap[83];
    9'd84 : pixel_ps1_nx = ifmap[84];
    9'd85 : pixel_ps1_nx = ifmap[85];
    9'd86 : pixel_ps1_nx = ifmap[86];
    9'd87 : pixel_ps1_nx = ifmap[87];
    9'd88 : pixel_ps1_nx = ifmap[88];
    9'd89 : pixel_ps1_nx = ifmap[89];
    9'd90 : pixel_ps1_nx = ifmap[90];
    9'd91 : pixel_ps1_nx = ifmap[91];
    9'd92 : pixel_ps1_nx = ifmap[92];
    9'd93 : pixel_ps1_nx = ifmap[93];
    9'd94 : pixel_ps1_nx = ifmap[94];
    9'd95 : pixel_ps1_nx = ifmap[95];
    9'd96 : pixel_ps1_nx = ifmap[96];
    9'd97 : pixel_ps1_nx = ifmap[97];
    9'd98 : pixel_ps1_nx = ifmap[98];
    9'd99 : pixel_ps1_nx = ifmap[99];
    9'd100 : pixel_ps1_nx = ifmap[100];
    9'd101 : pixel_ps1_nx = ifmap[101];
    9'd102 : pixel_ps1_nx = ifmap[102];
    9'd103 : pixel_ps1_nx = ifmap[103];
    9'd104 : pixel_ps1_nx = ifmap[104];
    9'd105 : pixel_ps1_nx = ifmap[105];
    9'd106 : pixel_ps1_nx = ifmap[106];
    9'd107 : pixel_ps1_nx = ifmap[107];
    9'd108 : pixel_ps1_nx = ifmap[108];
    9'd109 : pixel_ps1_nx = ifmap[109];
    9'd110 : pixel_ps1_nx = ifmap[110];
    9'd111 : pixel_ps1_nx = ifmap[111];
    9'd112 : pixel_ps1_nx = ifmap[112];
    9'd113 : pixel_ps1_nx = ifmap[113];
    9'd114 : pixel_ps1_nx = ifmap[114];
    9'd115 : pixel_ps1_nx = ifmap[115];
    9'd116 : pixel_ps1_nx = ifmap[116];
    9'd117 : pixel_ps1_nx = ifmap[117];
    9'd118 : pixel_ps1_nx = ifmap[118];
    9'd119 : pixel_ps1_nx = ifmap[119];
    9'd120 : pixel_ps1_nx = ifmap[120];
    9'd121 : pixel_ps1_nx = ifmap[121];
    9'd122 : pixel_ps1_nx = ifmap[122];
    9'd123 : pixel_ps1_nx = ifmap[123];
    9'd124 : pixel_ps1_nx = ifmap[124];
    9'd125 : pixel_ps1_nx = ifmap[125];
    9'd126 : pixel_ps1_nx = ifmap[126];
    9'd127 : pixel_ps1_nx = ifmap[127];
    9'd128 : pixel_ps1_nx = ifmap[128];
    9'd129 : pixel_ps1_nx = ifmap[129];
    9'd130 : pixel_ps1_nx = ifmap[130];
    9'd131 : pixel_ps1_nx = ifmap[131];
    9'd132 : pixel_ps1_nx = ifmap[132];
    9'd133 : pixel_ps1_nx = ifmap[133];
    9'd134 : pixel_ps1_nx = ifmap[134];
    9'd135 : pixel_ps1_nx = ifmap[135];
    9'd136 : pixel_ps1_nx = ifmap[136];
    9'd137 : pixel_ps1_nx = ifmap[137];
    9'd138 : pixel_ps1_nx = ifmap[138];
    9'd139 : pixel_ps1_nx = ifmap[139];
    9'd140 : pixel_ps1_nx = ifmap[140];
    9'd141 : pixel_ps1_nx = ifmap[141];
    9'd142 : pixel_ps1_nx = ifmap[142];
    9'd143 : pixel_ps1_nx = ifmap[143];
    9'd144 : pixel_ps1_nx = ifmap[144];
    9'd145 : pixel_ps1_nx = ifmap[145];
    9'd146 : pixel_ps1_nx = ifmap[146];
    9'd147 : pixel_ps1_nx = ifmap[147];
    9'd148 : pixel_ps1_nx = ifmap[148];
    9'd149 : pixel_ps1_nx = ifmap[149];
    9'd150 : pixel_ps1_nx = ifmap[150];
    9'd151 : pixel_ps1_nx = ifmap[151];
    9'd152 : pixel_ps1_nx = ifmap[152];
    9'd153 : pixel_ps1_nx = ifmap[153];
    9'd154 : pixel_ps1_nx = ifmap[154];
    9'd155 : pixel_ps1_nx = ifmap[155];
    9'd156 : pixel_ps1_nx = ifmap[156];
    9'd157 : pixel_ps1_nx = ifmap[157];
    9'd158 : pixel_ps1_nx = ifmap[158];
    9'd159 : pixel_ps1_nx = ifmap[159];
    9'd160 : pixel_ps1_nx = ifmap[160];
    9'd161 : pixel_ps1_nx = ifmap[161];
    9'd162 : pixel_ps1_nx = ifmap[162];
    9'd163 : pixel_ps1_nx = ifmap[163];
    9'd164 : pixel_ps1_nx = ifmap[164];
    9'd165 : pixel_ps1_nx = ifmap[165];
    9'd166 : pixel_ps1_nx = ifmap[166];
    9'd167 : pixel_ps1_nx = ifmap[167];
    9'd168 : pixel_ps1_nx = ifmap[168];
    9'd169 : pixel_ps1_nx = ifmap[169];
    9'd170 : pixel_ps1_nx = ifmap[170];
    9'd171 : pixel_ps1_nx = ifmap[171];
    9'd172 : pixel_ps1_nx = ifmap[172];
    9'd173 : pixel_ps1_nx = ifmap[173];
    9'd174 : pixel_ps1_nx = ifmap[174];
    9'd175 : pixel_ps1_nx = ifmap[175];
    9'd176 : pixel_ps1_nx = ifmap[176];
    9'd177 : pixel_ps1_nx = ifmap[177];
    9'd178 : pixel_ps1_nx = ifmap[178];
    9'd179 : pixel_ps1_nx = ifmap[179];
    9'd180 : pixel_ps1_nx = ifmap[180];
    9'd181 : pixel_ps1_nx = ifmap[181];
    9'd182 : pixel_ps1_nx = ifmap[182];
    9'd183 : pixel_ps1_nx = ifmap[183];
    9'd184 : pixel_ps1_nx = ifmap[184];
    9'd185 : pixel_ps1_nx = ifmap[185];
    9'd186 : pixel_ps1_nx = ifmap[186];
    9'd187 : pixel_ps1_nx = ifmap[187];
    9'd188 : pixel_ps1_nx = ifmap[188];
    9'd189 : pixel_ps1_nx = ifmap[189];
    9'd190 : pixel_ps1_nx = ifmap[190];
    9'd191 : pixel_ps1_nx = ifmap[191];
    9'd192 : pixel_ps1_nx = ifmap[192];
    9'd193 : pixel_ps1_nx = ifmap[193];
    9'd194 : pixel_ps1_nx = ifmap[194];
    9'd195 : pixel_ps1_nx = ifmap[195];
    9'd196 : pixel_ps1_nx = ifmap[196];
    9'd197 : pixel_ps1_nx = ifmap[197];
    9'd198 : pixel_ps1_nx = ifmap[198];
    9'd199 : pixel_ps1_nx = ifmap[199];
    9'd200 : pixel_ps1_nx = ifmap[200];
    9'd201 : pixel_ps1_nx = ifmap[201];
    9'd202 : pixel_ps1_nx = ifmap[202];
    9'd203 : pixel_ps1_nx = ifmap[203];
    9'd204 : pixel_ps1_nx = ifmap[204];
    9'd205 : pixel_ps1_nx = ifmap[205];
    9'd206 : pixel_ps1_nx = ifmap[206];
    9'd207 : pixel_ps1_nx = ifmap[207];
    9'd208 : pixel_ps1_nx = ifmap[208];
    9'd209 : pixel_ps1_nx = ifmap[209];
    9'd210 : pixel_ps1_nx = ifmap[210];
    9'd211 : pixel_ps1_nx = ifmap[211];
    9'd212 : pixel_ps1_nx = ifmap[212];
    9'd213 : pixel_ps1_nx = ifmap[213];
    9'd214 : pixel_ps1_nx = ifmap[214];
    9'd215 : pixel_ps1_nx = ifmap[215];
    9'd216 : pixel_ps1_nx = ifmap[216];
    9'd217 : pixel_ps1_nx = ifmap[217];
    9'd218 : pixel_ps1_nx = ifmap[218];
    9'd219 : pixel_ps1_nx = ifmap[219];
    9'd220 : pixel_ps1_nx = ifmap[220];
    9'd221 : pixel_ps1_nx = ifmap[221];
    9'd222 : pixel_ps1_nx = ifmap[222];
    9'd223 : pixel_ps1_nx = ifmap[223];
    9'd224 : pixel_ps1_nx = ifmap[224];
    9'd225 : pixel_ps1_nx = ifmap[225];
    9'd226 : pixel_ps1_nx = ifmap[226];
    9'd227 : pixel_ps1_nx = ifmap[227];
    9'd228 : pixel_ps1_nx = ifmap[228];
    9'd229 : pixel_ps1_nx = ifmap[229];
    9'd230 : pixel_ps1_nx = ifmap[230];
    9'd231 : pixel_ps1_nx = ifmap[231];
    9'd232 : pixel_ps1_nx = ifmap[232];
    9'd233 : pixel_ps1_nx = ifmap[233];
    9'd234 : pixel_ps1_nx = ifmap[234];
    9'd235 : pixel_ps1_nx = ifmap[235];
    9'd236 : pixel_ps1_nx = ifmap[236];
    9'd237 : pixel_ps1_nx = ifmap[237];
    9'd238 : pixel_ps1_nx = ifmap[238];
    9'd239 : pixel_ps1_nx = ifmap[239];
    9'd240 : pixel_ps1_nx = ifmap[240];
    9'd241 : pixel_ps1_nx = ifmap[241];
    9'd242 : pixel_ps1_nx = ifmap[242];
    9'd243 : pixel_ps1_nx = ifmap[243];
    9'd244 : pixel_ps1_nx = ifmap[244];
    9'd245 : pixel_ps1_nx = ifmap[245];
    9'd246 : pixel_ps1_nx = ifmap[246];
    9'd247 : pixel_ps1_nx = ifmap[247];
    9'd248 : pixel_ps1_nx = ifmap[248];
    9'd249 : pixel_ps1_nx = ifmap[249];
    9'd250 : pixel_ps1_nx = ifmap[250];
    9'd251 : pixel_ps1_nx = ifmap[251];
    9'd252 : pixel_ps1_nx = ifmap[252];
    9'd253 : pixel_ps1_nx = ifmap[253];
    9'd254 : pixel_ps1_nx = ifmap[254];
    9'd255 : pixel_ps1_nx = ifmap[255];
    9'd256 : pixel_ps1_nx = ifmap[256];
    9'd257 : pixel_ps1_nx = ifmap[257];
    9'd258 : pixel_ps1_nx = ifmap[258];
    9'd259 : pixel_ps1_nx = ifmap[259];
    9'd260 : pixel_ps1_nx = ifmap[260];
    9'd261 : pixel_ps1_nx = ifmap[261];
    9'd262 : pixel_ps1_nx = ifmap[262];
    9'd263 : pixel_ps1_nx = ifmap[263];
    9'd264 : pixel_ps1_nx = ifmap[264];
    9'd265 : pixel_ps1_nx = ifmap[265];
    9'd266 : pixel_ps1_nx = ifmap[266];
    9'd267 : pixel_ps1_nx = ifmap[267];
    9'd268 : pixel_ps1_nx = ifmap[268];
    9'd269 : pixel_ps1_nx = ifmap[269];
    9'd270 : pixel_ps1_nx = ifmap[270];
    9'd271 : pixel_ps1_nx = ifmap[271];
    9'd272 : pixel_ps1_nx = ifmap[272];
    9'd273 : pixel_ps1_nx = ifmap[273];
    9'd274 : pixel_ps1_nx = ifmap[274];
    9'd275 : pixel_ps1_nx = ifmap[275];
    9'd276 : pixel_ps1_nx = ifmap[276];
    9'd277 : pixel_ps1_nx = ifmap[277];
    9'd278 : pixel_ps1_nx = ifmap[278];
    9'd279 : pixel_ps1_nx = ifmap[279];
    9'd280 : pixel_ps1_nx = ifmap[280];
    9'd281 : pixel_ps1_nx = ifmap[281];
    9'd282 : pixel_ps1_nx = ifmap[282];
    9'd283 : pixel_ps1_nx = ifmap[283];
    9'd284 : pixel_ps1_nx = ifmap[284];
    9'd285 : pixel_ps1_nx = ifmap[285];
    9'd286 : pixel_ps1_nx = ifmap[286];
    9'd287 : pixel_ps1_nx = ifmap[287];
    9'd288 : pixel_ps1_nx = ifmap[288];
    9'd289 : pixel_ps1_nx = ifmap[289];
    9'd290 : pixel_ps1_nx = ifmap[290];
    9'd291 : pixel_ps1_nx = ifmap[291];
    9'd292 : pixel_ps1_nx = ifmap[292];
    9'd293 : pixel_ps1_nx = ifmap[293];
    9'd294 : pixel_ps1_nx = ifmap[294];
    9'd295 : pixel_ps1_nx = ifmap[295];
    9'd296 : pixel_ps1_nx = ifmap[296];
    9'd297 : pixel_ps1_nx = ifmap[297];
    9'd298 : pixel_ps1_nx = ifmap[298];
    9'd299 : pixel_ps1_nx = ifmap[299];
    9'd300 : pixel_ps1_nx = ifmap[300];
    9'd301 : pixel_ps1_nx = ifmap[301];
    9'd302 : pixel_ps1_nx = ifmap[302];
    9'd303 : pixel_ps1_nx = ifmap[303];
    9'd304 : pixel_ps1_nx = ifmap[304];
    9'd305 : pixel_ps1_nx = ifmap[305];
    9'd306 : pixel_ps1_nx = ifmap[306];
    9'd307 : pixel_ps1_nx = ifmap[307];
    9'd308 : pixel_ps1_nx = ifmap[308];
    9'd309 : pixel_ps1_nx = ifmap[309];
    9'd310 : pixel_ps1_nx = ifmap[310];
    9'd311 : pixel_ps1_nx = ifmap[311];
    9'd312 : pixel_ps1_nx = ifmap[312];
    9'd313 : pixel_ps1_nx = ifmap[313];
    9'd314 : pixel_ps1_nx = ifmap[314];
    9'd315 : pixel_ps1_nx = ifmap[315];
    9'd316 : pixel_ps1_nx = ifmap[316];
    9'd317 : pixel_ps1_nx = ifmap[317];
    9'd318 : pixel_ps1_nx = ifmap[318];
    9'd319 : pixel_ps1_nx = ifmap[319];
    9'd320 : pixel_ps1_nx = ifmap[320];
    9'd321 : pixel_ps1_nx = ifmap[321];
    9'd322 : pixel_ps1_nx = ifmap[322];
    9'd323 : pixel_ps1_nx = ifmap[323];
    9'd324 : pixel_ps1_nx = ifmap[324];
    9'd325 : pixel_ps1_nx = ifmap[325];
    9'd326 : pixel_ps1_nx = ifmap[326];
    9'd327 : pixel_ps1_nx = ifmap[327];
    9'd328 : pixel_ps1_nx = ifmap[328];
    9'd329 : pixel_ps1_nx = ifmap[329];
    9'd330 : pixel_ps1_nx = ifmap[330];
    9'd331 : pixel_ps1_nx = ifmap[331];
    9'd332 : pixel_ps1_nx = ifmap[332];
    9'd333 : pixel_ps1_nx = ifmap[333];
    9'd334 : pixel_ps1_nx = ifmap[334];
    9'd335 : pixel_ps1_nx = ifmap[335];
    9'd336 : pixel_ps1_nx = ifmap[336];
    9'd337 : pixel_ps1_nx = ifmap[337];
    9'd338 : pixel_ps1_nx = ifmap[338];
    9'd339 : pixel_ps1_nx = ifmap[339];
    9'd340 : pixel_ps1_nx = ifmap[340];
    9'd341 : pixel_ps1_nx = ifmap[341];
    9'd342 : pixel_ps1_nx = ifmap[342];
    9'd343 : pixel_ps1_nx = ifmap[343];
    9'd344 : pixel_ps1_nx = ifmap[344];
    9'd345 : pixel_ps1_nx = ifmap[345];
    9'd346 : pixel_ps1_nx = ifmap[346];
    9'd347 : pixel_ps1_nx = ifmap[347];
    9'd348 : pixel_ps1_nx = ifmap[348];
    9'd349 : pixel_ps1_nx = ifmap[349];
    9'd350 : pixel_ps1_nx = ifmap[350];
    9'd351 : pixel_ps1_nx = ifmap[351];
    9'd352 : pixel_ps1_nx = ifmap[352];
    9'd353 : pixel_ps1_nx = ifmap[353];
    9'd354 : pixel_ps1_nx = ifmap[354];
    9'd355 : pixel_ps1_nx = ifmap[355];
    9'd356 : pixel_ps1_nx = ifmap[356];
    9'd357 : pixel_ps1_nx = ifmap[357];
    9'd358 : pixel_ps1_nx = ifmap[358];
    9'd359 : pixel_ps1_nx = ifmap[359];
    9'd360 : pixel_ps1_nx = ifmap[360];
    9'd361 : pixel_ps1_nx = ifmap[361];
    9'd362 : pixel_ps1_nx = ifmap[362];
    9'd363 : pixel_ps1_nx = ifmap[363];
    9'd364 : pixel_ps1_nx = ifmap[364];
    9'd365 : pixel_ps1_nx = ifmap[365];
    9'd366 : pixel_ps1_nx = ifmap[366];
    9'd367 : pixel_ps1_nx = ifmap[367];
    9'd368 : pixel_ps1_nx = ifmap[368];
    9'd369 : pixel_ps1_nx = ifmap[369];
    9'd370 : pixel_ps1_nx = ifmap[370];
    9'd371 : pixel_ps1_nx = ifmap[371];
    9'd372 : pixel_ps1_nx = ifmap[372];
    9'd373 : pixel_ps1_nx = ifmap[373];
    9'd374 : pixel_ps1_nx = ifmap[374];
    9'd375 : pixel_ps1_nx = ifmap[375];
    9'd376 : pixel_ps1_nx = ifmap[376];
    9'd377 : pixel_ps1_nx = ifmap[377];
    9'd378 : pixel_ps1_nx = ifmap[378];
    9'd379 : pixel_ps1_nx = ifmap[379];
    9'd380 : pixel_ps1_nx = ifmap[380];
    9'd381 : pixel_ps1_nx = ifmap[381];
    9'd382 : pixel_ps1_nx = ifmap[382];
    9'd383 : pixel_ps1_nx = ifmap[383];
    9'd384 : pixel_ps1_nx = ifmap[384];
    9'd385 : pixel_ps1_nx = ifmap[385];
    9'd386 : pixel_ps1_nx = ifmap[386];
    9'd387 : pixel_ps1_nx = ifmap[387];
    9'd388 : pixel_ps1_nx = ifmap[388];
    9'd389 : pixel_ps1_nx = ifmap[389];
    9'd390 : pixel_ps1_nx = ifmap[390];
    9'd391 : pixel_ps1_nx = ifmap[391];
    9'd392 : pixel_ps1_nx = ifmap[392];
    9'd393 : pixel_ps1_nx = ifmap[393];
    9'd394 : pixel_ps1_nx = ifmap[394];
    9'd395 : pixel_ps1_nx = ifmap[395];
    9'd396 : pixel_ps1_nx = ifmap[396];
    9'd397 : pixel_ps1_nx = ifmap[397];
    9'd398 : pixel_ps1_nx = ifmap[398];
    9'd399 : pixel_ps1_nx = ifmap[399];
    default : pixel_ps1_nx = 0;
  endcase
end
/* multiply */
always@(*) begin
  //prod1 = wt1 * ifmap[cnt_wt1_ff[1]];
  //prod1 = wt1 * pixel_ps1;
  prod1 = wt1 * ifmap[0];
  prod1_roff = prod1 >>> 16;
  //prod2 = wt2 * ofmap_tmp[cnt_wt2_ff[1]];
  //prod2 = wt2 * pixel_ps2;
  prod2 = wt2 * ofmap_tmp[0];
  prod2_roff = prod2 >>> 16;
end

/* accumulate */
always @(posedge clk) begin
  if (~srstn) begin
    mac1 <= 0;
    mac2 <= 0;
  end
  else begin
    mac1 <= mac1_nx;
    mac2 <= mac2_nx;
  end
end

assign mac1_bs = mac1 + bs1;
assign mac1_relu = (mac1_bs[DATA_WIDTH-1]) ? 0 : mac1_bs;
always @(*) begin
  case ({valid_bs1, valid_prod1})
    2'b00:    mac1_nx = mac1;
    2'b01:    mac1_nx = mac1 + prod1_roff;
    default:  mac1_nx = 0;
  endcase
end

assign mac2_bs = mac2 + bs2;
assign mac2_relu = (mac2_bs[DATA_WIDTH-1]) ? 0 : mac2_bs;
always @(*) begin
  case ({valid_bs2, valid_prod2})
    2'b00:    mac2_nx = mac2;
    2'b01:    mac2_nx = mac2 + prod2_roff;
    default:  mac2_nx = 0;
  endcase
end

always @(posedge clk) begin
  if (~srstn) begin
    cnt_ifmap_x <= 0;
    cnt_ifmap_y <= 0;
    cnt_ifmap_z <= 0;
  end
  else begin
    cnt_ifmap_x <= cnt_ifmap_x_nx;
    cnt_ifmap_y <= cnt_ifmap_y_nx;
    cnt_ifmap_z <= cnt_ifmap_z_nx;
  end
end

always @(*) begin // counter to record the x-axis of currently loading ifmap
  case ({state[IDX_LD_IFMAP], ifmap_x_last}) // synopsys parallel_case
    2'b10   : cnt_ifmap_x_nx = cnt_ifmap_x + 1;
    2'b11   : cnt_ifmap_x_nx = 0;
    default : cnt_ifmap_x_nx = cnt_ifmap_x;
  endcase
end

always @(*) begin // counter to record the y-axis of currently loading ifmap
  case ({state[IDX_LD_IFMAP], ifmap_x_last, ifmap_y_last}) // synopsys parallel_case
    3'b100   : cnt_ifmap_y_nx = cnt_ifmap_y;
    3'b101   : cnt_ifmap_y_nx = cnt_ifmap_y;
    3'b110   : cnt_ifmap_y_nx = cnt_ifmap_y + 1;
    default : cnt_ifmap_y_nx = 0;
  endcase
end

always @(*) begin // counter to record the z-axis of currently loading ifmap
  case ({state[IDX_LD_IFMAP], ifmap_x_last, ifmap_y_last}) // synopsys parallel_case
    3'b100   : cnt_ifmap_z_nx = cnt_ifmap_z;
    3'b101   : cnt_ifmap_z_nx = cnt_ifmap_z;
    3'b110   : cnt_ifmap_z_nx = cnt_ifmap_z;
    3'b111   : cnt_ifmap_z_nx = cnt_ifmap_z + 4'd1;
    default : cnt_ifmap_z_nx = 0;
  endcase
end

always@(posedge clk) begin
  if (~srstn) begin
    cnt_wt1 <= 0;
    cnt_bs1 <= 0;
    cnt_wt2 <= 0;
    cnt_bs2 <= 0;
  end
  else begin
    cnt_wt1 <= cnt_wt1_nx;
    cnt_bs1 <= cnt_bs1_nx;
    cnt_wt2 <= cnt_wt2_nx;
    cnt_bs2 <= cnt_bs2_nx;
  end
end

always @(*) begin // counter to record how many weights have been loaded in phase 1
  case ({state[IDX_MAC_PS1], wt1_last}) // synopsys parallel_case
    2'b10   : cnt_wt1_nx = cnt_wt1 + 1;
    2'b11   : cnt_wt1_nx = 0;
    default : cnt_wt1_nx = cnt_wt1;
  endcase
end

always @(*) begin // counter to record how many biases have been loaded in phase 1
  case ({state[IDX_BIAS_PS1], bs1_last}) // synopsys parallel_case
    2'b10   : cnt_bs1_nx = cnt_bs1 + 1;
    2'b11   : cnt_bs1_nx = 0;
    default : cnt_bs1_nx = cnt_bs1;
  endcase
end

always @(*) begin // counter to record how many weights have been loaded in phase 2
  case ({state[IDX_MAC_PS2], wt2_last}) // synopsys parallel_case
    2'b10   : cnt_wt2_nx = cnt_wt2 + 1;
    2'b11   : cnt_wt2_nx = 0;
    default : cnt_wt2_nx = cnt_wt2;
  endcase
end

always @(*) begin // counter to record how many biases have been loaded in phase 2
  case ({state[IDX_BIAS_PS2], bs2_last}) // synopsys parallel_case
    2'b10   : cnt_bs2_nx = cnt_bs2 + 1;
    2'b11   : cnt_bs2_nx = 0;
    default : cnt_bs2_nx = cnt_bs2;
  endcase
end

endmodule
