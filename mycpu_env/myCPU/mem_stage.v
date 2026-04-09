module mem_stage(
    input  wire        clk,
    input  wire        reset,

    input  wire        div_stall,

    // EX stage address/result and store controls (address is issued in EX)
    input  wire [31:0] ex_result,
    input  wire        ex_ale,
    input  wire        ID_EX_mem_we,
    input  wire        ID_EX_valid,
    input  wire [ 1:0] ID_EX_store_size,
    input  wire [31:0] ID_EX_rkd_value,

    // data sram interface
    output wire        data_sram_en,
    output wire [3 :0] data_sram_we,
    output wire [31:0] data_sram_addr,
    output wire [31:0] data_sram_wdata,
    input  wire [31:0] data_sram_rdata,

    // held load data across div stall (captured in EX stage)
    input  wire        mem_rdata_hold_valid,
    input  wire [31:0] mem_rdata_hold,

    // EX/MEM pipeline registers inputs
    input  wire [31:0] EX_MEM_pc,
    input  wire        EX_MEM_res_from_mem,
    input  wire        EX_MEM_gr_we,
    input  wire        EX_MEM_mem_we,
    input  wire [ 1:0] EX_MEM_load_size,
    input  wire        EX_MEM_load_unsigned,
    input  wire [ 4:0] EX_MEM_dest,
    input  wire [31:0] EX_MEM_alu_result,
    input  wire [31:0] EX_MEM_rkd_value,
    input  wire        EX_MEM_csrrd,
    input  wire [13:0] EX_MEM_csr_num,
    input  wire        EX_MEM_csr_we,
    input  wire [31:0] EX_MEM_csr_wmask,
    input  wire [31:0] EX_MEM_csr_wvalue,
    input  wire        EX_MEM_valid,

    // forwarding to ID stage
    output wire [31:0] mem_forward_value,
    output wire        mem_forward_valid,

    // MEM/WB pipeline registers outputs
    output reg  [31:0] MEM_WB_pc,
    output reg         MEM_WB_res_from_mem,
    output reg         MEM_WB_gr_we,
    output reg  [ 4:0] MEM_WB_dest,
    output reg  [31:0] MEM_WB_alu_result,
    output reg  [31:0] MEM_WB_mem_result,
    output reg         MEM_WB_csrrd,
    output reg  [13:0] MEM_WB_csr_num,
    output reg         MEM_WB_csr_we,
    output reg  [31:0] MEM_WB_csr_wmask,
    output reg  [31:0] MEM_WB_csr_wvalue,
    output reg         MEM_WB_valid
);

// Data SRAM uses BRAM (synchronous read): address must be sent 1 cycle early (from EX stage)
assign data_sram_en    = 1'b1;
assign data_sram_addr  = ex_result;

reg  [3 :0] data_sram_we_r;
reg  [31:0] data_sram_wdata_r;
always @(*) begin
    data_sram_we_r    = 4'b0000;
    data_sram_wdata_r = ID_EX_rkd_value;
    if (ID_EX_mem_we && ID_EX_valid && !ex_ale) begin
        case (ID_EX_store_size)
            2'b00: begin
                data_sram_wdata_r = {4{ID_EX_rkd_value[7:0]}};
                case (ex_result[1:0])
                    2'b00: data_sram_we_r = 4'b0001;
                    2'b01: data_sram_we_r = 4'b0010;
                    2'b10: data_sram_we_r = 4'b0100;
                    2'b11: data_sram_we_r = 4'b1000;
                endcase
            end
            2'b01: begin
                data_sram_wdata_r = {2{ID_EX_rkd_value[15:0]}};
                data_sram_we_r    = ex_result[1] ? 4'b1100 : 4'b0011;
            end
            default: begin
                data_sram_wdata_r = ID_EX_rkd_value;
                data_sram_we_r    = 4'b1111;
            end
        endcase
    end
end

assign data_sram_we    = data_sram_we_r;
assign data_sram_wdata = data_sram_wdata_r;

// load data extend
wire [31:0] mem_load_data;
assign mem_load_data = mem_rdata_hold_valid ? mem_rdata_hold : data_sram_rdata;

reg  [31:0] mem_load_result;
always @(*) begin
    mem_load_result = mem_load_data;
    case (EX_MEM_load_size)
        2'b00: begin
            case (EX_MEM_alu_result[1:0])
                2'b00: mem_load_result = EX_MEM_load_unsigned ? {24'b0, mem_load_data[7:0]}   : {{24{mem_load_data[7]}},  mem_load_data[7:0]};
                2'b01: mem_load_result = EX_MEM_load_unsigned ? {24'b0, mem_load_data[15:8]}  : {{24{mem_load_data[15]}}, mem_load_data[15:8]};
                2'b10: mem_load_result = EX_MEM_load_unsigned ? {24'b0, mem_load_data[23:16]} : {{24{mem_load_data[23]}}, mem_load_data[23:16]};
                2'b11: mem_load_result = EX_MEM_load_unsigned ? {24'b0, mem_load_data[31:24]} : {{24{mem_load_data[31]}}, mem_load_data[31:24]};
            endcase
        end
        2'b01: begin
            if (EX_MEM_alu_result[1]) begin
                mem_load_result = EX_MEM_load_unsigned ? {16'b0, mem_load_data[31:16]} : {{16{mem_load_data[31]}}, mem_load_data[31:16]};
            end
            else begin
                mem_load_result = EX_MEM_load_unsigned ? {16'b0, mem_load_data[15:0]}  : {{16{mem_load_data[15]}}, mem_load_data[15:0]};
            end
        end
        default: begin
            mem_load_result = mem_load_data;
        end
    endcase
end

assign mem_forward_value = EX_MEM_res_from_mem ? mem_load_result : EX_MEM_alu_result;
assign mem_forward_valid = EX_MEM_valid && EX_MEM_gr_we && (EX_MEM_dest != 5'b0);

// MEM/WB pipeline register update
always @(posedge clk) begin
    if (reset) begin
        MEM_WB_pc           <= 32'b0;
        MEM_WB_res_from_mem <= 1'b0;
        MEM_WB_gr_we        <= 1'b0;
        MEM_WB_dest         <= 5'b0;
        MEM_WB_alu_result   <= 32'b0;
        MEM_WB_mem_result   <= 32'b0;
        MEM_WB_csrrd        <= 1'b0;
        MEM_WB_csr_num      <= 14'b0;
        MEM_WB_csr_we       <= 1'b0;
        MEM_WB_csr_wmask    <= 32'b0;
        MEM_WB_csr_wvalue   <= 32'b0;
        MEM_WB_valid        <= 1'b0;
    end
    else if (div_stall) begin
        // Hold MEM/WB while divider is busy.
    end
    else begin
        MEM_WB_pc           <= EX_MEM_pc;
        MEM_WB_res_from_mem <= EX_MEM_res_from_mem;
        MEM_WB_gr_we        <= EX_MEM_gr_we;
        MEM_WB_dest         <= EX_MEM_dest;
        MEM_WB_alu_result   <= EX_MEM_alu_result;
        MEM_WB_mem_result   <= mem_load_result;
        MEM_WB_csrrd        <= EX_MEM_csrrd;
        MEM_WB_csr_num      <= EX_MEM_csr_num;
        MEM_WB_csr_we       <= EX_MEM_csr_we;
        MEM_WB_csr_wmask    <= EX_MEM_csr_wmask;
        MEM_WB_csr_wvalue   <= EX_MEM_csr_wvalue;
        MEM_WB_valid        <= EX_MEM_valid;
    end
end

endmodule
