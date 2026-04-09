// Minimal behavioral stub for non-Vivado simulation (iverilog).
// Provides AXI-Stream-like handshake and returns {remainder[31:0], quotient[31:0]}.

module div_signed(
    input         aclk,
    input         s_axis_divisor_tvalid,
    output        s_axis_divisor_tready,
    input  [31:0] s_axis_divisor_tdata,
    input         s_axis_dividend_tvalid,
    output        s_axis_dividend_tready,
    input  [31:0] s_axis_dividend_tdata,
    output reg    m_axis_dout_tvalid,
    output reg [63:0] m_axis_dout_tdata
);

    localparam integer LATENCY = 8;

    reg        busy;
    reg signed [31:0] dividend_r;
    reg signed [31:0] divisor_r;
    reg [7:0]  cnt;

    assign s_axis_divisor_tready  = ~busy;
    assign s_axis_dividend_tready = ~busy;

    wire accept = (~busy) && s_axis_divisor_tvalid && s_axis_dividend_tvalid;

    wire divisor_is_zero = (divisor_r == 32'sd0);
    wire overflow_case   = (dividend_r == 32'sh8000_0000) && (divisor_r == -32'sd1);

    wire signed [31:0] quot_s = divisor_is_zero ? -32'sd1 : (overflow_case ? dividend_r : (dividend_r / divisor_r));
    wire signed [31:0] rem_s  = divisor_is_zero ? dividend_r : (overflow_case ? 32'sd0    : (dividend_r % divisor_r));

    always @(posedge aclk) begin
        m_axis_dout_tvalid <= 1'b0;

        if (accept) begin
            busy       <= 1'b1;
            dividend_r <= $signed(s_axis_dividend_tdata);
            divisor_r  <= $signed(s_axis_divisor_tdata);
            cnt        <= LATENCY;
        end
        else if (busy) begin
            if (cnt != 8'd0) begin
                cnt <= cnt - 8'd1;
            end
            else begin
                m_axis_dout_tvalid <= 1'b1;
                m_axis_dout_tdata  <= {rem_s[31:0], quot_s[31:0]};
                busy               <= 1'b0;
            end
        end

        if (!busy && !accept) begin
            // keep registers stable when idle
        end
    end

    initial begin
        busy            = 1'b0;
        dividend_r      = 32'sd0;
        divisor_r       = 32'sd0;
        cnt             = 8'b0;
        m_axis_dout_tvalid = 1'b0;
        m_axis_dout_tdata  = 64'b0;
    end

endmodule
