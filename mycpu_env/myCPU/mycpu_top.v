module mycpu_top(
    input  wire        clk,
    input  wire        resetn,
    input  wire [ 7:0] hw_int_in,
    // inst sram interface
    output wire        inst_sram_en,
    output wire [3 :0] inst_sram_we,
    output wire [31:0] inst_sram_addr,
    output wire [31:0] inst_sram_wdata,
    input  wire [31:0] inst_sram_rdata,
    // data sram interface
    output wire        data_sram_en,
    output wire [3 :0] data_sram_we,
    output wire [31:0] data_sram_addr,
    output wire [31:0] data_sram_wdata,
    input  wire [31:0] data_sram_rdata,
    // trace debug interface
    output wire [31:0] debug_wb_pc,
    output wire [ 3:0] debug_wb_rf_we,
    output wire [ 4:0] debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata
);

reg reset;
always @(posedge clk) reset <= ~resetn;

// IF/ID
wire [31:0] IF_ID_pc;
wire [31:0] IF_ID_inst;
wire        IF_ID_valid;

// ID/EX
wire [31:0] ID_EX_pc;
wire [14:0] ID_EX_alu_op;
wire        ID_EX_src1_is_pc;
wire        ID_EX_src2_is_imm;
wire [ 1:0] ID_EX_store_size;
wire [ 1:0] ID_EX_load_size;
wire        ID_EX_load_unsigned;
wire        ID_EX_div_en;
wire        ID_EX_div_signed;
wire        ID_EX_div_mod;
wire        ID_EX_res_from_mem;
wire        ID_EX_gr_we;
wire        ID_EX_mem_we;
wire [ 4:0] ID_EX_dest;
wire [31:0] ID_EX_rj_value;
wire [31:0] ID_EX_rkd_value;
wire [31:0] ID_EX_imm;
wire        ID_EX_csrrd;
wire        ID_EX_ertn;
wire        ID_EX_syscall;
wire        ID_EX_break;
wire        ID_EX_ine;
wire        ID_EX_adef;
wire        ID_EX_rdtimel;
wire        ID_EX_rdtimeh;
wire        ID_EX_rdtime_write_tid;
wire        ID_EX_int;
wire [13:0] ID_EX_csr_num;
wire        ID_EX_csr_we;
wire [31:0] ID_EX_csr_wmask;
wire [31:0] ID_EX_csr_wvalue;
wire        ID_EX_valid;

// EX/MEM
wire [31:0] EX_MEM_pc;
wire        EX_MEM_res_from_mem;
wire        EX_MEM_gr_we;
wire        EX_MEM_mem_we;
wire [ 1:0] EX_MEM_load_size;
wire        EX_MEM_load_unsigned;
wire [ 4:0] EX_MEM_dest;
wire [31:0] EX_MEM_alu_result;
wire [31:0] EX_MEM_rkd_value;
wire        EX_MEM_csrrd;
wire [13:0] EX_MEM_csr_num;
wire        EX_MEM_csr_we;
wire [31:0] EX_MEM_csr_wmask;
wire [31:0] EX_MEM_csr_wvalue;
wire        EX_MEM_valid;

// MEM/WB
wire [31:0] MEM_WB_pc;
wire        MEM_WB_res_from_mem;
wire        MEM_WB_gr_we;
wire [ 4:0] MEM_WB_dest;
wire [31:0] MEM_WB_alu_result;
wire [31:0] MEM_WB_mem_result;
wire        MEM_WB_csrrd;
wire [13:0] MEM_WB_csr_num;
wire        MEM_WB_csr_we;
wire [31:0] MEM_WB_csr_wmask;
wire [31:0] MEM_WB_csr_wvalue;
wire        MEM_WB_valid;

// Control / hazard
wire        pipeline_stall;
wire        br_taken;
wire [31:0] br_target;

// EX stage outputs
wire        div_stall;
wire        ex_exc_order_stall;
wire        ex_ale_redirect;
wire        ex_ale;
wire [31:0] ex_result;
wire [31:0] ex_forward_value;
wire        ex_forward_valid;
wire        ex_exc_flush;
wire [ 5:0] ex_exc_ecode;
wire [ 8:0] ex_exc_esubcode;
wire        ex_exc_badv_we;
wire [31:0] ex_exc_badv;
wire        mem_rdata_hold_valid;
wire [31:0] mem_rdata_hold;

// MEM stage forwarding
wire [31:0] mem_forward_value;
wire        mem_forward_valid;

// WB stage / CSR
wire [13:0] csr_num2;
wire        rf_we_commit;
wire [ 4:0] rf_waddr;
wire [31:0] rf_wdata;
wire [31:0] csr_rvalue;
wire [31:0] csr_rvalue2;
wire [31:0] csr_tid_value;
wire [31:0] csr_rdtime_lo;
wire [31:0] csr_rdtime_hi;
wire        csr_has_int;

