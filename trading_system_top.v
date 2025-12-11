module trading_system_top (
    input  wire         clk_sys,          // 100 MHz system clock
    input  wire         clk_eth,          // 156.25 MHz Ethernet clock
    input  wire         rstn,
    
    // Ethernet PHY interface (10G SFP+)
    output wire [63:0]  sfp_tx_data,
    output wire         sfp_tx_valid,
    input  wire         sfp_tx_ready,
    
    input  wire [63:0]  sfp_rx_data,
    input  wire         sfp_rx_valid,
    
    // Configuration (from PCIe or AXI)
    input  wire [31:0]  config_max_position,
    input  wire [31:0]  config_max_loss,
    
    // Status LEDs
    output wire [7:0]   status_leds,
    
    // Performance counters
    output wire [31:0]  total_orders_sent,
    output wire [31:0]  total_fills_received,
    output wire signed [31:0] current_position,
    output wire signed [31:0] realized_pnl
);

    // ========================================
    // Internal Signals (clk_sys domain)
    // ========================================
    
    // Market data
    wire [31:0] best_bid_sys, best_ask_sys;
    wire        tob_valid_sys;
    
    // Strategy signals
    wire        strategy_signal;
    wire [31:0] strategy_qty;
    wire        strategy_side;
    
    // Risk approval
    wire        risk_approved;
    
    // Order signals (clk_sys domain)
    wire [31:0] order_qty_sys, order_price_sys;
    wire [7:0]  order_side_sys;
    wire        order_valid_sys;
    
    // Position and P&L
    wire signed [31:0] unrealized_pnl;
    wire [31:0] avg_entry_price;
    wire [31:0] trade_count;
    wire [31:0] total_fees;
    
    // ========================================
    // CDC: clk_sys -> clk_eth (with ASYNC_REG)
    // ========================================
    (* ASYNC_REG = "TRUE" *)
    reg [31:0] order_qty_eth_s1, order_qty_eth_s2;
    (* ASYNC_REG = "TRUE" *)
    reg [31:0] order_price_eth_s1, order_price_eth_s2;
    (* ASYNC_REG = "TRUE" *)
    reg [7:0]  order_side_eth_s1, order_side_eth_s2;
    (* ASYNC_REG = "TRUE" *)
    reg        order_valid_eth_s1, order_valid_eth_s2;
    
    always @(posedge clk_eth or negedge rstn) begin
        if (!rstn) begin
            order_qty_eth_s1 <= 0;
            order_qty_eth_s2 <= 0;
            order_price_eth_s1 <= 0;
            order_price_eth_s2 <= 0;
            order_side_eth_s1 <= 0;
            order_side_eth_s2 <= 0;
            order_valid_eth_s1 <= 0;
            order_valid_eth_s2 <= 0;
        end else begin
            // First stage: capture from clk_sys domain
            order_qty_eth_s1 <= order_qty_sys;
            order_price_eth_s1 <= order_price_sys;
            order_side_eth_s1 <= order_side_sys;
            order_valid_eth_s1 <= order_valid_sys;
            
            // Second stage: stable output
            order_qty_eth_s2 <= order_qty_eth_s1;
            order_price_eth_s2 <= order_price_eth_s1;
            order_side_eth_s2 <= order_side_eth_s1;
            order_valid_eth_s2 <= order_valid_eth_s1;
        end
    end
    
    // ========================================
    // MODULE INSTANTIATIONS
    // ========================================
    
    // 1. Market Data Engine (Day 9)
    market_data_engine u_market_data (
        .clk_sys        (clk_sys),
        .clk_fast       (clk_sys),           // Use same clock for simplicity
        .rstn           (rstn),
        .udp_data_in    (8'h00),             // Stub
        .udp_valid_in   (1'b0),
        .udp_ready_out  (),
        .best_bid_price (best_bid_sys),
        .best_bid_qty   (),
        .best_ask_price (best_ask_sys),
        .best_ask_qty   (),
        .tob_valid      (tob_valid_sys),
        .status_led     (),
        .msg_count      (),
        .decode_errors  (),
        .update_count   ()
    );
    
    // 2. Trading Strategy (Day 10/12 - optimized version)
    simple_trading_strategy_opt u_strategy (
        .clk                (clk_sys),
        .rstn               (rstn),
        .best_bid           (best_bid_sys),
        .best_ask           (best_ask_sys),
        .tob_valid          (tob_valid_sys),
        .current_position   (current_position),
        .strategy_signal    (strategy_signal),
        .strategy_qty       (strategy_qty),
        .strategy_side      (strategy_side),
        .target_profit      ()
    );
    
    // 3. Risk Manager (Day 10)
    risk_manager u_risk (
        .clk                (clk_sys),
        .rstn               (rstn),
        .current_position   (current_position),
        .unrealized_pnl     (unrealized_pnl),
        .realized_pnl       (realized_pnl),
        .order_qty          (strategy_qty),
        .order_side         (strategy_side),
        .max_position       (config_max_position),
        .max_loss_limit     (config_max_loss),
        .order_approved     (risk_approved),
        .rejection_code     (),
        .risk_violations    ()
    );
    
    // 4. Order Manager (Day 10)
    order_manager u_order_mgr (
        .clk                (clk_sys),
        .rstn               (rstn),
        .best_bid_price     (best_bid_sys),
        .best_ask_price     (best_ask_sys),
        .tob_valid          (tob_valid_sys),
        .trade_signal       (strategy_signal),
        .trade_qty          (strategy_qty),
        .trade_side         (strategy_side),
        .risk_approved      (risk_approved),
        .order_qty          (order_qty_sys),
        .order_price        (order_price_sys),
        .order_side         (order_side_sys),
        .order_valid        (order_valid_sys),
        .position           (current_position),
        .realized_pnl       (realized_pnl),
        .order_count        (total_orders_sent),
        .filled_count       (),
        .rejected_count     (),
        .state_out          ()
    );
    
    // 5. FIX Encoder (clk_eth domain)
    wire [7:0] fix_tx_data;
    wire fix_tx_valid;
    wire fix_tx_ready;
    
    fix_encoder u_fix_encoder (
        .clk                (clk_eth),
        .rstn               (rstn),
        .symbol             (64'h4141504C00000000),  // "AAPL    "
        .order_qty          (order_qty_eth_s2),
        .order_price        (order_price_eth_s2),
        .order_side         (order_side_eth_s2),
        .client_order_id    (32'd1),
        .order_valid        (order_valid_eth_s2),
        .fix_data_out       (fix_tx_data),
        .fix_valid_out      (fix_tx_valid),
        .fix_ready_in       (fix_tx_ready),
        .msg_count          (),
        .encode_errors      ()
    );
    
    // 6. Ethernet TX Wrapper (clk_eth domain)
    ethernet_tx_wrapper u_eth_tx (
        .clk156             (clk_eth),
        .rstn               (rstn),
        .fix_data_in        ({56'h00, fix_tx_data}),
        .fix_valid_in       (fix_tx_valid),
        .fix_last_in        (1'b0),
        .fix_ready_out      (fix_tx_ready),
        .eth_tx_data        (sfp_tx_data),
        .eth_tx_valid       (sfp_tx_valid),
        .eth_tx_last        (),
        .eth_tx_ready       (sfp_tx_ready),
        .tx_frame_count     (),
        .tx_byte_count      ()
    );
    
    // 7. FIX Decoder (clk_eth domain) - Execution reports
    wire [63:0] exec_order_id;
    wire [31:0] exec_fill_qty, exec_fill_price;
    wire [7:0]  exec_fill_side;
    wire exec_report_valid;
    reg [31:0] fill_counter_eth;
    
    // Simplified decoder stub: extract from sfp_rx_data
    // In real system, this would be a full FIX 4.2/4.4 parser
    assign exec_order_id = sfp_rx_data;
    assign exec_fill_qty = 32'd100;
    assign exec_fill_price = 32'd15050;
    assign exec_fill_side = 8'd1;  // BUY
    assign exec_report_valid = sfp_rx_valid;
    
    // Count fills in clk_eth domain
    always @(posedge clk_eth or negedge rstn) begin
        if (!rstn)
            fill_counter_eth <= 0;
        else if (exec_report_valid)
            fill_counter_eth <= fill_counter_eth + 1;
    end
    
    // 8. CDC: fill signals from clk_eth -> clk_sys
    (* ASYNC_REG = "TRUE" *)
    reg fill_valid_sys_s1, fill_valid_sys_s2;
    (* ASYNC_REG = "TRUE" *)
    reg [31:0] fill_qty_sys_s1, fill_qty_sys_s2;
    (* ASYNC_REG = "TRUE" *)
    reg [31:0] fill_price_sys_s1, fill_price_sys_s2;
    (* ASYNC_REG = "TRUE" *)
    reg [7:0]  fill_side_sys_s1, fill_side_sys_s2;
    (* ASYNC_REG = "TRUE" *)
    reg [31:0] fill_count_sys_s1, fill_count_sys_s2;
    
    always @(posedge clk_sys or negedge rstn) begin
        if (!rstn) begin
            fill_valid_sys_s1 <= 0;
            fill_valid_sys_s2 <= 0;
            fill_qty_sys_s1 <= 0;
            fill_qty_sys_s2 <= 0;
            fill_price_sys_s1 <= 0;
            fill_price_sys_s2 <= 0;
            fill_side_sys_s1 <= 0;
            fill_side_sys_s2 <= 0;
            fill_count_sys_s1 <= 0;
            fill_count_sys_s2 <= 0;
        end else begin
            // First stage: capture from clk_eth domain
            fill_valid_sys_s1 <= exec_report_valid;
            fill_qty_sys_s1 <= exec_fill_qty;
            fill_price_sys_s1 <= exec_fill_price;
            fill_side_sys_s1 <= exec_fill_side;
            fill_count_sys_s1 <= fill_counter_eth;
            
            // Second stage: stable output
            fill_valid_sys_s2 <= fill_valid_sys_s1;
            fill_qty_sys_s2 <= fill_qty_sys_s1;
            fill_price_sys_s2 <= fill_price_sys_s1;
            fill_side_sys_s2 <= fill_side_sys_s1;
            fill_count_sys_s2 <= fill_count_sys_s1;
        end
    end
    
    assign total_fills_received = fill_count_sys_s2;
    
    // 9. Position Tracker (clk_sys domain)
    position_tracker u_position (
        .clk                (clk_sys),
        .rstn               (rstn),
        .fill_qty           (fill_qty_sys_s2),
        .fill_price         (fill_price_sys_s2),
        .fill_side          (fill_side_sys_s2),
        .fill_valid         (fill_valid_sys_s2),
        .current_price      (best_bid_sys),     // Use bid as market price
        .position           (current_position),
        .avg_entry_price    (avg_entry_price),
        .unrealized_pnl     (unrealized_pnl),
        .realized_pnl       (realized_pnl),
        .trade_count        (trade_count),
        .total_fees         (total_fees)
    );
    
    // 10. Latency Counter (clk_sys domain)
    wire [15:0] latency_clocks;
    wire latency_valid;

    latency_counter u_latency (
        .clk            (clk_sys),
        .rstn           (rstn),
        .tob_valid      (tob_valid_sys),
        .order_valid    (order_valid_sys),
        .latency_clocks (latency_clocks),
        .latency_valid  (latency_valid)
    );
    
    // ========================================
    // STATUS LEDS (non-critical path)
    // ========================================
    assign status_leds[0] = tob_valid_sys;           // Market data active
    assign status_leds[1] = order_valid_sys;         // Order sent
    assign status_leds[2] = fix_tx_valid;            // FIX encoding active
    assign status_leds[3] = exec_report_valid;       // Fill received (clk_eth)
    assign status_leds[4] = fill_valid_sys_s2;       // Fill processed (clk_sys)
    assign status_leds[5] = (current_position != 0); // Non-zero position
    assign status_leds[6] = risk_approved;           // Risk check passed
    assign status_leds[7] = latency_valid;           // Latency measurement valid

endmodule
