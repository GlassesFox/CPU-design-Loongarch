module csr_exc_int (
    input  wire        clk,
    input  wire        reset,
    input  wire [ 7:0] hw_int_in,
    input  wire        inst_retire,
    input  wire [13:0] csr_num,
    input  wire [13:0] csr_num2,
    input  wire        csr_we,
    input  wire [31:0] csr_wmask,
    input  wire [31:0] csr_wvalue,
    input  wire        exc_flush,
    input  wire [ 5:0] exc_ecode,
    input  wire [ 8:0] exc_esubcode,
    input  wire [31:0] exc_pc,
    input  wire        exc_badv_we,
    input  wire [31:0] exc_badv,
    input  wire        ertn_flush,
    output reg  [31:0] csr_rvalue,
    output reg  [31:0] csr_rvalue2,
    output wire [31:0] csr_tid_value,
    output wire [31:0] rdtime_lo,
    output wire [31:0] rdtime_hi,
    output wire        has_int
);

// CSR numbers (aligned with mycpu_env/func/include/regdef.h)
localparam [13:0] CSR_CRMD   = 14'h0000;
localparam [13:0] CSR_PRMD   = 14'h0001;
localparam [13:0] CSR_ECFG   = 14'h0004; // regdef.h uses csr_ectl
localparam [13:0] CSR_ESTAT  = 14'h0005;
localparam [13:0] CSR_ERA    = 14'h0006;
localparam [13:0] CSR_BADV   = 14'h0007;
localparam [13:0] CSR_EENTRY = 14'h000c;
localparam [13:0] CSR_SAVE0  = 14'h0030;
localparam [13:0] CSR_SAVE1  = 14'h0031;
localparam [13:0] CSR_SAVE2  = 14'h0032;
localparam [13:0] CSR_SAVE3  = 14'h0033;
localparam [13:0] CSR_TID    = 14'h0040;
localparam [13:0] CSR_TCFG   = 14'h0041;
localparam [13:0] CSR_TVAL   = 14'h0042;
localparam [13:0] CSR_TICLR  = 14'h0044;
localparam [13:0] CSR_LLBCTL = 14'h0060;

// CSR storage
reg [31:0] csr_crmd;
reg [31:0] csr_prmd;
reg [31:0] csr_ecfg;
reg [31:0] csr_era;
reg [31:0] csr_badv;
reg [31:0] csr_eentry;
reg [31:0] csr_save0;
reg [31:0] csr_save1;
reg [31:0] csr_save2;
reg [31:0] csr_save3;
reg [31:0] csr_tid;
reg [31:0] csr_tcfg;
reg [31:0] timer_cnt;

reg [63:0] stable_cnt;

assign csr_tid_value = csr_tid;
assign rdtime_lo     = stable_cnt[31:0];
assign rdtime_hi     = stable_cnt[63:32];

reg        llbit;
reg        csr_llbctl_klo;   // LLBCTL.KLO (bit2)

// ESTAT fields we care about
reg  [1:0] estat_is_soft;   // ESTAT.IS[1:0]
reg  [7:0] estat_is_hard;   // ESTAT.IS[9:2]
reg        estat_is_timer;  // ESTAT.IS[11]
reg  [5:0] estat_ecode;     // ESTAT.ECODE[21:16]
reg  [8:0] estat_esubcode;  // ESTAT.ESUBCODE[30:22]

wire       csr_crmd_ie = csr_crmd[2];
wire [12:0] csr_ecfg_lie = csr_ecfg[12:0];
wire [12:0] csr_estat_is = {1'b0, estat_is_timer, 1'b0, estat_is_hard, estat_is_soft};

assign has_int = ((csr_estat_is & csr_ecfg_lie) != 13'b0) && (csr_crmd_ie == 1'b1);