if_stage u_if_stage(
    .clk            (clk),
    .reset          (reset),
    .pipeline_stall (pipeline_stall),
    .br_taken       (br_taken),
    .br_target      (br_target),
    .ex_ale_redirect(ex_ale_redirect),
    .csr_rvalue2    (csr_rvalue2),
    .inst_sram_en   (inst_sram_en),
    .inst_sram_we   (inst_sram_we),
    .inst_sram_addr (inst_sram_addr),
    .inst_sram_wdata(inst_sram_wdata),
    .inst_sram_rdata(inst_sram_rdata),
    .IF_ID_pc       (IF_ID_pc),
    .IF_ID_inst     (IF_ID_inst),
    .IF_ID_valid    (IF_ID_valid)
);

id_stage u_id_stage(
    .clk               (clk),
    .reset             (reset),
    .IF_ID_pc          (IF_ID_pc),
    .IF_ID_inst        (IF_ID_inst),
    .IF_ID_valid       (IF_ID_valid),
    .div_stall         (div_stall),
    .ex_exc_order_stall(ex_exc_order_stall),
    .ex_ale_redirect   (ex_ale_redirect),
    .ex_forward_value  (ex_forward_value),
    .ex_forward_valid  (ex_forward_valid),
    .mem_forward_value (mem_forward_value),
    .mem_forward_valid (mem_forward_valid),
    .EX_MEM_dest       (EX_MEM_dest),
    .EX_MEM_gr_we      (EX_MEM_gr_we),
    .EX_MEM_valid      (EX_MEM_valid),
    .EX_MEM_csrrd      (EX_MEM_csrrd),
    .EX_MEM_csr_we     (EX_MEM_csr_we),
    .EX_MEM_csr_num    (EX_MEM_csr_num),
    .MEM_WB_valid      (MEM_WB_valid),
    .MEM_WB_csr_we     (MEM_WB_csr_we),
    .MEM_WB_csr_num    (MEM_WB_csr_num),
    .csr_has_int       (csr_has_int),
    .csr_rvalue2       (csr_rvalue2),
    .rf_we_commit      (rf_we_commit),
    .rf_waddr          (rf_waddr),
    .rf_wdata          (rf_wdata),
    .pipeline_stall    (pipeline_stall),
    .br_taken          (br_taken),
    .br_target         (br_target),
    .csr_num2          (csr_num2),
    .ID_EX_pc          (ID_EX_pc),
    .ID_EX_alu_op      (ID_EX_alu_op),
    .ID_EX_src1_is_pc  (ID_EX_src1_is_pc),
    .ID_EX_src2_is_imm (ID_EX_src2_is_imm),
    .ID_EX_store_size  (ID_EX_store_size),
    .ID_EX_load_size   (ID_EX_load_size),
    .ID_EX_load_unsigned(ID_EX_load_unsigned),
    .ID_EX_div_en      (ID_EX_div_en),
    .ID_EX_div_signed  (ID_EX_div_signed),
    .ID_EX_div_mod     (ID_EX_div_mod),
    .ID_EX_res_from_mem(ID_EX_res_from_mem),
    .ID_EX_gr_we       (ID_EX_gr_we),
    .ID_EX_mem_we      (ID_EX_mem_we),
    .ID_EX_dest        (ID_EX_dest),
    .ID_EX_rj_value    (ID_EX_rj_value),
    .ID_EX_rkd_value   (ID_EX_rkd_value),
    .ID_EX_imm         (ID_EX_imm),
    .ID_EX_csrrd       (ID_EX_csrrd),
    .ID_EX_ertn        (ID_EX_ertn),
    .ID_EX_syscall     (ID_EX_syscall),
    .ID_EX_break       (ID_EX_break),
    .ID_EX_ine         (ID_EX_ine),
    .ID_EX_adef        (ID_EX_adef),
    .ID_EX_rdtimel     (ID_EX_rdtimel),
    .ID_EX_rdtimeh     (ID_EX_rdtimeh),
    .ID_EX_rdtime_write_tid(ID_EX_rdtime_write_tid),
    .ID_EX_int         (ID_EX_int),
    .ID_EX_csr_num     (ID_EX_csr_num),
    .ID_EX_csr_we      (ID_EX_csr_we),
    .ID_EX_csr_wmask   (ID_EX_csr_wmask),
    .ID_EX_csr_wvalue  (ID_EX_csr_wvalue),
    .ID_EX_valid       (ID_EX_valid)
);

