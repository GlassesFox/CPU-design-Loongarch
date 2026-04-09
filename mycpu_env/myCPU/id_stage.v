module id_stage(
    input  wire        clk,
    input  wire        reset,

    // from IF stage
    input  wire [31:0] IF_ID_pc,
    input  wire [31:0] IF_ID_inst,
    input  wire        IF_ID_valid,

    // from EX stage
    input  wire        div_stall,
    input  wire        ex_exc_order_stall,
    input  wire        ex_ale_redirect,
    input  wire [31:0] ex_forward_value,
    input  wire        ex_forward_valid,

    // from MEM stage
    input  wire [31:0] mem_forward_value,
    input  wire        mem_forward_valid,

    // from EX/MEM pipeline (for hazards)
    input  wire [ 4:0] EX_MEM_dest,
    input  wire        EX_MEM_gr_we,
    input  wire        EX_MEM_valid,
    input  wire        EX_MEM_csrrd,
    input  wire        EX_MEM_csr_we,
    input  wire [13:0] EX_MEM_csr_num,

    // from MEM/WB pipeline (for hazards)
    input  wire        MEM_WB_valid,
    input  wire        MEM_WB_csr_we,
    input  wire [13:0] MEM_WB_csr_num,

    // from WB stage / CSR
    input  wire        csr_has_int,
    input  wire [31:0] csr_rvalue2,

    // regfile writeback from WB
    input  wire        rf_we_commit,
    input  wire [ 4:0] rf_waddr,
    input  wire [31:0] rf_wdata,

    // to IF stage
    output wire        pipeline_stall,
    output wire        br_taken,
    output wire [31:0] br_target,

    // to WB stage
    output wire [13:0] csr_num2,

    // ID/EX pipeline registers outputs
    output reg  [31:0] ID_EX_pc,
    output reg  [14:0] ID_EX_alu_op,
    output reg         ID_EX_src1_is_pc,
    output reg         ID_EX_src2_is_imm,
    output reg  [ 1:0] ID_EX_store_size,
    output reg  [ 1:0] ID_EX_load_size,
    output reg         ID_EX_load_unsigned,
    output reg         ID_EX_div_en,
    output reg         ID_EX_div_signed,
    output reg         ID_EX_div_mod,
    output reg         ID_EX_res_from_mem,
    output reg         ID_EX_gr_we,
    output reg         ID_EX_mem_we,
    output reg  [ 4:0] ID_EX_dest,
    output reg  [31:0] ID_EX_rj_value,
    output reg  [31:0] ID_EX_rkd_value,
    output reg  [31:0] ID_EX_imm,
    output reg         ID_EX_csrrd,
    output reg         ID_EX_ertn,
    output reg         ID_EX_syscall,
    output reg         ID_EX_break,
    output reg         ID_EX_ine,
    output reg         ID_EX_adef,
    output reg         ID_EX_rdtimel,
    output reg         ID_EX_rdtimeh,
    output reg         ID_EX_rdtime_write_tid,
    output reg         ID_EX_int,
    output reg  [13:0] ID_EX_csr_num,
    output reg         ID_EX_csr_we,
    output reg  [31:0] ID_EX_csr_wmask,
    output reg  [31:0] ID_EX_csr_wvalue,
    output reg         ID_EX_valid
);

// interrupt redirect suppression (avoid repeated redirect before CRMD.IE is cleared on exception entry)
reg         int_redirect_inflight;

wire [31:0] inst;

