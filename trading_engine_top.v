module trading_engine_top (
    input  wire       clk_125mhz,
    input  wire       rstn_raw,
    output wire [7:0] status_leds
);

    wire clk_sys, locked, rstn;
    wire [31:0] best_bid_price, best_ask_price;
    wire        tob_valid;
    wire [31:0] trade_qty, order_qty, order_price;
    wire [7:0]  trade_side, order_side;
    wire        trade_signal, order_valid, risk_approved;
    wire [31:0] position, realized_pnl, unrealized_pnl;
    
    // Clock Wizard (single output clock)
    clk_wiz_0 u_clk_wiz (
        .clk_in1  (clk_125mhz),
        .clk_out1 (clk_sys),      // Only clk_out1 exists
        .reset    (~rstn_raw),
        .locked   (locked)
    );
    assign rstn = rstn_raw & locked;
    
    // Day 9: Market data (stubbed for now)
    // In real implementation, would interface to actual market data engine
    assign best_bid_price = 32'd15045;  // $150.45
    assign best_ask_price = 32'd15050;  // $150.50
    assign tob_valid = 1;
    
    // Trading strategy
    simple_trading_strategy u_strategy (
        .clk              (clk_sys),
        .rstn             (rstn),
        .best_bid_price   (best_bid_price),
        .best_ask_price   (best_ask_price),
        .current_position (position),
        .trade_signal     (trade_signal),
        .trade_qty        (trade_qty),
        .trade_side       (trade_side)
    );
    
    // Order manager
    order_manager u_order_mgr (
        .clk             (clk_sys),
        .rstn            (rstn),
        .best_bid_price  (best_bid_price),
        .best_ask_price  (best_ask_price),
        .tob_valid       (tob_valid),
        .trade_signal    (trade_signal),
        .trade_qty       (trade_qty),
        .trade_side      (trade_side),
        .risk_approved   (risk_approved),
        .order_qty       (order_qty),
        .order_price     (order_price),
        .order_side      (order_side),
        .order_valid     (order_valid),
        .position        (position),
        .realized_pnl    (realized_pnl),
        .order_count     (),
        .filled_count    (),
        .rejected_count  (),
        .state_out       ()
    );
    
    // Risk manager
    risk_manager u_risk (
        .clk              (clk_sys),
        .rstn             (rstn),
        .current_position (position),
        .unrealized_pnl   (unrealized_pnl),
        .realized_pnl     (realized_pnl),
        .order_qty        (order_qty),
        .order_side       (order_side),
        .max_position     (32'd1000),
        .max_loss_limit   (32'd50000),
        .order_approved   (risk_approved),
        .rejection_code   (),
        .risk_violations  ()
    );
    
    // Position tracker
    position_tracker u_pos_track (
        .clk              (clk_sys),
        .rstn             (rstn),
        .fill_qty         (order_qty),  // Simplified: auto-fill
        .fill_price       (order_price),
        .fill_side        (order_side),
        .fill_valid       (order_valid),
        .current_price    (best_bid_price),
        .position         (position),
        .avg_entry_price  (),
        .unrealized_pnl   (unrealized_pnl),
        .realized_pnl     (realized_pnl),
        .trade_count      (),
        .total_fees       ()
    );
    
    // FIX encoder
    fix_encoder u_fix_enc (
        .clk             (clk_sys),
        .rstn            (rstn),
        .symbol          (64'd0),
        .order_qty       (order_qty),
        .order_price     (order_price),
        .order_side      (order_side),
        .client_order_id (32'd0),
        .order_valid     (order_valid),
        .fix_data_out    (),
        .fix_valid_out   (),
        .fix_ready_in    (),
        .msg_count       (),
        .encode_errors   ()
    );
    
    // Status LEDs (corrected multiple assignments)
    assign status_leds = {
        4'b0000,                // [7:4] unused
        order_valid,            // [3] Blue: order sent
        ~risk_approved,         // [2] Red: risk violation (active low)
        trade_signal,           // [1] Orange: trading active
        locked                  // [0] Green: clock locked
    };

endmodule
