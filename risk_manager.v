module risk_manager (
    input  wire              clk,
    input  wire              rstn,
    
    // Position info
    input  wire [31:0]       current_position,
    input  wire signed [31:0] unrealized_pnl,
    input  wire signed [31:0] realized_pnl,
    
    // Order request
    input  wire [31:0]       order_qty,
    input  wire [7:0]        order_side,
    
    // Risk limits
    input  wire [31:0]       max_position,
    input  wire [31:0]       max_loss_limit,
    
    // Approval
    output reg               order_approved,
    output reg [7:0]         rejection_code,
    output reg  [31:0]       risk_violations
);

    localparam
        NO_ERROR             = 8'd0,
        MAX_POS_VIOLATION    = 8'd1,
        LOSS_LIMIT_VIOLATION = 8'd2,
        SIZE_VIOLATION       = 8'd3;
    
    // ========== PIPELINE STAGE 1: Register all inputs ==========
    reg [31:0]       s1_current_position;
    reg signed [31:0] s1_unrealized_pnl;
    reg signed [31:0] s1_realized_pnl;
    reg [31:0]       s1_order_qty;
    reg [7:0]        s1_order_side;
    reg [31:0]       s1_max_position;
    reg [31:0]       s1_max_loss_limit;
    
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            s1_current_position <= 0;
            s1_unrealized_pnl   <= 0;
            s1_realized_pnl     <= 0;
            s1_order_qty        <= 0;
            s1_order_side       <= 0;
            s1_max_position     <= 0;
            s1_max_loss_limit   <= 0;
        end else begin
            s1_current_position <= current_position;
            s1_unrealized_pnl   <= unrealized_pnl;
            s1_realized_pnl     <= realized_pnl;
            s1_order_qty        <= order_qty;
            s1_order_side       <= order_side;
            s1_max_position     <= max_position;
            s1_max_loss_limit   <= max_loss_limit;
        end
    end
    
    // ========== PIPELINE STAGE 2: Compute intermediate checks ==========
    reg signed [31:0] s2_new_position_buy;
    reg signed [31:0] s2_new_position_sell;
    reg signed [31:0] s2_total_pnl;
    reg [31:0]       s2_order_qty;
    reg [7:0]        s2_order_side;
    reg [31:0]       s2_max_position;
    reg signed [31:0] s2_max_loss_limit_signed;
    reg [31:0]       s2_max_order_size;
    
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            s2_new_position_buy  <= 0;
            s2_new_position_sell <= 0;
            s2_total_pnl         <= 0;
            s2_order_qty         <= 0;
            s2_order_side        <= 0;
            s2_max_position      <= 0;
            s2_max_loss_limit_signed <= 0;
            s2_max_order_size    <= 0;
        end else begin
            // Precompute position after buy/sell
            s2_new_position_buy  <= $signed(s1_current_position) + $signed(s1_order_qty);
            s2_new_position_sell <= $signed(s1_current_position) - $signed(s1_order_qty);
            
            // Precompute total P&L
            s2_total_pnl <= s1_unrealized_pnl + s1_realized_pnl;
            
            // Pass through control signals
            s2_order_qty    <= s1_order_qty;
            s2_order_side   <= s1_order_side;
            s2_max_position <= s1_max_position;
            s2_max_loss_limit_signed <= -$signed(s1_max_loss_limit);
            s2_max_order_size <= s1_max_position >> 1;  // 50% of max_position
        end
    end
    
    // ========== PIPELINE STAGE 3: Evaluate risk checks and output decision ==========
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            order_approved  <= 0;
            rejection_code  <= NO_ERROR;
            risk_violations <= 0;
        end else begin
            // Default: approve
            order_approved  <= 1'b1;
            rejection_code  <= NO_ERROR;
            
            // Check 1: Position limit
            if (s2_order_side == 8'd1) begin  // Buy
                if (s2_new_position_buy > $signed(s2_max_position)) begin
                    order_approved  <= 1'b0;
                    rejection_code  <= MAX_POS_VIOLATION;
                    risk_violations <= risk_violations + 1;
                end
            end else begin  // Sell
                if (s2_new_position_sell < 0 || 
                    s2_new_position_sell > $signed(s2_max_position)) begin
                    order_approved  <= 1'b0;
                    rejection_code  <= MAX_POS_VIOLATION;
                    risk_violations <= risk_violations + 1;
                end
            end
            
            // Check 2: Loss limit
            if (s2_total_pnl < s2_max_loss_limit_signed) begin
                order_approved  <= 1'b0;
                rejection_code  <= LOSS_LIMIT_VIOLATION;
                risk_violations <= risk_violations + 1;
            end
            
            // Check 3: Order size (max 50% of max position)
            if (s2_order_qty > s2_max_order_size) begin
                order_approved  <= 1'b0;
                rejection_code  <= SIZE_VIOLATION;
                risk_violations <= risk_violations + 1;
            end
        end
    end

endmodule