ex_stage u_ex_stage(
    .clk               (clk),
    .reset             (reset),
    .ID_EX_pc          (ID_EX_pc),
    .ID_EX_alu_op      (ID_EX_alu_op),
    .ID_EX_src1_is_pc  (ID_EX_src1_is_pc),
    .ID_EX_src2_is_imm (ID_EX_src2_is_imm),
    .ID_EX_store_size  (ID_EX_store_size),
    .ID_EX_load_size   (ID_EX_load_size),
    .ID_EX_load_unsigned(ID_EX_load_unsigned),
    .ID_EX_div_en      (ID_EX_div_en),
    .ID_EX_div_signed  (ID_EX_div_signed),
    .ID_EX_div_mod     (ID_EX_div_mod),
    .ID_EX_res_from_mem(ID_EX_res_from_mem),
    .ID_EX_gr_we       (ID_EX_gr_we),
    .ID_EX_mem_we      (ID_EX_mem_we),
    .ID_EX_dest        (ID_EX_dest),
    .ID_EX_rj_value    (ID_EX_rj_value),
    .ID_EX_rkd_value   (ID_EX_rkd_value),
    .ID_EX_imm         (ID_EX_imm),
    .ID_EX_csrrd       (ID_EX_csrrd),
    .ID_EX_ertn        (ID_EX_ertn),
    .ID_EX_syscall     (ID_EX_syscall),
    .ID_EX_break       (ID_EX_break),
    .ID_EX_ine         (ID_EX_ine),
    .ID_EX_adef        (ID_EX_adef),
    .ID_EX_rdtimel     (ID_EX_rdtimel),
    .ID_EX_rdtimeh     (ID_EX_rdtimeh),
    .ID_EX_rdtime_write_tid(ID_EX_rdtime_write_tid),
    .ID_EX_int         (ID_EX_int),
    .ID_EX_csr_num     (ID_EX_csr_num),
    .ID_EX_csr_we      (ID_EX_csr_we),
    .ID_EX_csr_wmask   (ID_EX_csr_wmask),
    .ID_EX_csr_wvalue  (ID_EX_csr_wvalue),
    .ID_EX_valid       (ID_EX_valid),
    .data_sram_rdata   (data_sram_rdata),
    .MEM_WB_valid      (MEM_WB_valid),
    .MEM_WB_csr_we     (MEM_WB_csr_we),
    .MEM_WB_csr_num    (MEM_WB_csr_num),
    .MEM_WB_csr_wmask  (MEM_WB_csr_wmask),
    .MEM_WB_csr_wvalue (MEM_WB_csr_wvalue),
    .csr_tid_value     (csr_tid_value),
    .csr_rdtime_lo     (csr_rdtime_lo),
    .csr_rdtime_hi     (csr_rdtime_hi),
    .div_stall         (div_stall),
    .ex_exc_order_stall(ex_exc_order_stall),
    .ex_ale_redirect   (ex_ale_redirect),
    .ex_forward_value  (ex_forward_value),
    .ex_forward_valid  (ex_forward_valid),
    .ex_result         (ex_result),
    .ex_exc_flush      (ex_exc_flush),
    .ex_exc_ecode      (ex_exc_ecode),
    .ex_exc_esubcode   (ex_exc_esubcode),
    .ex_exc_badv_we    (ex_exc_badv_we),
    .ex_exc_badv       (ex_exc_badv),
    .ex_ale            (ex_ale),
    .mem_rdata_hold_valid(mem_rdata_hold_valid),
    .mem_rdata_hold    (mem_rdata_hold),
    .EX_MEM_pc         (EX_MEM_pc),
    .EX_MEM_res_from_mem(EX_MEM_res_from_mem),
    .EX_MEM_gr_we      (EX_MEM_gr_we),
    .EX_MEM_mem_we     (EX_MEM_mem_we),
    .EX_MEM_load_size  (EX_MEM_load_size),
    .EX_MEM_load_unsigned(EX_MEM_load_unsigned),
    .EX_MEM_dest       (EX_MEM_dest),
    .EX_MEM_alu_result (EX_MEM_alu_result),
    .EX_MEM_rkd_value  (EX_MEM_rkd_value),
    .EX_MEM_csrrd      (EX_MEM_csrrd),
    .EX_MEM_csr_num    (EX_MEM_csr_num),
    .EX_MEM_csr_we     (EX_MEM_csr_we),
    .EX_MEM_csr_wmask  (EX_MEM_csr_wmask),
    .EX_MEM_csr_wvalue (EX_MEM_csr_wvalue),
    .EX_MEM_valid      (EX_MEM_valid)
);

