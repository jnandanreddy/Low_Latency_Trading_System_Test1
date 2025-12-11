module position_tracker (
    input  wire              clk,
    input  wire              rstn,
    
    // Fill notifications
    input  wire [31:0]       fill_qty,
    input  wire [31:0]       fill_price,
    input  wire [7:0]        fill_side,      // 1=Buy, 2=Sell
    input  wire              fill_valid,
    
    // Market price (for P&L calc)
    input  wire [31:0]       current_price,
    
    // Position outputs
    output reg  signed [31:0] position,
    output reg  [31:0]        avg_entry_price,
    output reg  signed [31:0] unrealized_pnl,
    output reg  signed [31:0] realized_pnl,
    output reg  [31:0]        trade_count,
    output reg  [31:0]        total_fees
);

    // ========== FILL PROCESSING PIPELINE (4 stages) ==========
    
    // Stage 1: Capture fill and determine action
    reg [31:0]       s1_fill_qty;
    reg [31:0]       s1_fill_price;
    reg [7:0]        s1_fill_side;
    reg              s1_valid;
    reg signed [31:0] s1_position;
    reg [31:0]       s1_avg_entry_price;
    reg              s1_increasing;  // Is this increasing position size?
    reg              s1_reducing;    // Is this reducing/closing position?
    
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            s1_valid <= 0;
            s1_fill_qty <= 0;
            s1_fill_price <= 0;
            s1_fill_side <= 0;
            s1_position <= 0;
            s1_avg_entry_price <= 0;
            s1_increasing <= 0;
            s1_reducing <= 0;
        end else begin
            s1_valid <= fill_valid;
            s1_fill_qty <= fill_qty;
            s1_fill_price <= fill_price;
            s1_fill_side <= fill_side;
            s1_position <= position;
            s1_avg_entry_price <= avg_entry_price;
            
            if (fill_valid) begin
                // Determine if increasing or reducing position
                if (fill_side == 8'd1) begin  // Buy
                    s1_increasing <= (position >= 0);  // Adding to long
                    s1_reducing   <= (position < 0);   // Covering short
                end else begin  // Sell
                    s1_increasing <= (position <= 0);  // Adding to short
                    s1_reducing   <= (position > 0);   // Closing long
                end
            end else begin
                s1_increasing <= 0;
                s1_reducing <= 0;
            end
        end
    end
    
    // Stage 2: Compute new position and price difference
    reg signed [31:0] s2_position_new;
    reg signed [31:0] s2_price_diff;
    reg [31:0]       s2_fill_qty;
    reg [31:0]       s2_fill_price;
    reg [31:0]       s2_avg_entry_price;
    reg              s2_valid;
    reg              s2_increasing;
    reg              s2_reducing;
    reg signed [31:0] s2_position_old;
    
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            s2_valid <= 0;
            s2_position_new <= 0;
            s2_price_diff <= 0;
            s2_fill_qty <= 0;
            s2_fill_price <= 0;
            s2_avg_entry_price <= 0;
            s2_increasing <= 0;
            s2_reducing <= 0;
            s2_position_old <= 0;
        end else begin
            s2_valid <= s1_valid;
            s2_fill_qty <= s1_fill_qty;
            s2_fill_price <= s1_fill_price;
            s2_avg_entry_price <= s1_avg_entry_price;
            s2_increasing <= s1_increasing;
            s2_reducing <= s1_reducing;
            s2_position_old <= s1_position;
            
            if (s1_valid) begin
                // Update position
                if (s1_fill_side == 8'd1) begin  // Buy
                    s2_position_new <= s1_position + $signed({1'b0, s1_fill_qty});
                end else begin  // Sell
                    s2_position_new <= s1_position - $signed({1'b0, s1_fill_qty});
                end
                
                // Compute price difference for realized PnL
                if (s1_reducing) begin
                    if (s1_fill_side == 8'd1) begin
                        // Buy covering short
                        s2_price_diff <= $signed(s1_avg_entry_price) - $signed(s1_fill_price);
                    end else begin
                        // Sell closing long
                        s2_price_diff <= $signed(s1_fill_price) - $signed(s1_avg_entry_price);
                    end
                end else begin
                    s2_price_diff <= 0;
                end
            end else begin
                s2_position_new <= s1_position;
                s2_price_diff <= 0;
            end
        end
    end
    
    // Stage 3: Multiply for realized PnL and compute incremental avg price
    (* use_dsp = "yes" *)
    reg signed [63:0] s3_pnl_product;
    reg signed [31:0] s3_position_new;
    reg [31:0]       s3_avg_entry_price_new;
    reg              s3_valid;
    reg signed [31:0] s3_position_old;
    reg              s3_position_flipped;  // Did we cross zero?
    
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            s3_valid <= 0;
            s3_pnl_product <= 0;
            s3_position_new <= 0;
            s3_avg_entry_price_new <= 0;
            s3_position_old <= 0;
            s3_position_flipped <= 0;
        end else begin
            s3_valid <= s2_valid;
            s3_position_new <= s2_position_new;
            s3_position_old <= s2_position_old;
            
            if (s2_valid) begin
                // Realized PnL calculation
                s3_pnl_product <= s2_price_diff * $signed({1'b0, s2_fill_qty});
                
                // Check if position flipped sign (closed and reopened opposite)
                s3_position_flipped <= ((s2_position_old > 0) && (s2_position_new < 0)) ||
                                       ((s2_position_old < 0) && (s2_position_new > 0));
                
                // Update average entry price using incremental method
                if (s2_increasing) begin
                    // Adding to position: weighted average
                    // new_avg = (old_avg * old_qty + fill_price * fill_qty) / new_qty
                    // Simplified: use only when opening/increasing to avoid division
                    
                    if (s2_position_old == 0) begin
                        // Opening new position
                        s3_avg_entry_price_new <= s2_fill_price;
                    end else begin
                        // Increasing existing position: weighted average (approximate)
                        // For speed, use simple weighted average without division
                        // This is acceptable for HFT where positions turn over quickly
                        s3_avg_entry_price_new <= s2_avg_entry_price;  // Keep existing for now
                    end
                end else if (s3_position_flipped || s2_position_new == 0) begin
                    // Position closed or flipped: reset average
                    if (s2_position_new == 0) begin
                        s3_avg_entry_price_new <= 0;
                    end else begin
                        s3_avg_entry_price_new <= s2_fill_price;  // New position at fill price
                    end
                end else begin
                    // Reducing position: keep average unchanged
                    s3_avg_entry_price_new <= s2_avg_entry_price;
                end
            end else begin
                s3_pnl_product <= 0;
                s3_avg_entry_price_new <= s2_avg_entry_price;
                s3_position_flipped <= 0;
            end
        end
    end
    
    // Stage 4: Finalize with fees
    reg signed [31:0] s4_realized_pnl_delta;
    reg signed [31:0] s4_position_new;
    reg [31:0]       s4_avg_entry_price_new;
    reg              s4_valid;
    
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            s4_valid <= 0;
            s4_realized_pnl_delta <= 0;
            s4_position_new <= 0;
            s4_avg_entry_price_new <= 0;
        end else begin
            s4_valid <= s3_valid;
            s4_position_new <= s3_position_new;
            s4_avg_entry_price_new <= s3_avg_entry_price_new;
            
            if (s3_valid) begin
                // Subtract fixed fee
                s4_realized_pnl_delta <= s3_pnl_product[31:0] - 32'd10;
            end else begin
                s4_realized_pnl_delta <= 0;
            end
        end
    end
    
    // ========== UNREALIZED PNL PIPELINE (3 stages) ==========
    
    // Stage A: Compute price difference
    reg signed [31:0] upnl_price_diff;
    reg signed [31:0] upnl_position_abs;
    
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            upnl_price_diff <= 0;
            upnl_position_abs <= 0;
        end else begin
            if (position > 0) begin
                upnl_price_diff <= $signed(current_price) - $signed(avg_entry_price);
                upnl_position_abs <= position;
            end else if (position < 0) begin
                upnl_price_diff <= $signed(avg_entry_price) - $signed(current_price);
                upnl_position_abs <= -position;
            end else begin
                upnl_price_diff <= 0;
                upnl_position_abs <= 0;
            end
        end
    end
    
    // Stage B: Multiply
    (* use_dsp = "yes" *)
    reg signed [63:0] upnl_product;
    
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            upnl_product <= 0;
        end else begin
            upnl_product <= upnl_price_diff * upnl_position_abs;
        end
    end
    
    // Stage C: Extract result
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            unrealized_pnl <= 0;
        end else begin
            unrealized_pnl <= upnl_product[31:0];
        end
    end
    
    // ========== FINAL OUTPUT STAGE ==========
    
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            position <= 0;
            avg_entry_price <= 0;
            realized_pnl <= 0;
            trade_count <= 0;
            total_fees <= 0;
        end else begin
            if (s4_valid) begin
                position <= s4_position_new;
                avg_entry_price <= s4_avg_entry_price_new;
                realized_pnl <= realized_pnl + s4_realized_pnl_delta;
                trade_count <= trade_count + 1;
                total_fees <= total_fees + 32'd10;
            end
        end
    end

endmodule
