`timescale 1ns / 1ps

module tb_trading_system;

    // Clock and reset
    reg clk_sys;
    reg clk_eth;
    reg rstn;
    
    // Ethernet PHY signals
    wire [63:0] sfp_tx_data;
    wire        sfp_tx_valid;
    reg         sfp_tx_ready;
    
    reg  [63:0] sfp_rx_data;
    reg         sfp_rx_valid;
    
    // Configuration
    reg  [31:0] config_max_position;
    reg  [31:0] config_max_loss;
    
    // Status outputs
    wire [7:0]  status_leds;
    wire [31:0] total_orders_sent;
    wire [31:0] total_fills_received;
    wire signed [31:0] current_position;
    wire signed [31:0] realized_pnl;
    
    // Additional monitoring signals
    wire [15:0] latency_clocks;
    wire        latency_valid;
    
    // ========================================
    // DUT Instantiation
    // ========================================
    trading_system_top dut (
        .clk_sys                (clk_sys),
        .clk_eth                (clk_eth),
        .rstn                   (rstn),
        .sfp_tx_data            (sfp_tx_data),
        .sfp_tx_valid           (sfp_tx_valid),
        .sfp_tx_ready           (sfp_tx_ready),
        .sfp_rx_data            (sfp_rx_data),
        .sfp_rx_valid           (sfp_rx_valid),
        .config_max_position    (config_max_position),
        .config_max_loss        (config_max_loss),
        .status_leds            (status_leds),
        .total_orders_sent      (total_orders_sent),
        .total_fills_received   (total_fills_received),
        .current_position       (current_position),
        .realized_pnl           (realized_pnl)
    );
    
    // Access internal signals
    assign latency_clocks = dut.u_latency.latency_clocks;
    assign latency_valid = dut.u_latency.latency_valid;
    
    // ========================================
    // Clock Generation
    // ========================================
    initial begin
        clk_sys = 0;
        forever #5 clk_sys = ~clk_sys;  // 100 MHz
    end
    
    initial begin
        clk_eth = 0;
        forever #3.2 clk_eth = ~clk_eth;  // 156.25 MHz
    end
    
    // ========================================
    // Test Sequence
    // ========================================
    initial begin
        $display("========================================");
        $display("DAY 12 TRADING SYSTEM - DEBUG MODE");
        $display("========================================");
        
        // Initialize
        rstn = 0;
        sfp_tx_ready = 1;
        sfp_rx_data = 0;
        sfp_rx_valid = 0;
        config_max_position = 32'd1000;
        config_max_loss = 32'd50000;
        
        #100;
        rstn = 1;
        $display("[%0t] Reset released", $time);
        
        #500;
        
        // === INJECT MARKET DATA WITH TOB PULSE ===
        $display("[%0t] === Injecting market data with TOB pulse ===", $time);
        
        // Force TOB low first
        force dut.tob_valid_sys = 1'b0;
        force dut.best_bid_sys = 32'd15000;
        force dut.best_ask_sys = 32'd15050;
        
        #100;
        
        // Now pulse TOB high (this triggers latency counter)
        $display("[%0t] TOB pulse: 0->1", $time);
        force dut.tob_valid_sys = 1'b1;
        
        #50;
        
        // Keep high for strategy to process
        $display("[%0t] Monitoring for order...", $time);
        
        repeat(200) begin
            @(posedge clk_sys);
            
            if (dut.order_valid_sys) begin
                $display("[%0t] *** ORDER VALID ***", $time);
                $display("  Qty: %0d, Price: %0d, Side: %0d", 
                         dut.order_qty_sys, dut.order_price_sys, dut.order_side_sys);
            end
            
            if (latency_valid) begin
                $display("[%0t] *** LATENCY: %0d clocks = %0d ns ***", 
                         $time, latency_clocks, latency_clocks * 10);
                if (latency_clocks * 10 < 100) begin
                    $display("  ✓ SUB-100ns TARGET MET!");
                end else begin
                    $display("  ✗ Exceeds 100ns");
                end
            end
        end
        
        #2000;
        
        // === SEND FILL (clk_eth domain) ===
        $display("\n[%0t] === Sending fill in clk_eth domain ===", $time);
        
        repeat(10) begin
            @(posedge clk_eth);
            sfp_rx_valid = 1;
            sfp_rx_data = 64'h3838464958342E32;
            $display("[%0t] sfp_rx_valid=1 sfp_rx_data=%h", $time, sfp_rx_data);
        end
        
        @(posedge clk_eth);
        sfp_rx_valid = 0;
        $display("[%0t] sfp_rx_valid=0", $time);
        
        // === WAIT FOR CDC AND POSITION UPDATE ===
        $display("[%0t] === Waiting for CDC clk_eth->clk_sys ===", $time);
        
        repeat(100) @(posedge clk_sys);
        
        $display("\n[%0t] === DEBUG: Fill CDC chain ===", $time);
        $display("  exec_report_valid (clk_eth): %b", dut.exec_report_valid);
        $display("  fill_valid_sys_s1 (clk_sys):  %b", dut.fill_valid_sys_s1);
        $display("  fill_valid_sys_s2 (clk_sys):  %b", dut.fill_valid_sys_s2);
        $display("  fill_qty_sys_s2:   %0d", dut.fill_qty_sys_s2);
        $display("  fill_price_sys_s2: %0d", dut.fill_price_sys_s2);
        $display("  fill_side_sys_s2:  %0d", dut.fill_side_sys_s2);
        
        $display("\n[%0t] === DEBUG: Position tracker inputs ===", $time);
        $display("  u_position.fill_valid: %b", dut.u_position.fill_valid);
        $display("  u_position.fill_qty:   %0d", dut.u_position.fill_qty);
        $display("  u_position.fill_price: %0d", dut.u_position.fill_price);
        $display("  u_position.fill_side:  %0d", dut.u_position.fill_side);
        
        $display("\n[%0t] === DEBUG: Position tracker state ===", $time);
        $display("  u_position.position:   %0d", dut.u_position.position);
        $display("  u_position.realized_pnl: %0d", dut.u_position.realized_pnl);
        $display("  u_position.trade_count:  %0d", dut.u_position.trade_count);
        
        #5000;
        
        // Release forced signals
        release dut.tob_valid_sys;
        release dut.best_bid_sys;
        release dut.best_ask_sys;
        
        #2000;
        
        // === FINAL SUMMARY ===
        $display("\n========================================");
        $display("SIMULATION SUMMARY - DAY 12");
        $display("========================================");
        $display("Orders Sent:        %0d", total_orders_sent);
        $display("Fills Received:     %0d", total_fills_received);
        $display("Current Position:   %0d", current_position);
        $display("Realized P&L:       $%0d", realized_pnl);
        $display("========================================");
        $display("Status LEDs: %b", status_leds);
        $display("  [0] TOB Valid:     %b", status_leds[0]);
        $display("  [1] Order Valid:   %b", status_leds[1]);
        $display("  [2] FIX TX:        %b", status_leds[2]);
        $display("  [3] Exec Report:   %b", status_leds[3]);
        $display("  [4] Fill Proc:     %b", status_leds[4]);
        $display("  [5] Position!=0:   %b", status_leds[5]);
        $display("  [6] Risk OK:       %b", status_leds[6]);
        $display("  [7] Latency Valid: %b", status_leds[7]);
        $display("========================================");
        
        if (total_orders_sent > 0 && current_position == 100) begin
            $display("✓✓ FULL SUCCESS: Order sent and position updated!");
        end else if (total_orders_sent > 0) begin
            $display("✓ Partial: Orders sent but position not updated");
        end else begin
            $display("✗ No orders generated");
        end
        
        $display("\nSimulation complete!");
        $finish;
    end
    
    // === CONTINUOUS MONITORS ===
    always @(posedge clk_sys) begin
        if (dut.fill_valid_sys_s2) begin
            $display("[%0t] [clk_sys] fill_valid_sys_s2 PULSED!", $time);
        end
    end
    
    always @(posedge clk_sys) begin
        if (dut.u_position.fill_valid && dut.u_position.s5_valid) begin
            $display("[%0t] [position_tracker] Fill pipeline stage 5 valid!", $time);
        end
    end
    
    // Position change detector
    reg signed [31:0] last_pos = 0;
    always @(posedge clk_sys) begin
        if (current_position != last_pos) begin
            $display("[%0t] *** POSITION CHANGED: %0d -> %0d ***", 
                     $time, last_pos, current_position);
            last_pos = current_position;
        end
    end
    
    // Timeout
    initial begin
        #200_000;  // 200us
        $display("\n[TIMEOUT] Simulation timeout");
        $finish;
    end

endmodule
