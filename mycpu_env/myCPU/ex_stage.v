module ex_stage(
    input  wire        clk,
    input  wire        reset,

    // ID/EX pipeline registers inputs
    input  wire [31:0] ID_EX_pc,
    input  wire [14:0] ID_EX_alu_op,
    input  wire        ID_EX_src1_is_pc,
    input  wire        ID_EX_src2_is_imm,
    input  wire [ 1:0] ID_EX_store_size,
    input  wire [ 1:0] ID_EX_load_size,
    input  wire        ID_EX_load_unsigned,
    input  wire        ID_EX_div_en,
    input  wire        ID_EX_div_signed,
    input  wire        ID_EX_div_mod,
    input  wire        ID_EX_res_from_mem,
    input  wire        ID_EX_gr_we,
    input  wire        ID_EX_mem_we,
    input  wire [ 4:0] ID_EX_dest,
    input  wire [31:0] ID_EX_rj_value,
    input  wire [31:0] ID_EX_rkd_value,
    input  wire [31:0] ID_EX_imm,
    input  wire        ID_EX_csrrd,
    input  wire        ID_EX_ertn,
    input  wire        ID_EX_syscall,
    input  wire        ID_EX_break,
    input  wire        ID_EX_ine,
    input  wire        ID_EX_adef,
    input  wire        ID_EX_rdtimel,
    input  wire        ID_EX_rdtimeh,
    input  wire        ID_EX_rdtime_write_tid,
    input  wire        ID_EX_int,
    input  wire [13:0] ID_EX_csr_num,
    input  wire        ID_EX_csr_we,
    input  wire [31:0] ID_EX_csr_wmask,
    input  wire [31:0] ID_EX_csr_wvalue,
    input  wire        ID_EX_valid,

    // data sram return (used for holding during div stall)
    input  wire [31:0] data_sram_rdata,

    // MEM/WB csr write info (for ordering & TID forwarding)
    input  wire        MEM_WB_valid,
    input  wire        MEM_WB_csr_we,
    input  wire [13:0] MEM_WB_csr_num,
    input  wire [31:0] MEM_WB_csr_wmask,
    input  wire [31:0] MEM_WB_csr_wvalue,

    // CSR readouts used by EX stage
    input  wire [31:0] csr_tid_value,
    input  wire [31:0] csr_rdtime_lo,
    input  wire [31:0] csr_rdtime_hi,

    // to IF/ID and ID stage
    output wire        div_stall,
    output wire        ex_exc_order_stall,
    output wire        ex_ale_redirect,

    // EX forwarding
    output wire [31:0] ex_forward_value,
    output wire        ex_forward_valid,

    // EX stage result (EA/ALU/div/rdtime)
    output wire [31:0] ex_result,

    // EX-stage exception info for CSR
    output wire        ex_exc_flush,
    output wire [ 5:0] ex_exc_ecode,
    output wire [ 8:0] ex_exc_esubcode,
    output wire        ex_exc_badv_we,
    output wire [31:0] ex_exc_badv,

    // EX exception flag used by MEM store gating
    output wire        ex_ale,

    // hold load data across div stall
    output reg         mem_rdata_hold_valid,
    output reg  [31:0] mem_rdata_hold,

    // EX/MEM pipeline registers outputs
    output reg  [31:0] EX_MEM_pc,
    output reg         EX_MEM_res_from_mem,
    output reg         EX_MEM_gr_we,
    output reg         EX_MEM_mem_we,
    output reg  [ 1:0] EX_MEM_load_size,
    output reg         EX_MEM_load_unsigned,
    output reg  [ 4:0] EX_MEM_dest,
    output reg  [31:0] EX_MEM_alu_result,
    output reg  [31:0] EX_MEM_rkd_value,
    output reg         EX_MEM_csrrd,
    output reg  [13:0] EX_MEM_csr_num,
    output reg         EX_MEM_csr_we,
    output reg  [31:0] EX_MEM_csr_wmask,
    output reg  [31:0] EX_MEM_csr_wvalue,
    output reg         EX_MEM_valid
);

localparam [13:0] CSR_CRMD_NUM = 14'h0000;
localparam [13:0] CSR_PRMD_NUM = 14'h0001;
localparam [13:0] CSR_ERA_NUM  = 14'h0006;
localparam [13:0] CSR_ESTAT_NUM= 14'h0005;
localparam [13:0] CSR_TID_NUM  = 14'h0040;