// ID stage uses IF/ID registers
wire inst_adef;
assign inst_adef = IF_ID_valid && (IF_ID_pc[1:0] != 2'b00);
wire [31:0] inst_for_decode = inst_adef ? 32'b0 : IF_ID_inst;
assign inst = inst_for_decode;

// ========== ID Stage decode ==========
wire [ 5:0] op_31_26;
wire [ 3:0] op_25_22;
wire [ 1:0] op_21_20;
wire [ 4:0] op_19_15;
wire [ 4:0] rd;
wire [ 4:0] rj;
wire [ 4:0] rk;
wire [11:0] i12;
wire [19:0] i20;
wire [15:0] i16;
wire [25:0] i26;
wire [13:0] csr_num;

assign op_31_26  = inst[31:26];
assign op_25_22  = inst[25:22];
assign op_21_20  = inst[21:20];
assign op_19_15  = inst[19:15];

assign rd   = inst[ 4: 0];
assign rj   = inst[ 9: 5];
assign rk   = inst[14:10];

assign i12  = inst[21:10];
assign i20  = inst[24: 5];
assign i16  = inst[25:10];
assign i26  = {inst[ 9: 0], inst[25:10]};
assign csr_num = inst[23:10];

wire [63:0] op_31_26_d;
wire [15:0] op_25_22_d;
wire [ 3:0] op_21_20_d;
wire [31:0] op_19_15_d;

decoder_6_64 u_dec0(.in(op_31_26 ), .out(op_31_26_d ));
decoder_4_16 u_dec1(.in(op_25_22 ), .out(op_25_22_d ));
decoder_2_4  u_dec2(.in(op_21_20 ), .out(op_21_20_d ));
decoder_5_32 u_dec3(.in(op_19_15 ), .out(op_19_15_d ));

wire        inst_add_w;
wire        inst_sub_w;
wire        inst_slt;
wire        inst_sltu;
wire        inst_nor;
wire        inst_and;
wire        inst_or;
wire        inst_xor;
wire        inst_slli_w;
wire        inst_srli_w;
wire        inst_srai_w;
wire        inst_sll_w;
wire        inst_srl_w;
wire        inst_sra_w;
wire        inst_mul_w;
wire        inst_mulh_w;
wire        inst_mulh_wu;
wire        inst_div_w;
wire        inst_mod_w;
wire        inst_div_wu;
wire        inst_mod_wu;
wire        inst_addi_w;
wire        inst_slti;
wire        inst_sltui;
wire        inst_andi;
wire        inst_ori;
wire        inst_xori;
wire        inst_ld_b;
wire        inst_ld_h;
wire        inst_ld_w;
wire        inst_ld_bu;
wire        inst_ld_hu;
wire        inst_st_b;
wire        inst_st_h;
wire        inst_st_w;
wire        inst_jirl;
wire        inst_b;
wire        inst_bl;
wire        inst_beq;
wire        inst_bne;
wire        inst_blt;
wire        inst_bge;
wire        inst_bltu;
wire        inst_bgeu;
wire        inst_lu12i_w;
wire        inst_pcaddu12i;

wire        inst_csrrd;
wire        inst_csrwr;
wire        inst_csrxchg;
wire        inst_ertn;
wire        inst_syscall;
wire        inst_break;
wire        inst_rdtimel_w;
wire        inst_rdtimeh_w;
wire        inst_ine;

assign inst_add_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h00];
assign inst_sub_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h02];
assign inst_slt    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h04];
assign inst_sltu   = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h05];
assign inst_nor    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h08];
assign inst_and    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h09];
assign inst_or     = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0a];
assign inst_xor    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0b];
assign inst_slli_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h01];
assign inst_srli_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h09];
assign inst_srai_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h11];
assign inst_sll_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0e];
assign inst_srl_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0f];
assign inst_sra_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h10];
assign inst_mul_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h18];
assign inst_mulh_w = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h19];
assign inst_mulh_wu= op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h1a];
assign inst_div_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h00];
assign inst_mod_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h01];
assign inst_div_wu = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h02];
assign inst_mod_wu = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h03];
assign inst_addi_w = op_31_26_d[6'h00] & op_25_22_d[4'ha];
assign inst_slti   = op_31_26_d[6'h00] & op_25_22_d[4'h8];
assign inst_sltui  = op_31_26_d[6'h00] & op_25_22_d[4'h9];
assign inst_andi   = op_31_26_d[6'h00] & op_25_22_d[4'hd];
assign inst_ori    = op_31_26_d[6'h00] & op_25_22_d[4'he];
assign inst_xori   = op_31_26_d[6'h00] & op_25_22_d[4'hf];
assign inst_ld_b   = op_31_26_d[6'h0a] & op_25_22_d[4'h0];
assign inst_ld_h   = op_31_26_d[6'h0a] & op_25_22_d[4'h1];
assign inst_ld_w   = op_31_26_d[6'h0a] & op_25_22_d[4'h2];
assign inst_ld_bu  = op_31_26_d[6'h0a] & op_25_22_d[4'h8];
assign inst_ld_hu  = op_31_26_d[6'h0a] & op_25_22_d[4'h9];
assign inst_st_b   = op_31_26_d[6'h0a] & op_25_22_d[4'h4];
assign inst_st_h   = op_31_26_d[6'h0a] & op_25_22_d[4'h5];
assign inst_st_w   = op_31_26_d[6'h0a] & op_25_22_d[4'h6];
assign inst_jirl   = op_31_26_d[6'h13];
assign inst_b      = op_31_26_d[6'h14];
assign inst_bl     = op_31_26_d[6'h15];
assign inst_beq    = op_31_26_d[6'h16];
assign inst_bne    = op_31_26_d[6'h17];
assign inst_blt    = op_31_26_d[6'h18];
assign inst_bge    = op_31_26_d[6'h19];
assign inst_bltu   = op_31_26_d[6'h1a];
assign inst_bgeu   = op_31_26_d[6'h1b];
assign inst_lu12i_w= op_31_26_d[6'h05] & ~inst[25];
assign inst_pcaddu12i = op_31_26_d[6'h07];

// CSR instruction (LoongArch32): CSRRD rd, csr_num
assign inst_csrrd = (inst[31:26] == 6'h01) && (inst[25:24] == 2'b00) && (inst[9:5] == 5'b00000);
assign inst_csrwr  = (inst[31:26] == 6'h01) && (inst[25:24] == 2'b00) && (inst[9:5] == 5'b00001);
assign inst_csrxchg = (inst[31:26] == 6'h01) && (inst[25:24] == 2'b00) && (inst[9:5] != 5'b00000) && (inst[9:5] != 5'b00001);

assign inst_ertn = (inst == 32'h0648_3800);
assign inst_syscall = (inst[31:15] == 17'h00056);
assign inst_break   = (inst[31:15] == 17'h00054);
assign inst_rdtimel_w = (inst[31:10] == 22'h000018);
assign inst_rdtimeh_w = (inst[31:10] == 22'h000019);

wire inst_known;
assign inst_known = inst_add_w | inst_sub_w | inst_slt | inst_sltu | inst_nor | inst_and | inst_or | inst_xor
                  | inst_slli_w | inst_srli_w | inst_srai_w | inst_sll_w | inst_srl_w | inst_sra_w
                  | inst_mul_w | inst_mulh_w | inst_mulh_wu | inst_div_w | inst_mod_w | inst_div_wu | inst_mod_wu
                  | inst_addi_w | inst_slti | inst_sltui | inst_andi | inst_ori | inst_xori
                  | inst_ld_b | inst_ld_h | inst_ld_w | inst_ld_bu | inst_ld_hu
                  | inst_st_b | inst_st_h | inst_st_w
                  | inst_jirl | inst_b | inst_bl | inst_beq | inst_bne | inst_blt | inst_bge | inst_bltu | inst_bgeu
                  | inst_lu12i_w | inst_pcaddu12i
                  | inst_csrrd | inst_csrwr | inst_csrxchg | inst_ertn | inst_syscall | inst_break
                  | inst_rdtimel_w | inst_rdtimeh_w;
assign inst_ine = IF_ID_valid && !inst_adef && !inst_known;

// ALU op encoding
wire [14:0] alu_op;
assign alu_op[ 0] = inst_add_w | inst_addi_w | inst_ld_b | inst_ld_h | inst_ld_w | inst_ld_bu | inst_ld_hu | inst_st_b | inst_st_h | inst_st_w
                    | inst_jirl | inst_bl | inst_pcaddu12i;
assign alu_op[ 1] = inst_sub_w;
assign alu_op[ 2] = inst_slt  | inst_slti;
assign alu_op[ 3] = inst_sltu | inst_sltui;
assign alu_op[ 4] = inst_and  | inst_andi;
assign alu_op[ 5] = inst_nor;
assign alu_op[ 6] = inst_or   | inst_ori;
assign alu_op[ 7] = inst_xor  | inst_xori;
assign alu_op[ 8] = inst_slli_w | inst_sll_w;
assign alu_op[ 9] = inst_srli_w | inst_srl_w;
assign alu_op[10] = inst_srai_w | inst_sra_w;
assign alu_op[11] = inst_lu12i_w;
assign alu_op[12] = inst_mul_w;
assign alu_op[13] = inst_mulh_w;
assign alu_op[14] = inst_mulh_wu;

wire div_op;
wire div_signed;
wire div_mod;
assign div_op     = inst_div_w | inst_mod_w | inst_div_wu | inst_mod_wu;
assign div_signed = inst_div_w | inst_mod_w;
assign div_mod    = inst_mod_w | inst_mod_wu;

wire        need_ui5;
wire        need_ui12;
wire        need_si12;
wire        need_si16;
wire        need_si20;
wire        need_si20_pcaddu12i;
wire        need_si26;
wire        src2_is_4;

assign need_ui5   =  inst_slli_w | inst_srli_w | inst_srai_w;
assign need_ui12  =  inst_andi | inst_ori | inst_xori;
assign need_si12  =  inst_addi_w | inst_ld_b | inst_ld_h | inst_ld_w | inst_ld_bu | inst_ld_hu | inst_st_b | inst_st_h | inst_st_w | inst_slti | inst_sltui;
assign need_si16  =  inst_jirl | inst_beq | inst_bne;
assign need_si20  =  inst_lu12i_w;
assign need_si20_pcaddu12i = inst_pcaddu12i;
assign need_si26  =  inst_b | inst_bl;
assign src2_is_4  =  inst_jirl | inst_bl;

wire [31:0] pcaddu12i_imm;
assign pcaddu12i_imm = ({{12{i20[19]}}, i20[19:0]} << 12);

wire [31:0] imm;
assign imm = src2_is_4 ? 32'h4                      :
             need_si20_pcaddu12i ? pcaddu12i_imm     :
             need_si20 ? {i20[19:0], 12'b0}          :
             need_ui5  ? {27'b0, i12[4:0]}           :
             need_ui12 ? {20'b0, i12[11:0]}          :
         /*need_si12*/   {{20{i12[11]}}, i12[11:0]}  ;

wire [31:0] br_offs;
assign br_offs = need_si26 ? {{ 4{i26[25]}}, i26[25:0], 2'b0} :
                             {{14{i16[15]}}, i16[15:0], 2'b0} ;

wire [31:0] jirl_offs;
assign jirl_offs = {{14{i16[15]}}, i16[15:0], 2'b0};

wire src_reg_is_rd;
assign src_reg_is_rd = inst_beq | inst_bne | inst_blt | inst_bge | inst_bltu | inst_bgeu | inst_st_b | inst_st_h | inst_st_w
                     | inst_csrwr | inst_csrxchg;

wire src1_is_pc;
assign src1_is_pc    = inst_jirl | inst_bl | inst_pcaddu12i;

wire src2_is_imm;
assign src2_is_imm   = inst_slli_w |
                       inst_srli_w |
                       inst_srai_w |
                       inst_addi_w |
                       inst_slti   |
                       inst_sltui  |
                       inst_andi   |
                       inst_ori    |
                       inst_xori   |
                       inst_ld_b   |
                       inst_ld_h   |
                       inst_ld_w   |
                       inst_ld_bu  |
                       inst_ld_hu  |
                       inst_st_b   |
                       inst_st_h   |
                       inst_st_w   |
                       inst_lu12i_w|
                       inst_pcaddu12i|
                       inst_jirl   |
                       inst_bl     ;

wire res_from_mem;
assign res_from_mem  = inst_ld_b | inst_ld_h | inst_ld_w | inst_ld_bu | inst_ld_hu;

wire dst_is_r1;
assign dst_is_r1     = inst_bl;

wire gr_we_normal;
assign gr_we_normal  = ~inst_st_b & ~inst_st_h & ~inst_st_w & ~inst_beq & ~inst_bne & ~inst_blt & ~inst_bge & ~inst_bltu & ~inst_bgeu & ~inst_b
                     & ~inst_ertn & ~inst_syscall & ~inst_break & ~inst_ine & ~inst_adef;

wire mem_we;
assign mem_we        = inst_st_b | inst_st_h | inst_st_w;

wire [4:0] dest_normal;
assign dest_normal = dst_is_r1 ? 5'd1 : rd;

wire rdtime_has_dest;
assign rdtime_has_dest = (inst_rdtimel_w || inst_rdtimeh_w) && ((rd != 5'd0) || (rj != 5'd0));
wire [4:0] rdtime_dest;
assign rdtime_dest = (rd != 5'd0) ? rd : rj;

wire gr_we;
wire [4:0] dest;
assign gr_we         = (inst_rdtimel_w || inst_rdtimeh_w) ? rdtime_has_dest : gr_we_normal;
assign dest          = (inst_rdtimel_w || inst_rdtimeh_w) ? rdtime_dest     : dest_normal;

// Regfile
wire [ 4:0] rf_raddr1;
wire [31:0] rf_rdata1;
wire [ 4:0] rf_raddr2;
wire [31:0] rf_rdata2;

assign rf_raddr1 = rj;
assign rf_raddr2 = src_reg_is_rd ? rd : rk;

regfile u_regfile(
    .clk    (clk      ),
    .raddr1 (rf_raddr1),
    .rdata1 (rf_rdata1),
    .raddr2 (rf_raddr2),
    .rdata2 (rf_rdata2),
    .we     (rf_we_commit),
    .waddr  (rf_waddr ),
    .wdata  (rf_wdata )
);

// ========== Operand Forwarding (Bypass) ==========
wire        wb_forward_valid;
wire [31:0] wb_forward_value;
assign wb_forward_valid  = rf_we_commit && (rf_waddr != 5'b0);
assign wb_forward_value  = rf_wdata;

wire r1_from_ex;
wire r1_from_mem;
wire r1_from_wb;
assign r1_from_ex  = ex_forward_valid  && (rf_raddr1 == ID_EX_dest);
assign r1_from_mem = mem_forward_valid && (rf_raddr1 == EX_MEM_dest);
assign r1_from_wb  = wb_forward_valid  && (rf_raddr1 == rf_waddr);

wire [31:0] rj_value;
assign rj_value  = (rf_raddr1 == 5'b0) ? 32'b0 :
                   r1_from_ex  ? ex_forward_value  :
                   r1_from_mem ? mem_forward_value :
                   r1_from_wb  ? wb_forward_value  :
                                 rf_rdata1;

wire r2_from_ex;
wire r2_from_mem;
wire r2_from_wb;
assign r2_from_ex  = ex_forward_valid  && (rf_raddr2 == ID_EX_dest);
assign r2_from_mem = mem_forward_valid && (rf_raddr2 == EX_MEM_dest);
assign r2_from_wb  = wb_forward_valid  && (rf_raddr2 == rf_waddr);

wire [31:0] rkd_value;
assign rkd_value = (rf_raddr2 == 5'b0) ? 32'b0 :
                   r2_from_ex  ? ex_forward_value  :
                   r2_from_mem ? mem_forward_value :
                   r2_from_wb  ? wb_forward_value  :
                                 rf_rdata2;

// Branch decision in ID stage
wire rj_eq_rd;
wire rj_lt_rd_s;
wire rj_ge_rd_s;
wire rj_lt_rd_u;
wire rj_ge_rd_u;
assign rj_eq_rd = (rj_value == rkd_value);
assign rj_lt_rd_s  = ($signed(rj_value) <  $signed(rkd_value));
assign rj_ge_rd_s  = ($signed(rj_value) >= $signed(rkd_value));
assign rj_lt_rd_u  = (rj_value <  rkd_value);
assign rj_ge_rd_u  = (rj_value >= rkd_value);

// Take interrupt in ID stage as a branch-like redirect to EENTRY.
wire id_is_exc_inst;
assign id_is_exc_inst = inst_syscall || inst_break || inst_ine || inst_adef;
wire id_take_int;
assign id_take_int = csr_has_int
                                 && IF_ID_valid
                                 && !pipeline_stall
                                 && !ex_ale_redirect
                                 && !int_redirect_inflight
                                 && !(inst_ertn || inst_syscall || inst_break || inst_ine || inst_adef);

// Latch that we have already redirected to EENTRY for the current pending interrupt.
always @(posedge clk) begin
    if (reset) begin
        int_redirect_inflight <= 1'b0;
    end
    else if (!csr_has_int) begin
        int_redirect_inflight <= 1'b0;
    end
    else if (id_take_int) begin
        int_redirect_inflight <= 1'b1;
    end
end

assign br_taken = (   inst_beq  &&  rj_eq_rd
                   || inst_bne  && !rj_eq_rd
                   || inst_blt  &&  rj_lt_rd_s
                   || inst_bge  &&  rj_ge_rd_s
                   || inst_bltu &&  rj_lt_rd_u
                   || inst_bgeu &&  rj_ge_rd_u
                   || inst_jirl
                   || inst_bl
                   || inst_b
                   || inst_ertn
                   || inst_syscall
                   || inst_break
                   || inst_ine
                   || inst_adef
                   || id_take_int
                  ) && IF_ID_valid && !pipeline_stall;

assign br_target = (inst_ertn || inst_syscall || inst_break || inst_ine || inst_adef || id_take_int) ? csr_rvalue2 :
                   ((inst_beq || inst_bne || inst_blt || inst_bge || inst_bltu || inst_bgeu || inst_bl || inst_b) ? (IF_ID_pc + br_offs) :
                                                   /*inst_jirl*/ (rj_value + jirl_offs));

// ========== Hazard Detection (Stall) ==========
wire id_need_r1;
wire id_need_r2;
assign id_need_r1 = ~inst_b & ~inst_bl & ~inst_lu12i_w & ~inst_pcaddu12i & ~inst_csrrd & ~inst_csrwr
               & ~inst_ertn & ~inst_syscall & ~inst_break
               & ~inst_rdtimel_w & ~inst_rdtimeh_w
               & ~inst_ine & ~inst_adef;

assign id_need_r2 = inst_add_w | inst_sub_w | inst_slt | inst_sltu
                | inst_nor  | inst_and   | inst_or  | inst_xor
                | inst_sll_w | inst_srl_w | inst_sra_w
                | inst_mul_w | inst_mulh_w | inst_mulh_wu
                | inst_div_w | inst_mod_w | inst_div_wu | inst_mod_wu
                | inst_beq  | inst_bne   | inst_blt | inst_bge | inst_bltu | inst_bgeu | inst_st_b | inst_st_h | inst_st_w
                | inst_csrwr | inst_csrxchg;

// Pipeline stall: with forwarding enabled, only stall for load-use hazard when the load is in EX stage.
wire load_use_hazard;
assign load_use_hazard = ID_EX_valid && ID_EX_res_from_mem && ID_EX_gr_we && (ID_EX_dest != 5'b0) &&
                       ((id_need_r1 && (rf_raddr1 == ID_EX_dest)) || (id_need_r2 && (rf_raddr2 == ID_EX_dest)));
wire load_use_stall;
assign load_use_stall = IF_ID_valid && load_use_hazard;

// ========== CSR Hazard Handling (Stall) ==========
localparam [13:0] CSR_PRMD_NUM = 14'h0001;
localparam [13:0] CSR_ERA_NUM  = 14'h0006;
localparam [13:0] CSR_CRMD_NUM = 14'h0000;
localparam [13:0] CSR_ESTAT_NUM= 14'h0005;

wire ex_writes_era_prmd;
wire mem_writes_era_prmd;
wire wb_writes_era_prmd;
assign ex_writes_era_prmd  = ID_EX_valid  && ID_EX_csr_we  && ((ID_EX_csr_num  == CSR_ERA_NUM) || (ID_EX_csr_num  == CSR_PRMD_NUM));
assign mem_writes_era_prmd = EX_MEM_valid && EX_MEM_csr_we && ((EX_MEM_csr_num == CSR_ERA_NUM) || (EX_MEM_csr_num == CSR_PRMD_NUM));
assign wb_writes_era_prmd  = MEM_WB_valid && MEM_WB_csr_we && ((MEM_WB_csr_num == CSR_ERA_NUM) || (MEM_WB_csr_num == CSR_PRMD_NUM));
wire ertn_csr_stall;
assign ertn_csr_stall = IF_ID_valid && inst_ertn && (ex_writes_era_prmd || mem_writes_era_prmd || wb_writes_era_prmd);

wire ex_writes_exc_csrs;
wire mem_writes_exc_csrs;
wire wb_writes_exc_csrs;
assign ex_writes_exc_csrs  = ID_EX_valid  && ID_EX_csr_we  && ((ID_EX_csr_num  == CSR_CRMD_NUM) || (ID_EX_csr_num  == CSR_PRMD_NUM) || (ID_EX_csr_num  == CSR_ESTAT_NUM) || (ID_EX_csr_num  == CSR_ERA_NUM));
assign mem_writes_exc_csrs = EX_MEM_valid && EX_MEM_csr_we && ((EX_MEM_csr_num == CSR_CRMD_NUM) || (EX_MEM_csr_num == CSR_PRMD_NUM) || (EX_MEM_csr_num == CSR_ESTAT_NUM) || (EX_MEM_csr_num == CSR_ERA_NUM));
assign wb_writes_exc_csrs  = MEM_WB_valid && MEM_WB_csr_we && ((MEM_WB_csr_num == CSR_CRMD_NUM) || (MEM_WB_csr_num == CSR_PRMD_NUM) || (MEM_WB_csr_num == CSR_ESTAT_NUM) || (MEM_WB_csr_num == CSR_ERA_NUM));
wire exc_csr_stall;
assign exc_csr_stall = IF_ID_valid && id_is_exc_inst && (ex_writes_exc_csrs || mem_writes_exc_csrs || wb_writes_exc_csrs);

wire id_would_take_int;
assign id_would_take_int = csr_has_int
                      && IF_ID_valid
                      && !ex_ale_redirect
                      && !int_redirect_inflight
                      && !inst_ertn
                      && !id_is_exc_inst;
wire int_csr_stall;
assign int_csr_stall = id_would_take_int && (ex_writes_exc_csrs || mem_writes_exc_csrs || wb_writes_exc_csrs);

wire ex_is_csr;
wire mem_is_csr;
assign ex_is_csr  = ID_EX_valid  && (ID_EX_csrrd  || ID_EX_csr_we)  && ID_EX_gr_we  && (ID_EX_dest  != 5'b0);
assign mem_is_csr = EX_MEM_valid && (EX_MEM_csrrd || EX_MEM_csr_we) && EX_MEM_gr_we && (EX_MEM_dest != 5'b0);

wire csr_data_hazard;
assign csr_data_hazard = IF_ID_valid && (
    (id_need_r1 && (rf_raddr1 != 5'b0) && ((ex_is_csr  && (rf_raddr1 == ID_EX_dest )) || (mem_is_csr && (rf_raddr1 == EX_MEM_dest)))) ||
    (id_need_r2 && (rf_raddr2 != 5'b0) && ((ex_is_csr  && (rf_raddr2 == ID_EX_dest )) || (mem_is_csr && (rf_raddr2 == EX_MEM_dest))))
);

wire id_bubble_stall;
assign id_bubble_stall = load_use_stall || ertn_csr_stall || exc_csr_stall || int_csr_stall || csr_data_hazard;
assign pipeline_stall = id_bubble_stall || div_stall || ex_exc_order_stall;
wire ex_hold_stall;
assign ex_hold_stall  = div_stall || ex_exc_order_stall;

// csr_num2 selection: EXC/INT->CSR.EENTRY, ERTN->CSR.ERA
assign csr_num2 = (inst_syscall || inst_break || inst_ine || inst_adef || ex_ale_redirect || id_take_int) ? 14'h000c : 14'h0006;

// ID/EX pipeline register update
always @(posedge clk) begin
    if (reset) begin
        ID_EX_pc           <= 32'b0;
        ID_EX_alu_op       <= 15'b0;
        ID_EX_src1_is_pc   <= 1'b0;
        ID_EX_src2_is_imm  <= 1'b0;
        ID_EX_store_size   <= 2'b10;
        ID_EX_load_size    <= 2'b10;
        ID_EX_load_unsigned<= 1'b0;
        ID_EX_div_en       <= 1'b0;
        ID_EX_div_signed   <= 1'b0;
        ID_EX_div_mod      <= 1'b0;
        ID_EX_res_from_mem <= 1'b0;
        ID_EX_gr_we        <= 1'b0;
        ID_EX_mem_we       <= 1'b0;
        ID_EX_dest         <= 5'b0;
        ID_EX_rj_value     <= 32'b0;
        ID_EX_rkd_value    <= 32'b0;
        ID_EX_imm          <= 32'b0;
        ID_EX_csrrd        <= 1'b0;
        ID_EX_ertn         <= 1'b0;
        ID_EX_syscall      <= 1'b0;
        ID_EX_break        <= 1'b0;
        ID_EX_ine          <= 1'b0;
        ID_EX_adef         <= 1'b0;
        ID_EX_rdtimel      <= 1'b0;
        ID_EX_rdtimeh      <= 1'b0;
        ID_EX_rdtime_write_tid <= 1'b0;
        ID_EX_int          <= 1'b0;
        ID_EX_csr_num      <= 14'b0;
        ID_EX_csr_we       <= 1'b0;
        ID_EX_csr_wmask    <= 32'b0;
        ID_EX_csr_wvalue   <= 32'b0;
        ID_EX_valid        <= 1'b0;
    end
    else if (ex_ale_redirect) begin
        ID_EX_pc           <= 32'b0;
        ID_EX_alu_op       <= 15'b0;
        ID_EX_src1_is_pc   <= 1'b0;
        ID_EX_src2_is_imm  <= 1'b0;
        ID_EX_store_size   <= 2'b10;
        ID_EX_load_size    <= 2'b10;
        ID_EX_load_unsigned<= 1'b0;
        ID_EX_div_en       <= 1'b0;
        ID_EX_div_signed   <= 1'b0;
        ID_EX_div_mod      <= 1'b0;
        ID_EX_res_from_mem <= 1'b0;
        ID_EX_gr_we        <= 1'b0;
        ID_EX_mem_we       <= 1'b0;
        ID_EX_dest         <= 5'b0;
        ID_EX_rj_value     <= 32'b0;
        ID_EX_rkd_value    <= 32'b0;
        ID_EX_imm          <= 32'b0;
        ID_EX_csrrd        <= 1'b0;
        ID_EX_ertn         <= 1'b0;
        ID_EX_syscall      <= 1'b0;
        ID_EX_break        <= 1'b0;
        ID_EX_ine          <= 1'b0;
        ID_EX_adef         <= 1'b0;
        ID_EX_rdtimel      <= 1'b0;
        ID_EX_rdtimeh      <= 1'b0;
        ID_EX_rdtime_write_tid <= 1'b0;
        ID_EX_int          <= 1'b0;
        ID_EX_csr_num      <= 14'b0;
        ID_EX_csr_we       <= 1'b0;
        ID_EX_csr_wmask    <= 32'b0;
        ID_EX_csr_wvalue   <= 32'b0;
        ID_EX_valid        <= 1'b0;
    end
    else if (id_bubble_stall) begin
        ID_EX_pc           <= 32'b0;
        ID_EX_alu_op       <= 15'b0;
        ID_EX_src1_is_pc   <= 1'b0;
        ID_EX_src2_is_imm  <= 1'b0;
        ID_EX_store_size   <= 2'b10;
        ID_EX_load_size    <= 2'b10;
        ID_EX_load_unsigned<= 1'b0;
        ID_EX_div_en       <= 1'b0;
        ID_EX_div_signed   <= 1'b0;
        ID_EX_div_mod      <= 1'b0;
        ID_EX_res_from_mem <= 1'b0;
        ID_EX_gr_we        <= 1'b0;
        ID_EX_mem_we       <= 1'b0;
        ID_EX_dest         <= 5'b0;
        ID_EX_rj_value     <= 32'b0;
        ID_EX_rkd_value    <= 32'b0;
        ID_EX_imm          <= 32'b0;
        ID_EX_csrrd        <= 1'b0;
        ID_EX_ertn         <= 1'b0;
        ID_EX_syscall      <= 1'b0;
        ID_EX_break        <= 1'b0;
        ID_EX_ine          <= 1'b0;
        ID_EX_adef         <= 1'b0;
        ID_EX_rdtimel      <= 1'b0;
        ID_EX_rdtimeh      <= 1'b0;
        ID_EX_rdtime_write_tid <= 1'b0;
        ID_EX_int          <= 1'b0;
        ID_EX_csr_num      <= 14'b0;
        ID_EX_csr_we       <= 1'b0;
        ID_EX_csr_wmask    <= 32'b0;
        ID_EX_csr_wvalue   <= 32'b0;
        ID_EX_valid        <= 1'b0;
    end
    else if (ex_hold_stall) begin
        // Hold ID/EX registers
    end
    else if (id_take_int) begin
        ID_EX_pc           <= IF_ID_pc;
        ID_EX_alu_op       <= 15'b0;
        ID_EX_src1_is_pc   <= 1'b0;
        ID_EX_src2_is_imm  <= 1'b0;
        ID_EX_store_size   <= 2'b10;
        ID_EX_load_size    <= 2'b10;
        ID_EX_load_unsigned<= 1'b0;
        ID_EX_div_en       <= 1'b0;
        ID_EX_div_signed   <= 1'b0;
        ID_EX_div_mod      <= 1'b0;
        ID_EX_res_from_mem <= 1'b0;
        ID_EX_gr_we        <= 1'b0;
        ID_EX_mem_we       <= 1'b0;
        ID_EX_dest         <= 5'b0;
        ID_EX_rj_value     <= 32'b0;
        ID_EX_rkd_value    <= 32'b0;
        ID_EX_imm          <= 32'b0;
        ID_EX_csrrd        <= 1'b0;
        ID_EX_ertn         <= 1'b0;
        ID_EX_syscall      <= 1'b0;
        ID_EX_break        <= 1'b0;
        ID_EX_ine          <= 1'b0;
        ID_EX_adef         <= 1'b0;
        ID_EX_rdtimel      <= 1'b0;
        ID_EX_rdtimeh      <= 1'b0;
        ID_EX_rdtime_write_tid <= 1'b0;
        ID_EX_int          <= 1'b1;
        ID_EX_csr_num      <= 14'b0;
        ID_EX_csr_we       <= 1'b0;
        ID_EX_csr_wmask    <= 32'b0;
        ID_EX_csr_wvalue   <= 32'b0;
        ID_EX_valid        <= 1'b1;
    end
    else begin
        ID_EX_pc           <= IF_ID_pc;
        ID_EX_alu_op       <= alu_op;
        ID_EX_src1_is_pc   <= src1_is_pc;
        ID_EX_src2_is_imm  <= src2_is_imm;
        ID_EX_store_size   <= inst_st_b ? 2'b00 :
                              inst_st_h ? 2'b01 :
                              2'b10;
        ID_EX_load_size    <= inst_ld_b | inst_ld_bu ? 2'b00 :
                              inst_ld_h | inst_ld_hu ? 2'b01 :
                              2'b10;
        ID_EX_load_unsigned<= inst_ld_bu | inst_ld_hu;
        ID_EX_div_en       <= div_op;
        ID_EX_div_signed   <= div_signed;
        ID_EX_div_mod      <= div_mod;
        ID_EX_res_from_mem <= res_from_mem;
        ID_EX_gr_we        <= gr_we;
        ID_EX_mem_we       <= mem_we;
        ID_EX_dest         <= dest;
        ID_EX_rj_value     <= rj_value;
        ID_EX_rkd_value    <= rkd_value;
        ID_EX_imm          <= imm;
        ID_EX_csrrd        <= inst_csrrd;
        ID_EX_ertn         <= inst_ertn;
        ID_EX_syscall      <= inst_syscall;
        ID_EX_break        <= inst_break;
        ID_EX_ine          <= inst_ine;
        ID_EX_adef         <= inst_adef;
        ID_EX_rdtimel      <= inst_rdtimel_w;
        ID_EX_rdtimeh      <= inst_rdtimeh_w;
        ID_EX_rdtime_write_tid <= (inst_rdtimel_w || inst_rdtimeh_w) && (rd == 5'd0) && (rj != 5'd0);
        ID_EX_int          <= 1'b0;
        ID_EX_csr_num      <= csr_num;
        ID_EX_csr_we       <= inst_csrwr | inst_csrxchg;
        ID_EX_csr_wmask    <= inst_csrwr ? 32'hffff_ffff : rj_value;
        ID_EX_csr_wvalue   <= rkd_value;
        ID_EX_valid        <= IF_ID_valid;
    end
end

endmodule
