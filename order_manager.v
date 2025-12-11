module order_manager (
    input  wire         clk,
    input  wire         rstn,
    
    // Market data input
    input  wire [31:0]  best_bid_price,
    input  wire [31:0]  best_ask_price,
    input  wire         tob_valid,
    
    // Trading strategy input
    input  wire         trade_signal,
    input  wire [31:0]  trade_qty,
    input  wire [7:0]   trade_side,
    
    // Risk approval
    input  wire         risk_approved,
    
    // Order to FIX encoder
    output reg  [31:0]  order_qty,
    output reg  [31:0]  order_price,
    output reg  [7:0]   order_side,          // FIXED: was [7:8]
    output reg          order_valid,
    
    // Position tracking (READ-ONLY, driven by position_tracker)
    input  wire [31:0]  position,            // CHANGED to input
    input  wire [31:0]  realized_pnl,        // CHANGED to input
    
    // Counters
    output reg  [31:0]  order_count,
    output reg  [31:0]  filled_count,
    output reg  [31:0]  rejected_count,
    output reg  [3:0]   state_out
);

    reg [3:0] state, next_state;
    reg [31:0] pending_qty;
    reg [31:0] entry_price;
    
    localparam
        IDLE = 4'd0,
        RISK_CHECK = 4'd1,
        PREPARE_ORDER = 4'd2,
        SEND_ORDER = 4'd3,
        AWAITING_FILL = 4'd4,
        FILLED = 4'd5,
        REJECTED = 4'd6;
    
    // State register
    always @(posedge clk or negedge rstn) begin
        if (!rstn)
            state <= IDLE;
        else
            state <= next_state;
    end
    
    // State machine combinational logic
    always @(*) begin
        next_state = state;
        
        case (state)
            IDLE: begin
                if (trade_signal) begin
                    next_state = RISK_CHECK;
                end
            end
            
            RISK_CHECK: begin
                if (risk_approved) begin
                    next_state = PREPARE_ORDER;
                end else begin
                    next_state = REJECTED;
                end
            end
            
            PREPARE_ORDER: begin
                next_state = SEND_ORDER;
            end
            
            SEND_ORDER: begin
                next_state = AWAITING_FILL;
            end
            
            AWAITING_FILL: begin
                // In real implementation: wait for execution report
                // For simulation: auto-fill after 10 cycles
                next_state = FILLED;
            end
            
            FILLED: begin
                next_state = IDLE;
            end
            
            REJECTED: begin
                next_state = IDLE;
            end
        endcase
    end
    
    // Sequential logic (state actions)
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            order_valid <= 0;
            order_count <= 0;
            filled_count <= 0;
            rejected_count <= 0;
            // REMOVED: position <= 0;
            // REMOVED: realized_pnl <= 0;
        end else begin
            order_valid <= 0;
            state_out <= state;
            
            case (state)
                IDLE: begin
                    if (trade_signal) begin
                        pending_qty <= trade_qty;
                        order_side <= trade_side;
                    end
                end
                
                PREPARE_ORDER: begin
                    // Select price: buy at best_ask, sell at best_bid
                    if (trade_side == 1) begin  // Buy
                        order_price <= best_ask_price;
                    end else begin              // Sell
                        order_price <= best_bid_price;
                    end
                    
                    order_qty <= pending_qty;
                    entry_price <= (trade_side == 1) ? best_ask_price : best_bid_price;
                end
                
                SEND_ORDER: begin
                    order_valid <= 1;
                end
                
                FILLED: begin
                    // REMOVED position and realized_pnl updates
                    // position_tracker owns these signals now
                    filled_count <= filled_count + 1;
                    order_count <= order_count + 1;
                end
                
                REJECTED: begin
                    rejected_count <= rejected_count + 1;
                    order_count <= order_count + 1;
                end
            endcase
        end
    end

endmodule
