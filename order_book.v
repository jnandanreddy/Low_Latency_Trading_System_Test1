module order_book (
    input  wire         clk,
    input  wire         rstn,
    
    // Input: Decoded market data
    input  wire [63:0]  symbol,
    input  wire [31:0]  price,
    input  wire [31:0]  quantity,
    input  wire [7:0]   side,        // 0=Buy, 1=Sell
    input  wire         update_valid,
    
    // Output: Best Bid/Ask (Top of Book)
    output reg  [31:0]  best_bid_price,
    output reg  [31:0]  best_bid_qty,
    output reg  [31:0]  best_ask_price,
    output reg  [31:0]  best_ask_qty,
    output reg          tob_valid,
    
    // Statistics
    output reg  [31:0]  bid_levels,     // Number of bid price levels
    output reg  [31:0]  ask_levels,
    output reg  [31:0]  update_count
);

    // ========== Order Book Storage ==========
    // Top 10 bid levels (sorted descending: highest price at [0])
    reg [31:0] bid_price [0:9];
    reg [31:0] bid_qty   [0:9];
    
    // Top 10 ask levels (sorted ascending: lowest price at [0])
    reg [31:0] ask_price [0:9];
    reg [31:0] ask_qty   [0:9];
    
    integer i;
    
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            // Initialize arrays
            for (i = 0; i < 10; i = i + 1) begin
                bid_price[i] <= 32'd0;
                bid_qty[i]   <= 32'd0;
                ask_price[i] <= 32'hFFFFFFFF;  // Max value = empty
                ask_qty[i]   <= 32'd0;
            end
            
            best_bid_price <= 32'd0;
            best_bid_qty   <= 32'd0;
            best_ask_price <= 32'hFFFFFFFF;
            best_ask_qty   <= 32'd0;
            tob_valid      <= 1'b0;
            
            bid_levels   <= 32'd0;
            ask_levels   <= 32'd0;
            update_count <= 32'd0;
            
        end else if (update_valid) begin
            update_count <= update_count + 1;
            
            if (side == 8'd0) begin
                // ========== BUY ORDER (Bid) ==========
                // Check if new price is better than current best bid
                if (price > bid_price[0]) begin
                    // New best bid: shift existing levels down
                    for (i = 9; i > 0; i = i - 1) begin
                        bid_price[i] <= bid_price[i-1];
                        bid_qty[i]   <= bid_qty[i-1];
                    end
                    // Insert new level at top
                    bid_price[0] <= price;
                    bid_qty[0]   <= quantity;
                    
                    // Increment level count (cap at 10)
                    if (bid_levels < 32'd10)
                        bid_levels <= bid_levels + 1;
                end
                
                // Update best bid outputs
                best_bid_price <= bid_price[0];
                best_bid_qty   <= bid_qty[0];
                tob_valid      <= 1'b1;
                
            end else begin
                // ========== SELL ORDER (Ask) ==========
                // Check if new price is better than current best ask
                if (price < ask_price[0]) begin
                    // New best ask: shift existing levels down
                    for (i = 9; i > 0; i = i - 1) begin
                        ask_price[i] <= ask_price[i-1];
                        ask_qty[i]   <= ask_qty[i-1];
                    end
                    // Insert new level at top
                    ask_price[0] <= price;
                    ask_qty[0]   <= quantity;
                    
                    // Increment level count (cap at 10)
                    if (ask_levels < 32'd10)
                        ask_levels <= ask_levels + 1;
                end
                
                // Update best ask outputs
                best_ask_price <= ask_price[0];
                best_ask_qty   <= ask_qty[0];
                tob_valid      <= 1'b1;
            end
        end
    end

endmodule
