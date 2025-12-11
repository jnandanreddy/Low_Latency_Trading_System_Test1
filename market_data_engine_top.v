module market_data_engine_top (
    input  wire       clk_125mhz,
    input  wire       rstn_raw,
    output wire [3:0] status_led
);

    wire clk_sys, clk_fast, locked, rstn;
    wire [7:0]   udp_data_in;
    wire         udp_valid_in;
    wire         udp_ready_out;
    wire [31:0]  best_bid_price;
    wire [31:0]  best_bid_qty;
    wire [31:0]  best_ask_price;
    wire [31:0]  best_ask_qty;
    wire         tob_valid;
    wire [31:0]  msg_count;
    wire [31:0]  decode_errors;
    wire [31:0]  update_count;

    clk_wiz_0 u_clk_wiz (
        .clk_in1  (clk_125mhz),
        .clk_out1 (clk_sys),
        .clk_out2 (clk_fast),
        .reset    (~rstn_raw),
        .locked   (locked)
    );

    assign rstn = rstn_raw & locked;
    assign udp_data_in  = 8'd0;
    assign udp_valid_in = 1'b0;

    // ADD THIS ATTRIBUTE to prevent optimization
    (* dont_touch = "true" *)
    market_data_engine u_engine (
        .clk_sys        (clk_sys),
        .clk_fast       (clk_fast),
        .rstn           (rstn),
        .udp_data_in    (udp_data_in),
        .udp_valid_in   (udp_valid_in),
        .udp_ready_out  (udp_ready_out),
        .best_bid_price (best_bid_price),
        .best_bid_qty   (best_bid_qty),
        .best_ask_price (best_ask_price),
        .best_ask_qty   (best_ask_qty),
        .tob_valid      (tob_valid),
        .status_led     (status_led),
        .msg_count      (msg_count),
        .decode_errors  (decode_errors),
        .update_count   (update_count)
    );

endmodule