wire [31:0] alu_src1;
wire [31:0] alu_src2;
wire [31:0] alu_result;

assign alu_src1 = ID_EX_src1_is_pc  ? ID_EX_pc : ID_EX_rj_value;
assign alu_src2 = ID_EX_src2_is_imm ? ID_EX_imm : ID_EX_rkd_value;

alu u_alu(
    .alu_op     (ID_EX_alu_op    ),
    .alu_src1   (alu_src1  ),
    .alu_src2   (alu_src2  ),
    .alu_result (alu_result)
);

// ========== RDTIME* support ==========
wire ex_is_rdtime;
assign ex_is_rdtime = ID_EX_rdtimel || ID_EX_rdtimeh;

wire ex_writes_tid;
wire mem_writes_tid;
wire wb_writes_tid;
assign ex_writes_tid  = ID_EX_valid  && ID_EX_csr_we  && (ID_EX_csr_num  == CSR_TID_NUM);
assign mem_writes_tid = EX_MEM_valid && EX_MEM_csr_we && (EX_MEM_csr_num == CSR_TID_NUM);
assign wb_writes_tid  = MEM_WB_valid && MEM_WB_csr_we && (MEM_WB_csr_num == CSR_TID_NUM);

wire [31:0] tid_new_ex;
wire [31:0] tid_new_mem;
wire [31:0] tid_new_wb;
assign tid_new_ex  = (csr_tid_value & ~ID_EX_csr_wmask)  | (ID_EX_csr_wvalue  & ID_EX_csr_wmask);
assign tid_new_mem = (csr_tid_value & ~EX_MEM_csr_wmask) | (EX_MEM_csr_wvalue & EX_MEM_csr_wmask);
assign tid_new_wb  = (csr_tid_value & ~MEM_WB_csr_wmask) | (MEM_WB_csr_wvalue & MEM_WB_csr_wmask);

wire [31:0] tid_visible;
assign tid_visible = ex_writes_tid  ? tid_new_ex  :
                     mem_writes_tid ? tid_new_mem :
                     wb_writes_tid  ? tid_new_wb  :
                                      csr_tid_value;

wire [31:0] rdtime_read_value;
assign rdtime_read_value = ID_EX_rdtimel ? csr_rdtime_lo : csr_rdtime_hi;
wire [31:0] rdtime_result;
assign rdtime_result = ID_EX_rdtime_write_tid ? tid_visible : rdtime_read_value;

// ========== Exception detection in EX stage ==========
wire ex_is_load;
wire ex_is_store;
assign ex_is_load  = ID_EX_valid && ID_EX_res_from_mem;
assign ex_is_store = ID_EX_valid && ID_EX_mem_we;

wire ex_ld_half_misaligned;
wire ex_ld_word_misaligned;
wire ex_st_half_misaligned;
wire ex_st_word_misaligned;
assign ex_ld_half_misaligned = ex_is_load  && (ID_EX_load_size  == 2'b01) && (alu_result[0] != 1'b0);
assign ex_ld_word_misaligned = ex_is_load  && (ID_EX_load_size  == 2'b10) && (alu_result[1:0] != 2'b00);
assign ex_st_half_misaligned = ex_is_store && (ID_EX_store_size == 2'b01) && (alu_result[0] != 1'b0);
assign ex_st_word_misaligned = ex_is_store && (ID_EX_store_size == 2'b10) && (alu_result[1:0] != 2'b00);
assign ex_ale = ex_ld_half_misaligned | ex_ld_word_misaligned | ex_st_half_misaligned | ex_st_word_misaligned;

wire mem_writes_exc_csrs;
wire wb_writes_exc_csrs;
assign mem_writes_exc_csrs = EX_MEM_valid && EX_MEM_csr_we && ((EX_MEM_csr_num == CSR_CRMD_NUM) || (EX_MEM_csr_num == CSR_PRMD_NUM) || (EX_MEM_csr_num == CSR_ESTAT_NUM) || (EX_MEM_csr_num == CSR_ERA_NUM));
assign wb_writes_exc_csrs  = MEM_WB_valid && MEM_WB_csr_we && ((MEM_WB_csr_num == CSR_CRMD_NUM) || (MEM_WB_csr_num == CSR_PRMD_NUM) || (MEM_WB_csr_num == CSR_ESTAT_NUM) || (MEM_WB_csr_num == CSR_ERA_NUM));

