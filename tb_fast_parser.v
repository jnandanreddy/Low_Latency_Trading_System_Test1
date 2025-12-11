`timescale 1ms / 1ps

module tb_fast_parser;

    // ========== Testbench Signals ==========
    reg         clk_sys;
    reg         clk_fast;
    reg         rstn;
    
    reg  [7:0]  udp_data_in;
    reg         udp_valid_in;
    wire        udp_ready_out;
    
    wire [31:0] best_bid_price;
    wire [31:0] best_bid_qty;
    wire [31:0] best_ask_price;
    wire [31:0] best_ask_qty;
    wire        tob_valid;
    wire [3:0]  status_led;
    wire [31:0] msg_count;
    wire [31:0] decode_errors;
    wire [31:0] update_count;
    
    // ========== Task loop variable (declared at module level) ==========
    integer i;
    
    // ========== DUT Instantiation ==========
    market_data_engine dut (
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
    
    // ========== Clock Generation ==========
    // 100 MHz system clock (10 ns period)
    always #5 clk_sys = ~clk_sys;
    
    // 250 MHz fast clock (4 ns period)
    always #2 clk_fast = ~clk_fast;
    
    // ========== Main Test Sequence ==========
    initial begin
        // Initialize signals
        clk_sys      = 1'b0;
        clk_fast     = 1'b0;
        rstn         = 1'b0;
        udp_valid_in = 1'b0;
        udp_data_in  = 8'd0;
        
        // Hold reset for 100 ns
        #100;
        rstn = 1'b1;
        #100;
        
        $display("========================================");
        $display("Day 9: FAST Parser + Order Book Test");
        $display("========================================\n");
        
        // ========== Test 1: BUY Order ==========
        $display("[TEST 1] FAST message: BUY AAPL @ 150.50, qty=1000");
        send_fast_message(
            8'd1,                       // Template ID
            64'h4141504C_00000000,      // "AAPL" (41=A, 41=A, 50=P, 4C=L)
            32'd15050,                  // Price: 150.50 (cents)
            32'd1000,                   // Quantity
            8'd0,                       // Side: 0=Buy
            64'd1234567890              // Timestamp
        );
        
        // Wait for CDC and order book update
        #1000;
        
        // ========== Test 2: SELL Order ==========
        $display("[TEST 2] FAST message: SELL AAPL @ 150.55, qty=500");
        send_fast_message(
            8'd1,                       // Template ID
            64'h4141504C_00000000,      // "AAPL"
            32'd15055,                  // Price: 150.55 (cents)
            32'd500,                    // Quantity
            8'd1,                       // Side: 1=Sell
            64'd1234567891              // Timestamp
        );
        
        // Wait for processing
        #1000;
        
        // ========== Test 3: Another BUY (worse price) ==========
        $display("[TEST 3] FAST message: BUY AAPL @ 150.45, qty=2000");
        send_fast_message(
            8'd1,
            64'h4141504C_00000000,
            32'd15045,                  // Price: 150.45 (worse bid)
            32'd2000,
            8'd0,
            64'd1234567892
        );
        
        #1000;
        
        // ========== Test 4: Better BUY ==========
        $display("[TEST 4] FAST message: BUY AAPL @ 150.52, qty=750");
        send_fast_message(
            8'd1,
            64'h4141504C_00000000,
            32'd15052,                  // Price: 150.52 (new best bid)
            32'd750,
            8'd0,
            64'd1234567893
        );
        
        #1000;
        
        // ========== Verify Results ==========
        $display("\n----------------------------------------");
        $display("RESULTS:");
        $display("----------------------------------------");
        
        if (tob_valid) begin
            $display("Top of Book: VALID");
            $display("  Best Bid: $%0d.%02d @ qty %0d", 
                     best_bid_price/100, best_bid_price%100, best_bid_qty);
            $display("  Best Ask: $%0d.%02d @ qty %0d", 
                     best_ask_price/100, best_ask_price%100, best_ask_qty);
            $display("  Spread:   %0d cents", best_ask_price - best_bid_price);
        end else begin
            $display("ERROR: Top of Book NOT VALID");
        end
        
        $display("\nStatistics:");
        $display("  Messages decoded: %0d", msg_count);
        $display("  Decode errors:    %0d", decode_errors);
        $display("  Book updates:     %0d", update_count);
        
        $display("\nStatus LEDs: %b", status_led);
        $display("  LED[0] (TOB valid):    %b", status_led[0]);
        $display("  LED[1] (Parser active):%b", status_led[1]);
        $display("  LED[2] (High rate):    %b", status_led[2]);
        $display("  LED[3] (Errors):       %b", status_led[3]);
        
        // ========== Pass/Fail Check ==========
        $display("\n----------------------------------------");
        if (tob_valid && (decode_errors == 0) && (msg_count == 4)) begin
            $display("TEST PASSED");
        end else begin
            $display("TEST FAILED");
            if (!tob_valid)         $display("  - TOB not valid");
            if (decode_errors != 0) $display("  - Decode errors: %0d", decode_errors);
            if (msg_count != 4)     $display("  - Expected 4 messages, got %0d", msg_count);
        end
        $display("----------------------------------------\n");
        
        #500;
        $display("========================================");
        $display("Simulation Complete");
        $display("========================================");
        $finish;
    end
    
    // ========== Task: Send FAST Message ==========
    // Sends a complete FAST-encoded market data message
    task send_fast_message;
        input [7:0]  template_id;
        input [63:0] symbol;
        input [31:0] price;
        input [31:0] quantity;
        input [7:0]  side;
        input [63:0] timestamp;
    begin
        // Wait for clock edge
        @(posedge clk_fast);
        
        // ===== PMAP (Presence Map) =====
        // All bits set = all fields present
        udp_data_in  = 8'hFF;
        udp_valid_in = 1'b1;
        @(posedge clk_fast);
        
        // ===== Template ID =====
        // MSB=1 indicates last byte of varint
        udp_data_in = template_id | 8'h80;
        @(posedge clk_fast);
        
        // ===== Symbol (8 bytes, big-endian) =====
        for (i = 7; i >= 0; i = i - 1) begin
            udp_data_in = symbol[(i*8) +: 8];
            @(posedge clk_fast);
        end
        
        // ===== Price (4 bytes, little-endian, last byte has MSB=1) =====
        udp_data_in = price[7:0];
        @(posedge clk_fast);
        udp_data_in = price[15:8];
        @(posedge clk_fast);
        udp_data_in = price[23:16];
        @(posedge clk_fast);
        udp_data_in = price[31:24] | 8'h80;  // MSB=1 (stop bit)
        @(posedge clk_fast);
        
        // ===== Quantity (4 bytes, same encoding) =====
        udp_data_in = quantity[7:0];
        @(posedge clk_fast);
        udp_data_in = quantity[15:8];
        @(posedge clk_fast);
        udp_data_in = quantity[23:16];
        @(posedge clk_fast);
        udp_data_in = quantity[31:24] | 8'h80;
        @(posedge clk_fast);
        
        // ===== Side (1 byte) =====
        udp_data_in = side;
        @(posedge clk_fast);
        
        // ===== Timestamp (8 bytes, big-endian) =====
        for (i = 7; i >= 0; i = i - 1) begin
            udp_data_in = timestamp[(i*8) +: 8];
            @(posedge clk_fast);
        end
        
        // ===== End of message =====
        udp_valid_in = 1'b0;
        udp_data_in  = 8'd0;
        
        $display("  -> FAST message sent (27 bytes)");
    end
    endtask
    
    // ========== Waveform Dump (for simulation) ==========
    initial begin
        $dumpfile("tb_fast_parser.vcd");
        $dumpvars(0, tb_fast_parser);
    end

endmodule
