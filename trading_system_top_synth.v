module trading_system_top_synth (
    input  wire         clk_sys,          // 100 MHz
    input  wire         clk_eth,          // 156.25 MHz
    input  wire         rstn,
    
    // Minimal I/O for synthesis test
    output wire [7:0]   status_leds,
    output wire         order_valid_out,   // Single bit: order sent
    output wire         fill_received_out, // Single bit: fill received
    output wire         position_nonzero   // Single bit: have position
);

    // Internal signals (not exposed as I/O)
    wire [63:0] sfp_tx_data;
    wire        sfp_tx_valid;
    reg         sfp_tx_ready = 1'b1;
    
    reg  [63:0] sfp_rx_data = 64'h0;
    reg         sfp_rx_valid = 1'b0;
    
    wire [31:0] config_max_position = 32'd1000;
    wire [31:0] config_max_loss = 32'd5000;
    
    wire [31:0] total_orders_sent;
    wire [31:0] total_fills_received;
    wire signed [31:0] current_position;
    wire signed [31:0] realized_pnl;
    
    // Instantiate the real design
    trading_system_top dut (
        .clk_sys(clk_sys),
        .clk_eth(clk_eth),
        .rstn(rstn),
        .sfp_tx_data(sfp_tx_data),
        .sfp_tx_valid(sfp_tx_valid),
        .sfp_tx_ready(sfp_tx_ready),
        .sfp_rx_data(sfp_rx_data),
        .sfp_rx_valid(sfp_rx_valid),
        .config_max_position(config_max_position),
        .config_max_loss(config_max_loss),
        .status_leds(status_leds),
        .total_orders_sent(total_orders_sent),
        .total_fills_received(total_fills_received),
        .current_position(current_position),
        .realized_pnl(realized_pnl)
    );
    
    // Export single-bit status signals
    assign order_valid_out = sfp_tx_valid;
    assign fill_received_out = sfp_rx_valid;
    assign position_nonzero = (current_position != 0);

endmodule
