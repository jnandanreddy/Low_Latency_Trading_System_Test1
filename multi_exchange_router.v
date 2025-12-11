module multi_exchange_router (
    input  wire         clk,
    input  wire         rstn,

    // Order input (from strategy)
    input  wire [63:0]  symbol,
    input  wire [31:0]  order_qty,
    input  wire [31:0]  order_price,
    input  wire [7:0]   order_side,
    input  wire         order_valid,

    // Market data from each exchange
    input  wire [31:0]  nasdaq_best_bid,
    input  wire [31:0]  nasdaq_best_ask,
    input  wire [31:0]  nasdaq_liquidity,

    input  wire [31:0]  nyse_best_bid,
    input  wire [31:0]  nyse_best_ask,
    input  wire [31:0]  nyse_liquidity,

    input  wire [31:0]  cboe_best_bid,
    input  wire [31:0]  cboe_best_ask,
    input  wire [31:0]  cboe_liquidity,

    // Routed order output
    output reg  [1:0]   selected_exchange,  // 0=NASDAQ, 1=NYSE, 2=CBOE
    output reg  [63:0]  routed_symbol,
    output reg  [31:0]  routed_qty,
    output reg  [31:0]  routed_price,
    output reg  [7:0]   routed_side,
    output reg          routed_valid,

    // Statistics
    output reg  [31:0]  nasdaq_order_count,
    output reg  [31:0]  nyse_order_count,
    output reg  [31:0]  cboe_order_count
);

    localparam NASDAQ = 2'd0;
    localparam NYSE = 2'd1;
    localparam CBOE = 2'd2;

    // Smart routing logic
    wire [31:0] best_price_buy;
    wire [31:0] best_price_sell;
    wire [1:0] best_exchange_buy;
    wire [1:0] best_exchange_sell;

    // For BUY orders: find lowest ask
    assign best_price_buy = (nasdaq_best_ask < nyse_best_ask && nasdaq_best_ask < cboe_best_ask) ? nasdaq_best_ask :
                            (nyse_best_ask < cboe_best_ask) ? nyse_best_ask : cboe_best_ask;

    assign best_exchange_buy = (nasdaq_best_ask == best_price_buy) ? NASDAQ :
                               (nyse_best_ask == best_price_buy) ? NYSE : CBOE;

    // For SELL orders: find highest bid
    assign best_price_sell = (nasdaq_best_bid > nyse_best_bid && nasdaq_best_bid > cboe_best_bid) ? nasdaq_best_bid :
                             (nyse_best_bid > cboe_best_bid) ? nyse_best_bid : cboe_best_bid;

    assign best_exchange_sell = (nasdaq_best_bid == best_price_sell) ? NASDAQ :
                                (nyse_best_bid == best_price_sell) ? NYSE : CBOE;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            routed_valid <= 0;
            nasdaq_order_count <= 0;
            nyse_order_count <= 0;
            cboe_order_count <= 0;
        end else begin
            routed_valid <= 0;

            if (order_valid) begin
                routed_symbol <= symbol;
                routed_qty <= order_qty;
                routed_price <= order_price;
                routed_side <= order_side;
                routed_valid <= 1;

                // Route based on best price
                if (order_side == 8'd1) begin  // BUY
                    selected_exchange <= best_exchange_buy;

                    case (best_exchange_buy)
                        NASDAQ: nasdaq_order_count <= nasdaq_order_count + 1;
                        NYSE:   nyse_order_count <= nyse_order_count + 1;
                        CBOE:   cboe_order_count <= cboe_order_count + 1;
                    endcase
                end else begin  // SELL
                    selected_exchange <= best_exchange_sell;

                    case (best_exchange_sell)
                        NASDAQ: nasdaq_order_count <= nasdaq_order_count + 1;
                        NYSE:   nyse_order_count <= nyse_order_count + 1;
                        CBOE:   cboe_order_count <= cboe_order_count + 1;
                    endcase
                end
            end
        end
    end

endmodule