assign ex_exc_order_stall = ex_ale && (mem_writes_exc_csrs || wb_writes_exc_csrs);
assign ex_ale_redirect = ex_ale && !ex_exc_order_stall;

assign ex_exc_flush = ID_EX_valid && (ID_EX_int || ID_EX_syscall || ID_EX_break || ID_EX_ine || ID_EX_adef || ex_ale) && !ex_exc_order_stall;
assign ex_exc_ecode = ID_EX_int     ? 6'h00 :
                      ID_EX_adef    ? 6'h08 :
                      ex_ale        ? 6'h09 :
                      ID_EX_syscall ? 6'h0b :
                      ID_EX_break   ? 6'h0c :
                      ID_EX_ine     ? 6'h0d :
                                     6'h00;
assign ex_exc_esubcode = ID_EX_adef ? 9'h000 : 9'h000;
assign ex_exc_badv_we = ID_EX_adef || ex_ale;
assign ex_exc_badv   = ID_EX_adef ? ID_EX_pc : alu_result;

// Divider IP integration
reg         div_req_valid;
reg         div_inflight;
reg         div_sel_signed;
reg         div_sel_mod;
reg  [31:0] div_dividend;
reg  [31:0] div_divisor;

wire        ex_is_div;
assign ex_is_div = ID_EX_valid && ID_EX_div_en;

wire        divu_divisor_tready;
wire        divu_dividend_tready;
wire        divu_out_tvalid;
wire [63:0] divu_out_tdata;

wire        divs_divisor_tready;
wire        divs_dividend_tready;
wire        divs_out_tvalid;
wire [63:0] divs_out_tdata;

wire div_in_ready;
assign div_in_ready = div_sel_signed ? (divs_divisor_tready & divs_dividend_tready)
                                   : (divu_divisor_tready & divu_dividend_tready);
wire div_out_valid_sel;
assign div_out_valid_sel = div_sel_signed ? divs_out_tvalid : divu_out_tvalid;
wire [63:0] div_out_data_sel;
assign div_out_data_sel = div_sel_signed ? divs_out_tdata : divu_out_tdata;

wire div_req_fire;
assign div_req_fire = div_req_valid && div_in_ready;
wire div_complete;
assign div_complete = div_inflight && div_out_valid_sel;

assign div_stall = ex_is_div && !div_complete;

div_unsigned u_divu(
    .aclk                  (clk),
    .s_axis_divisor_tvalid  (div_req_valid && !div_sel_signed),
    .s_axis_divisor_tready  (divu_divisor_tready),
    .s_axis_divisor_tdata   (div_divisor),
    .s_axis_dividend_tvalid (div_req_valid && !div_sel_signed),
    .s_axis_dividend_tready (divu_dividend_tready),
    .s_axis_dividend_tdata  (div_dividend),
    .m_axis_dout_tvalid     (divu_out_tvalid),
    .m_axis_dout_tdata      (divu_out_tdata)
);

div_signed u_divs(
    .aclk                  (clk),
    .s_axis_divisor_tvalid  (div_req_valid && div_sel_signed),
    .s_axis_divisor_tready  (divs_divisor_tready),
    .s_axis_divisor_tdata   (div_divisor),
    .s_axis_dividend_tvalid (div_req_valid && div_sel_signed),
    .s_axis_dividend_tready (divs_dividend_tready),
    .s_axis_dividend_tdata  (div_dividend),
    .m_axis_dout_tvalid     (divs_out_tvalid),
    .m_axis_dout_tdata      (divs_out_tdata)
);

always @(posedge clk) begin
    if (reset) begin
        div_req_valid        <= 1'b0;
        div_inflight         <= 1'b0;
        div_sel_signed       <= 1'b0;
        div_sel_mod          <= 1'b0;
        div_dividend         <= 32'b0;
        div_divisor          <= 32'b0;
        mem_rdata_hold_valid <= 1'b0;
        mem_rdata_hold       <= 32'b0;
    end
    else begin
        if (div_stall && EX_MEM_valid && EX_MEM_res_from_mem && !mem_rdata_hold_valid) begin
            mem_rdata_hold_valid <= 1'b1;
            mem_rdata_hold       <= data_sram_rdata;
        end
        if (!div_stall) begin
            mem_rdata_hold_valid <= 1'b0;
        end

        if (ex_is_div && !div_req_valid && !div_inflight) begin
            div_req_valid  <= 1'b1;
            div_sel_signed <= ID_EX_div_signed;
            div_sel_mod    <= ID_EX_div_mod;
            div_dividend   <= alu_src1;
            div_divisor    <= alu_src2;
        end

        if (div_req_fire) begin
            div_req_valid <= 1'b0;
            div_inflight  <= 1'b1;
        end

        if (div_complete) begin
            div_inflight <= 1'b0;
        end
    end