wire        tcfg_en       = csr_tcfg[0];
wire        tcfg_periodic = csr_tcfg[1];
wire [29:0] tcfg_initval  = csr_tcfg[31:2];
wire [31:0] timer_init_cnt_raw = {tcfg_initval, 2'b0};
wire [31:0] timer_init_cnt = (timer_init_cnt_raw == 32'b0) ? 32'd1 : timer_init_cnt_raw;

wire write_tcfg  = csr_we && (csr_num == CSR_TCFG);
wire write_ticlr = csr_we && (csr_num == CSR_TICLR);
wire ticlr_clr_pulse = write_ticlr && csr_wmask[0] && csr_wvalue[0];
wire timer_timeout_pulse = (!write_tcfg) && tcfg_en && (timer_cnt == 32'd1);
wire [31:0] csr_tcfg_next = (csr_tcfg & ~csr_wmask) | (csr_wvalue & csr_wmask);
wire [31:0] timer_init_cnt_next_raw = {csr_tcfg_next[31:2], 2'b0};
wire [31:0] timer_init_cnt_next = (timer_init_cnt_next_raw == 32'b0) ? 32'd1 : timer_init_cnt_next_raw;

always @(posedge clk) begin
    if (reset) begin
        // A conservative reset state: PLV=0, IE=0, DA=1 (direct address), others 0.
        csr_crmd   <= 32'h0000_0008;
        csr_prmd   <= 32'h0000_0000;
        csr_ecfg   <= 32'h0000_0000;
        csr_era    <= 32'h0000_0000;
        csr_badv   <= 32'h0000_0000;
        csr_eentry <= 32'h1c00_8000;  // default exception entry used by func tests
        csr_save0  <= 32'h0000_0000;
        csr_save1  <= 32'h0000_0000;
        csr_save2  <= 32'h0000_0000;
        csr_save3  <= 32'h0000_0000;
        csr_tid    <= 32'h0000_0000;
        csr_tcfg   <= 32'h0000_0000;
        timer_cnt  <= 32'h0000_0000;
        stable_cnt <= 64'b0;

        estat_is_soft  <= 2'b00;
        estat_is_hard  <= 8'b0;
        estat_is_timer <= 1'b0;
        estat_ecode    <= 6'b0;
        estat_esubcode <= 9'b0;

        llbit          <= 1'b0;
        csr_llbctl_klo <= 1'b0;
    end
    else begin
        if (inst_retire) begin
            stable_cnt <= stable_cnt + 64'd1;
        end
        // Sample external hardware interrupts into ESTAT.IS[9:2]
        estat_is_hard <= hw_int_in;

        // Core-local timer
        // - TCFG write has priority for (re)load/stop.
        // - When enabled, timer_cnt decrements each cycle.
        // - When it reaches 0 (i.e. old value was 1), set ESTAT.IS[11].
        // - TICLR.CLR clears ESTAT.IS[11], but has LOWER priority than setting it.
        if (write_tcfg) begin
            csr_tcfg <= csr_tcfg_next;
            if (csr_tcfg_next[0]) begin
                timer_cnt <= timer_init_cnt_next;
            end
        end
        else if (tcfg_en) begin
            if (timer_cnt == 32'd1) begin
                timer_cnt <= tcfg_periodic ? timer_init_cnt : 32'b0;
            end
            else if (timer_cnt != 32'b0) begin
                timer_cnt <= timer_cnt - 32'd1;
            end
        end

        // Set/clear timer interrupt pending with correct priority.
        if (timer_timeout_pulse) begin
            estat_is_timer <= 1'b1;
        end
        else if (ticlr_clr_pulse) begin
            estat_is_timer <= 1'b0;
        end

        // Highest-priority events (exception/ertn/csr writes) follow.
        if (exc_flush) begin
            // Exception entry: save old mode into PRMD and switch to kernel mode (PLV=0, IE=0)
            csr_prmd[1:0] <= csr_crmd[1:0];
            csr_prmd[2]   <= csr_crmd[2];
            csr_crmd[1:0] <= 2'b00;
            csr_crmd[2]   <= 1'b0;

            // Record exception PC
            csr_era <= exc_pc;

            // Record exception codes into ESTAT
            estat_ecode    <= exc_ecode;
            estat_esubcode <= exc_esubcode;

            // Record bad virtual address when required (ADEF/ALE, etc.)
            if (exc_badv_we) begin
                csr_badv <= exc_badv;
            end
        end
        else if (ertn_flush) begin
            // ERTN: restore privilege level / interrupt enable from PRMD into CRMD
            // CRMD[1:0]=PLV, CRMD[2]=IE; PRMD[1:0]=PPLV, PRMD[2]=PIE
            csr_crmd[1:0] <= csr_prmd[1:0];
            csr_crmd[2]   <= csr_prmd[2];

            // ERTN: LLbit behavior controlled by LLBCTL.KLO
            // If KLO != 1: clear LLbit; else keep LLbit and clear KLO (one-shot)
            if (csr_llbctl_klo != 1'b1) begin
                llbit <= 1'b0;
            end
            else begin
                csr_llbctl_klo <= 1'b0;
            end
        end
        else if (csr_we) begin
            case (csr_num)
                CSR_CRMD:   csr_crmd   <= (csr_crmd   & ~csr_wmask) | (csr_wvalue & csr_wmask);
                CSR_PRMD:   csr_prmd   <= (csr_prmd   & ~csr_wmask) | (csr_wvalue & csr_wmask);
                // ECFG.LIE[12:0]: bit10 is reserved in this simplified core, keep it zero.
                CSR_ECFG:   csr_ecfg   <= (((csr_ecfg & ~csr_wmask) | (csr_wvalue & csr_wmask)) & 32'h0000_1bff);
                CSR_ESTAT: begin
                    // Only software interrupt pending bits are writable: ESTAT.IS[1:0]
                    if (csr_wmask[0]) estat_is_soft[0] <= csr_wvalue[0];
                    if (csr_wmask[1]) estat_is_soft[1] <= csr_wvalue[1];
                end
                CSR_ERA:    csr_era    <= (csr_era    & ~csr_wmask) | (csr_wvalue & csr_wmask);
                CSR_BADV:   csr_badv   <= (csr_badv   & ~csr_wmask) | (csr_wvalue & csr_wmask);
                CSR_EENTRY: csr_eentry <= (csr_eentry & ~csr_wmask) | (csr_wvalue & csr_wmask);
                CSR_SAVE0:  csr_save0  <= (csr_save0  & ~csr_wmask) | (csr_wvalue & csr_wmask);
                CSR_SAVE1:  csr_save1  <= (csr_save1  & ~csr_wmask) | (csr_wvalue & csr_wmask);
                CSR_SAVE2:  csr_save2  <= (csr_save2  & ~csr_wmask) | (csr_wvalue & csr_wmask);
                CSR_SAVE3:  csr_save3  <= (csr_save3  & ~csr_wmask) | (csr_wvalue & csr_wmask);
                CSR_TID:    csr_tid    <= (csr_tid    & ~csr_wmask) | (csr_wvalue & csr_wmask);
                CSR_TCFG: begin
                    // handled in the timer block above
                end
                CSR_TVAL: begin
                    // TVAL is read-only
                end
                CSR_TICLR: begin
                    // handled in the timer block above
                end
                CSR_LLBCTL: begin
                    // LLBCTL layout (LA32R): bit0 ROLLB (read-only=LLbit), bit1 WCLLB (W1: write-1 clears LLbit), bit2 KLO (RW)
                    if (csr_wmask[2]) begin
                        csr_llbctl_klo <= csr_wvalue[2];
                    end
                    if (csr_wmask[1] && csr_wvalue[1]) begin
                        llbit <= 1'b0;
                    end
                end
                default: begin
                    // Unknown/unsupported CSR: ignore writes
                end
            endcase
        end
    end
end

function [31:0] csr_read;
    input [13:0] num;
    begin
        case (num)
            CSR_CRMD:   csr_read = csr_crmd;
            CSR_PRMD:   csr_read = csr_prmd;
            CSR_ECFG:   csr_read = csr_ecfg;
            CSR_ESTAT:  csr_read = {1'b0, estat_esubcode, estat_ecode, 3'b0, csr_estat_is};
            CSR_ERA:    csr_read = csr_era;
            CSR_BADV:   csr_read = csr_badv;
            CSR_EENTRY: csr_read = csr_eentry;
            CSR_SAVE0:  csr_read = csr_save0;
            CSR_SAVE1:  csr_read = csr_save1;
            CSR_SAVE2:  csr_read = csr_save2;
            CSR_SAVE3:  csr_read = csr_save3;
            CSR_TID:    csr_read = csr_tid;
            CSR_TCFG:   csr_read = csr_tcfg;
            CSR_TVAL:   csr_read = timer_cnt;
            CSR_TICLR:  csr_read = 32'b0; // spec: reads as 0
            CSR_LLBCTL: csr_read = {29'b0, csr_llbctl_klo, 1'b0, llbit};
            default:    csr_read = 32'b0;
        endcase
    end
endfunction

always @(*) begin
    csr_rvalue  = csr_read(csr_num);
    csr_rvalue2 = csr_read(csr_num2);
end

endmodule
