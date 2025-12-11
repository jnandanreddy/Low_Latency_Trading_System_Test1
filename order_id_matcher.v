module order_id_matcher (
    input  wire         clk,
    input  wire         rstn,

    // New order sent (from order manager)
    input  wire [63:0]  sent_clordid,
    input  wire [31:0]  sent_qty,
    input  wire [31:0]  sent_price,
    input  wire         order_sent_valid,

    // Execution report received (from FIX decoder)
    input  wire [63:0]  exec_clordid,
    input  wire [63:0]  exec_orderid,
    input  wire [7:0]   exec_type,
    input  wire [7:0]   order_status,
    input  wire [31:0]  cum_qty,
    input  wire [31:0]  last_qty,
    input  wire [31:0]  last_price,
    input  wire         exec_report_valid,

    // Matched fill output
    output reg          fill_valid,
    output reg  [31:0]  fill_qty,
    output reg  [31:0]  fill_price,
    output reg          order_complete,

    // Statistics
    output reg  [31:0]  matched_count,
    output reg  [31:0]  unmatched_count,
    output reg  [31:0]  duplicate_count
);

    // Order tracking table (16 concurrent orders max)
    reg [63:0] order_table_clordid [0:15];
    reg [31:0] order_table_qty [0:15];
    reg [31:0] order_table_filled [0:15];
    reg [31:0] order_table_price [0:15];
    reg        order_table_active [0:15];

    integer i;
    reg [3:0] insert_index;
    reg [3:0] match_index;
    reg match_found;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            for (i = 0; i < 16; i = i + 1) begin
                order_table_active[i] <= 0;
                order_table_filled[i] <= 0;
            end
            matched_count <= 0;
            unmatched_count <= 0;
            duplicate_count <= 0;
            fill_valid <= 0;
        end else begin
            fill_valid <= 0;
            order_complete <= 0;

            // Insert new order into table
            if (order_sent_valid) begin
                // Find free slot
                insert_index = 0;
                for (i = 0; i < 16; i = i + 1) begin
                    if (!order_table_active[i]) begin
                        insert_index = i;
                    end
                end

                order_table_clordid[insert_index] <= sent_clordid;
                order_table_qty[insert_index] <= sent_qty;
                order_table_price[insert_index] <= sent_price;
                order_table_filled[insert_index] <= 0;
                order_table_active[insert_index] <= 1;
            end

            // Match execution report
            if (exec_report_valid) begin
                match_found = 0;

                for (i = 0; i < 16; i = i + 1) begin
                    if (order_table_active[i] && 
                        order_table_clordid[i] == exec_clordid) begin
                        match_found = 1;
                        match_index = i;
                    end
                end

                if (match_found) begin
                    // Check if this is a new fill (not duplicate)
                    if (cum_qty > order_table_filled[match_index]) begin
                        // New fill!
                        fill_valid <= 1;
                        fill_qty <= last_qty;
                        fill_price <= last_price;

                        order_table_filled[match_index] <= cum_qty;
                        matched_count <= matched_count + 1;

                        // Check if order is complete
                        if (cum_qty >= order_table_qty[match_index] || 
                            order_status == 8'h32) begin  // '2' = Filled
                            order_table_active[match_index] <= 0;
                            order_complete <= 1;
                        end
                    end else begin
                        // Duplicate fill
                        duplicate_count <= duplicate_count + 1;
                    end
                end else begin
                    // No matching order found
                    unmatched_count <= unmatched_count + 1;
                end
            end
        end
    end

endmodule