end

`ifdef __ICARUS__
wire [31:0] div_quot = div_out_data_sel[31:0];
wire [31:0] div_rem  = div_out_data_sel[63:32];
`else
wire [31:0] div_quot = div_out_data_sel[63:32];
wire [31:0] div_rem  = div_out_data_sel[31:0];
`endif

wire [31:0] div_result_value;
assign div_result_value = div_sel_mod ? div_rem : div_quot;

assign ex_result = ex_is_div    ? div_result_value :
                   ex_is_rdtime ? rdtime_result   :
                                  alu_result;

assign ex_forward_value = ex_result;
assign ex_forward_valid = ID_EX_valid && ID_EX_gr_we && (ID_EX_dest != 5'b0) && !ID_EX_res_from_mem
                          && !(ID_EX_csrrd || ID_EX_csr_we)
                          && (!ID_EX_div_en || div_complete);

// EX/MEM pipeline register update
always @(posedge clk) begin
    if (reset) begin
        EX_MEM_pc            <= 32'b0;
        EX_MEM_res_from_mem  <= 1'b0;
        EX_MEM_gr_we         <= 1'b0;
        EX_MEM_mem_we        <= 1'b0;
        EX_MEM_load_size     <= 2'b10;
        EX_MEM_load_unsigned <= 1'b0;
        EX_MEM_dest          <= 5'b0;
        EX_MEM_alu_result    <= 32'b0;
        EX_MEM_rkd_value     <= 32'b0;
        EX_MEM_csrrd         <= 1'b0;
        EX_MEM_csr_num       <= 14'b0;
        EX_MEM_csr_we        <= 1'b0;
        EX_MEM_csr_wmask     <= 32'b0;
        EX_MEM_csr_wvalue    <= 32'b0;
        EX_MEM_valid         <= 1'b0;
    end
    else if (div_stall) begin
        // Hold EX/MEM while divider is busy.
    end
    else if (ex_exc_order_stall) begin
        EX_MEM_pc            <= 32'b0;
        EX_MEM_res_from_mem  <= 1'b0;
        EX_MEM_gr_we         <= 1'b0;
        EX_MEM_mem_we        <= 1'b0;
        EX_MEM_load_size     <= 2'b10;
        EX_MEM_load_unsigned <= 1'b0;
        EX_MEM_dest          <= 5'b0;
        EX_MEM_alu_result    <= 32'b0;
        EX_MEM_rkd_value     <= 32'b0;
        EX_MEM_csrrd         <= 1'b0;
        EX_MEM_csr_num       <= 14'b0;
        EX_MEM_csr_we        <= 1'b0;
        EX_MEM_csr_wmask     <= 32'b0;
        EX_MEM_csr_wvalue    <= 32'b0;
        EX_MEM_valid         <= 1'b0;
    end
    else begin
        EX_MEM_pc            <= ID_EX_pc;
        EX_MEM_res_from_mem  <= ID_EX_res_from_mem && !ex_ale;
        EX_MEM_gr_we         <= ID_EX_gr_we && !ex_ale;
        EX_MEM_mem_we        <= ID_EX_mem_we && !ex_ale;
        EX_MEM_load_size     <= ID_EX_load_size;
        EX_MEM_load_unsigned <= ID_EX_load_unsigned;
        EX_MEM_dest          <= ID_EX_dest;
        EX_MEM_alu_result    <= ex_result;
        EX_MEM_rkd_value     <= ID_EX_rkd_value;
        EX_MEM_csrrd         <= ID_EX_csrrd;
        EX_MEM_csr_num       <= ID_EX_csr_num;
        EX_MEM_csr_we        <= ID_EX_csr_we;
        EX_MEM_csr_wmask     <= ID_EX_csr_wmask;
        EX_MEM_csr_wvalue    <= ID_EX_csr_wvalue;
        EX_MEM_valid         <= ID_EX_valid && !ex_ale;
    end
end

endmodule
