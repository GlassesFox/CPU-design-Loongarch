module if_stage(
    input  wire        clk,
    input  wire        reset,

    input  wire        pipeline_stall,
    input  wire        br_taken,
    input  wire [31:0] br_target,
    input  wire        ex_ale_redirect,
    input  wire [31:0] csr_rvalue2,

    // inst sram interface
    output wire        inst_sram_en,
    output wire [3 :0] inst_sram_we,
    output wire [31:0] inst_sram_addr,
    output wire [31:0] inst_sram_wdata,
    input  wire [31:0] inst_sram_rdata,

    // IF/ID pipeline registers
    output reg  [31:0] IF_ID_pc,
    output reg  [31:0] IF_ID_inst,
    output reg         IF_ID_valid
);

reg  [31:0] pc;
reg  [31:0] inst_addr_r;
reg         fetch_valid;   // marks when IF stage capture corresponds to a valid BRAM return

wire [31:0] seq_pc;
wire [31:0] nextpc;

assign seq_pc = pc + 32'h4;

// pre-IF: nextpc selection
assign nextpc = ex_ale_redirect ? csr_rvalue2 :  // EX-stage ALE redirect to exception entry
                pipeline_stall  ? pc :          // During stall, keep current PC
                br_taken        ? br_target :   // Branch to target
                                  seq_pc;       // Sequential

always @(posedge clk) begin
    if (reset) begin
        pc          <= 32'h1bfffffc;    // so that first nextpc = 0x1c000000
        fetch_valid <= 1'b0;
        inst_addr_r <= 32'b0;
    end
    else begin
        fetch_valid <= 1'b1;            // becomes valid one cycle after reset
        if (!pipeline_stall || ex_ale_redirect) begin
            pc <= nextpc;
        end
        // Remember the address issued to inst RAM; inst_sram_rdata returns for this address next cycle.
        // Must update even when stalling, because BRAM is still being clocked and sampling inst_sram_addr.
        inst_addr_r <= nextpc;
    end
end

assign inst_sram_en    = 1'b1;
assign inst_sram_we    = 4'b0;
assign inst_sram_addr  = nextpc;  // pre-IF issues nextpc; BRAM returns it in IF next cycle
assign inst_sram_wdata = 32'b0;

// IF/ID pipeline register update
always @(posedge clk) begin
    if (reset) begin
        IF_ID_pc    <= 32'b0;
        IF_ID_inst  <= 32'b0;
        IF_ID_valid <= 1'b0;
    end
    else if (ex_ale_redirect) begin
        // EX-stage exception redirect (ALE): flush IF/ID
        IF_ID_pc    <= 32'b0;
        IF_ID_inst  <= 32'b0;
        IF_ID_valid <= 1'b0;
    end
    else if (pipeline_stall) begin
        // Stall: freeze IF/ID, do nothing
    end
    else if (br_taken) begin
        // Branch taken, flush IF/ID (cancel technique)
        IF_ID_pc    <= 32'b0;
        IF_ID_inst  <= 32'b0;
        IF_ID_valid <= 1'b0;
    end
    else begin
        // Capture instruction that matches current PC (BRAM returns data of addr issued last cycle)
        IF_ID_pc    <= inst_addr_r;
        IF_ID_inst  <= inst_sram_rdata;
        IF_ID_valid <= fetch_valid;
    end
end

endmodule