mem_stage u_mem_stage(
    .clk               (clk),
    .reset             (reset),
    .div_stall         (div_stall),
    .ex_result         (ex_result),
    .ex_ale            (ex_ale),
    .ID_EX_mem_we      (ID_EX_mem_we),
    .ID_EX_valid       (ID_EX_valid),
    .ID_EX_store_size  (ID_EX_store_size),
    .ID_EX_rkd_value   (ID_EX_rkd_value),
    .data_sram_en      (data_sram_en),
    .data_sram_we      (data_sram_we),
    .data_sram_addr    (data_sram_addr),
    .data_sram_wdata   (data_sram_wdata),
    .data_sram_rdata   (data_sram_rdata),
    .mem_rdata_hold_valid(mem_rdata_hold_valid),
    .mem_rdata_hold    (mem_rdata_hold),
    .EX_MEM_pc         (EX_MEM_pc),
    .EX_MEM_res_from_mem(EX_MEM_res_from_mem),
    .EX_MEM_gr_we      (EX_MEM_gr_we),
    .EX_MEM_mem_we     (EX_MEM_mem_we),
    .EX_MEM_load_size  (EX_MEM_load_size),
    .EX_MEM_load_unsigned(EX_MEM_load_unsigned),
    .EX_MEM_dest       (EX_MEM_dest),
    .EX_MEM_alu_result (EX_MEM_alu_result),
    .EX_MEM_rkd_value  (EX_MEM_rkd_value),
    .EX_MEM_csrrd      (EX_MEM_csrrd),
    .EX_MEM_csr_num    (EX_MEM_csr_num),
    .EX_MEM_csr_we     (EX_MEM_csr_we),
    .EX_MEM_csr_wmask  (EX_MEM_csr_wmask),
    .EX_MEM_csr_wvalue (EX_MEM_csr_wvalue),
    .EX_MEM_valid      (EX_MEM_valid),
    .mem_forward_value (mem_forward_value),
    .mem_forward_valid (mem_forward_valid),
    .MEM_WB_pc         (MEM_WB_pc),
    .MEM_WB_res_from_mem(MEM_WB_res_from_mem),
    .MEM_WB_gr_we      (MEM_WB_gr_we),
    .MEM_WB_dest       (MEM_WB_dest),
    .MEM_WB_alu_result (MEM_WB_alu_result),
    .MEM_WB_mem_result (MEM_WB_mem_result),
    .MEM_WB_csrrd      (MEM_WB_csrrd),
    .MEM_WB_csr_num    (MEM_WB_csr_num),
    .MEM_WB_csr_we     (MEM_WB_csr_we),
    .MEM_WB_csr_wmask  (MEM_WB_csr_wmask),
    .MEM_WB_csr_wvalue (MEM_WB_csr_wvalue),
    .MEM_WB_valid      (MEM_WB_valid)
);

wb_stage u_wb_stage(
    .clk            (clk),
    .reset          (reset),
    .hw_int_in      (hw_int_in),
    .div_stall      (div_stall),
    .csr_num2       (csr_num2),
    .ex_pc          (ID_EX_pc),
    .ertn_flush     (ID_EX_valid && ID_EX_ertn),
    .ex_exc_flush   (ex_exc_flush),
    .ex_exc_ecode   (ex_exc_ecode),
    .ex_exc_esubcode(ex_exc_esubcode),
    .ex_exc_badv_we (ex_exc_badv_we),
    .ex_exc_badv    (ex_exc_badv),
    .MEM_WB_pc      (MEM_WB_pc),
    .MEM_WB_res_from_mem(MEM_WB_res_from_mem),
    .MEM_WB_gr_we   (MEM_WB_gr_we),
    .MEM_WB_dest    (MEM_WB_dest),
    .MEM_WB_alu_result(MEM_WB_alu_result),
    .MEM_WB_mem_result(MEM_WB_mem_result),
    .MEM_WB_csrrd   (MEM_WB_csrrd),
    .MEM_WB_csr_num (MEM_WB_csr_num),
    .MEM_WB_csr_we  (MEM_WB_csr_we),
    .MEM_WB_csr_wmask(MEM_WB_csr_wmask),
    .MEM_WB_csr_wvalue(MEM_WB_csr_wvalue),
    .MEM_WB_valid   (MEM_WB_valid),
    .rf_we_commit   (rf_we_commit),
    .rf_waddr       (rf_waddr),
    .rf_wdata       (rf_wdata),
    .csr_rvalue     (csr_rvalue),
    .csr_rvalue2    (csr_rvalue2),
    .csr_tid_value  (csr_tid_value),
    .csr_rdtime_lo  (csr_rdtime_lo),
    .csr_rdtime_hi  (csr_rdtime_hi),
    .csr_has_int    (csr_has_int),
    .debug_wb_pc    (debug_wb_pc),
    .debug_wb_rf_we (debug_wb_rf_we),
    .debug_wb_rf_wnum(debug_wb_rf_wnum),
    .debug_wb_rf_wdata(debug_wb_rf_wdata)
);

endmodule
