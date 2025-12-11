module simple_trading_strategy_opt (
    input wire clk,
    input wire rstn,
    input wire [31:0] best_bid,
    input wire [31:0] best_ask,
    input wire tob_valid,
    input wire signed [31:0] current_position,
    
    output reg strategy_signal,
    output reg [31:0] strategy_qty,
    output reg strategy_side,
    output reg [31:0] target_profit
);

// Pipeline Stage 1: Spread calculation
reg [31:0] spread_s1;
reg tob_valid_s1;
reg signed [31:0] position_s1;
reg [31:0] best_ask_s1;

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        spread_s1 <= 0;
        tob_valid_s1 <= 0;
        position_s1 <= 0;
        best_ask_s1 <= 0;
    end else begin
        spread_s1 <= best_ask - best_bid;  // ← Stage 1
        tob_valid_s1 <= tob_valid;
        position_s1 <= current_position;
        best_ask_s1 <= best_ask;
    end
end

// Pipeline Stage 2: Decision logic
reg [1:0] state;
localparam WAITING = 0, BOUGHT = 1;
reg [31:0] entry_price;

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        state <= WAITING;
        strategy_signal <= 0;
        strategy_qty <= 0;
        strategy_side <= 0;
        target_profit <= 0;
        entry_price <= 0;
    end else begin
        case (state)
            WAITING: begin
                // Now only comparisons (fast)
                if (tob_valid_s1 && (spread_s1 < 32'd100) && (position_s1 == 0)) begin
                    strategy_signal <= 1;
                    strategy_qty <= 100;
                    strategy_side <= 1;
                    target_profit <= 50;
                    entry_price <= best_ask_s1;
                    state <= BOUGHT;
                end else begin
                    strategy_signal <= 0;
                end
            end
            
            BOUGHT: begin
                if (tob_valid_s1 && (best_bid >= entry_price + target_profit)) begin
                    strategy_signal <= 1;
                    strategy_qty <= 100;
                    strategy_side <= 0;  // SELL
                    state <= WAITING;
                end else begin
                    strategy_signal <= 0;
                end
            end
            
            default: state <= WAITING;
        endcase
    end
end

endmodule
