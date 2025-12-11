module market_data_engine (
    // Clocks
    input  wire         clk_sys,     // 100 MHz system clock
    input  wire         clk_fast,    // 250 MHz for parser
    input  wire         rstn,
    
    // Input: Raw UDP packets (from Day 8 Ethernet)
    input  wire [7:0]   udp_data_in,
    input  wire         udp_valid_in,
    output wire         udp_ready_out,
    
    // Output: Top of Book
    output wire [31:0]  best_bid_price,
    output wire [31:0]  best_bid_qty,
    output wire [31:0]  best_ask_price,
    output wire [31:0]  best_ask_qty,
    output wire         tob_valid,
    
    // Status LEDs
    output wire [3:0]   status_led,
    
    // Statistics
    output wire [31:0]  msg_count,
    output wire [31:0]  decode_errors,
    output wire [31:0]  update_count
);

    // ========== Internal Signals ==========
    wire [31:0] template_id;
    wire [63:0] symbol;
    wire [31:0] price;
    wire [31:0] quantity;
    wire [7:0]  side;
    wire [63:0] timestamp;
    wire        decoded_valid;

    // ========== FAST Parser Instance ==========
    fast_parser parser (
        .clk            (clk_fast),
        .rstn           (rstn),
        .fast_data_in   (udp_data_in),
        .fast_valid_in  (udp_valid_in),
        .fast_ready_out (udp_ready_out),
        .template_id    (template_id),
        .symbol         (symbol),
        .price          (price),
        .quantity       (quantity),
        .side           (side),
        .timestamp      (timestamp),
        .decoded_valid  (decoded_valid),
        .msg_count      (msg_count),
        .decode_errors  (decode_errors)
    );
    
    // ========== CDC: Clock Domain Crossing ==========
    // From clk_fast (250 MHz) to clk_sys (100 MHz)
    reg [63:0] symbol_cdc_s1, symbol_cdc_s2;
    reg [31:0] price_cdc_s1,  price_cdc_s2;
    reg [31:0] qty_cdc_s1,    qty_cdc_s2;
    reg [7:0]  side_cdc_s1,   side_cdc_s2;
    reg        valid_cdc_s1,  valid_cdc_s2;
    
    always @(posedge clk_sys or negedge rstn) begin
        if (!rstn) begin
            symbol_cdc_s1 <= 64'd0;
            symbol_cdc_s2 <= 64'd0;
            price_cdc_s1  <= 32'd0;
            price_cdc_s2  <= 32'd0;
            qty_cdc_s1    <= 32'd0;
            qty_cdc_s2    <= 32'd0;
            side_cdc_s1   <= 8'd0;
            side_cdc_s2   <= 8'd0;
            valid_cdc_s1  <= 1'b0;
            valid_cdc_s2  <= 1'b0;
        end else begin
            // 2-FF synchronizer
            symbol_cdc_s1 <= symbol;
            symbol_cdc_s2 <= symbol_cdc_s1;
            price_cdc_s1  <= price;
            price_cdc_s2  <= price_cdc_s1;
            qty_cdc_s1    <= quantity;
            qty_cdc_s2    <= qty_cdc_s1;
            side_cdc_s1   <= side;
            side_cdc_s2   <= side_cdc_s1;
            valid_cdc_s1  <= decoded_valid;
            valid_cdc_s2  <= valid_cdc_s1;
        end
    end
    
    // ========== Order Book Instance ==========
    order_book book (
        .clk            (clk_sys),
        .rstn           (rstn),
        .symbol         (symbol_cdc_s2),
        .price          (price_cdc_s2),
        .quantity       (qty_cdc_s2),
        .side           (side_cdc_s2),
        .update_valid   (valid_cdc_s2),
        .best_bid_price (best_bid_price),
        .best_bid_qty   (best_bid_qty),
        .best_ask_price (best_ask_price),
        .best_ask_qty   (best_ask_qty),
        .tob_valid      (tob_valid),
        .update_count   (update_count)
    );
    
    // ========== Status LEDs ==========
    // Combine all status into one 4-bit vector
    assign status_led[0] = tob_valid;                  // Book has valid TOB
    assign status_led[1] = decoded_valid;              // Parser active
    assign status_led[2] = msg_count[15];              // High message rate indicator
    assign status_led[3] = (decode_errors != 32'd0);   // Errors detected

endmodule
