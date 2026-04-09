module wb_stage(
    input  wire        clk,
    input  wire        reset,
    input  wire [ 7:0] hw_int_in,

    input  wire        div_stall,

    // from ID stage
    input  wire [13:0] csr_num2,
    input  wire [31:0] ex_pc,
    input  wire        ertn_flush,

    // from EX stage
    input  wire        ex_exc_flush,
    input  wire [ 5:0] ex_exc_ecode,
    input  wire [ 8:0] ex_exc_esubcode,
    input  wire        ex_exc_badv_we,
    input  wire [31:0] ex_exc_badv,

    // MEM/WB pipeline registers inputs
    input  wire [31:0] MEM_WB_pc,
    input  wire        MEM_WB_res_from_mem,
    input  wire        MEM_WB_gr_we,
    input  wire [ 4:0] MEM_WB_dest,
    input  wire [31:0] MEM_WB_alu_result,
    input  wire [31:0] MEM_WB_mem_result,
    input  wire        MEM_WB_csrrd,
    input  wire [13:0] MEM_WB_csr_num,
    input  wire        MEM_WB_csr_we,
    input  wire [31:0] MEM_WB_csr_wmask,
    input  wire [31:0] MEM_WB_csr_wvalue,
    input  wire        MEM_WB_valid,

    // regfile writeback
    output wire        rf_we_commit,
    output wire [ 4:0] rf_waddr,
    output wire [31:0] rf_wdata,

    // CSR readouts
    output wire [31:0] csr_rvalue,
    output wire [31:0] csr_rvalue2,
    output wire [31:0] csr_tid_value,
    output wire [31:0] csr_rdtime_lo,
    output wire [31:0] csr_rdtime_hi,
    output wire        csr_has_int,

    // trace debug interface
    output wire [31:0] debug_wb_pc,
    output wire [ 3:0] debug_wb_rf_we,
    output wire [ 4:0] debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata
);

wire [31:0] mem_result;
assign mem_result = MEM_WB_mem_result;

// WB CSR RAW bypass
reg        last_csr_write_valid;
reg [13:0] last_csr_write_num;
reg [31:0] last_csr_write_new_value;

always @(posedge clk) begin
    if (reset) begin
        last_csr_write_valid     <= 1'b0;
        last_csr_write_num       <= 14'b0;
        last_csr_write_new_value <= 32'b0;
    end
    else begin
        last_csr_write_valid <= MEM_WB_valid && MEM_WB_csr_we;
        if (MEM_WB_valid && MEM_WB_csr_we) begin
            last_csr_write_num       <= MEM_WB_csr_num;
            last_csr_write_new_value <= (csr_rvalue & ~MEM_WB_csr_wmask) | (MEM_WB_csr_wvalue & MEM_WB_csr_wmask);
        end
    end
end

wire [31:0] wb_csrrd_value;
assign wb_csrrd_value = (MEM_WB_csrrd && last_csr_write_valid && (MEM_WB_csr_num == last_csr_write_num))
                             ? last_csr_write_new_value
                             : csr_rvalue;

wire [31:0] final_result;
assign final_result = MEM_WB_res_from_mem ? mem_result :
                      MEM_WB_csrrd        ? wb_csrrd_value :
                      MEM_WB_csr_we       ? csr_rvalue :
                                            MEM_WB_alu_result;

wire rf_we;
assign rf_we    = MEM_WB_gr_we && MEM_WB_valid;
assign rf_waddr = MEM_WB_dest;
assign rf_wdata = final_result;

// Prevent repeated WB commits when MEM/WB is held for many cycles by div/mod.
reg         div_stall_d;
reg         wb_written_valid;
reg  [31:0] wb_written_pc;
wire        wb_same_as_last;
assign wb_same_as_last = wb_written_valid && (wb_written_pc == MEM_WB_pc);
wire        wb_dedup_en;
assign wb_dedup_en = div_stall | div_stall_d;
assign      rf_we_commit = rf_we && !(wb_dedup_en && wb_same_as_last);

always @(posedge clk) begin
    if (reset) begin
        div_stall_d      <= 1'b0;
        wb_written_valid <= 1'b0;
        wb_written_pc    <= 32'b0;
    end
    else if (rf_we_commit) begin
        wb_written_valid <= 1'b1;
        wb_written_pc    <= MEM_WB_pc;
    end
    div_stall_d <= div_stall;
end

// rdtime stable counter tick
reg        retire_hold_counted_valid;
reg [31:0] retire_hold_counted_pc;
wire       retire_hold_window;
assign retire_hold_window = div_stall | div_stall_d;
wire       inst_retire;
assign inst_retire = MEM_WB_valid && !(retire_hold_window && retire_hold_counted_valid && (retire_hold_counted_pc == MEM_WB_pc));

always @(posedge clk) begin
    if (reset) begin
        retire_hold_counted_valid <= 1'b0;
        retire_hold_counted_pc    <= 32'b0;
    end
    else if (!retire_hold_window) begin
        retire_hold_counted_valid <= 1'b0;
    end
    else if (inst_retire) begin
        retire_hold_counted_valid <= 1'b1;
        retire_hold_counted_pc    <= MEM_WB_pc;
    end
end

// CSR
csr_exc_int u_csr_exc_int(
    .clk       (clk),
    .reset     (reset),
    .hw_int_in (hw_int_in),
    .inst_retire(inst_retire),
    .csr_num   (MEM_WB_csr_num),
    .csr_num2  (csr_num2),
    .csr_we    (MEM_WB_valid && MEM_WB_csr_we),
    .csr_wmask (MEM_WB_csr_wmask),
    .csr_wvalue(MEM_WB_csr_wvalue),
    .exc_flush (ex_exc_flush),
    .exc_ecode (ex_exc_ecode),
    .exc_esubcode(ex_exc_esubcode),
    .exc_pc    (ex_pc),
    .exc_badv_we(ex_exc_badv_we),
    .exc_badv  (ex_exc_badv),
    .ertn_flush(ertn_flush),
    .csr_rvalue(csr_rvalue),
    .csr_rvalue2(csr_rvalue2),
    .csr_tid_value(csr_tid_value),
    .rdtime_lo (csr_rdtime_lo),
    .rdtime_hi (csr_rdtime_hi),
    .has_int   (csr_has_int)
);

// debug info generate
assign debug_wb_pc       = MEM_WB_pc;
assign debug_wb_rf_we    = MEM_WB_valid ? {4{rf_we_commit}} : 4'b0;
assign debug_wb_rf_wnum  = MEM_WB_dest;
assign debug_wb_rf_wdata = final_result;

endmodule
