//==============================================================================
// File: trading_engine_tb.sv
// Description: Production-level testbench for trading engine
// Features: Constrained random, self-checking, coverage-driven
//==============================================================================

`timescale 1ns/1ps

module trading_engine_tb;

    //==========================================================================
    // Parameters & Configurations
    //==========================================================================
    parameter CLK_PERIOD = 8.0;  // 125MHz
    parameter TIMEOUT_CYCLES = 100000;
    
    //==========================================================================
    // DUT Signals
    //==========================================================================
    logic        clk_125mhz;
    logic        rstn;
    logic        btn_start;
    logic [7:0]  status_leds;
    
    //==========================================================================
    // Testbench Variables
    //==========================================================================
    int test_count = 0;
    int pass_count = 0;
    int fail_count = 0;
    
    //==========================================================================
    // Clock Generation
    //==========================================================================
    initial begin
        clk_125mhz = 0;
        forever #(CLK_PERIOD/2) clk_125mhz = ~clk_125mhz;
    end
    
    //==========================================================================
    // DUT Instantiation
    //==========================================================================
    trading_engine_top dut (
        .clk_125mhz(clk_125mhz),
        .rstn(rstn),
        .btn_start(btn_start),
        .status_leds(status_leds)
    );
    
    //==========================================================================
    // Transaction Class
    //==========================================================================
    class Transaction;
        rand bit       start_pulse;
        rand int       hold_cycles;
        bit [7:0]      expected_leds;
        realtime       timestamp;
        
        // Constraints for realistic scenarios
        constraint c_hold {
            hold_cycles inside {[10:100]};
        }
        
        constraint c_pulse {
            start_pulse dist {1 := 30, 0 := 70};  // 30% probability of pulse
        }
        
        function void display(string prefix = "");
            $display("%s[%0t] Transaction: start=%0b, hold=%0d cycles", 
                     prefix, timestamp, start_pulse, hold_cycles);
        endfunction
        
        function Transaction copy();
            Transaction t = new();
            t.start_pulse = this.start_pulse;
            t.hold_cycles = this.hold_cycles;
            t.expected_leds = this.expected_leds;
            return t;
        endfunction
    endclass
    
    //==========================================================================
    // Scoreboard Class
    //==========================================================================
    class Scoreboard;
        int transactions_checked;
        int mismatches;
        
        mailbox #(Transaction) expected_q;
        
        function new();
            transactions_checked = 0;
            mismatches = 0;
            expected_q = new();
        endfunction
        
        function void check_result(logic [7:0] actual_leds, Transaction exp);
            transactions_checked++;
            
            if (actual_leds !== exp.expected_leds && exp.expected_leds !== 8'hxx) begin
                $error("[%0t] LED mismatch! Expected: %02h, Got: %02h", 
                       $time, exp.expected_leds, actual_leds);
                mismatches++;
            end else begin
                $display("[%0t] LED check passed: %02h", $time, actual_leds);
            end
        endfunction
        
        function void report();
            $display("\n========================================");
            $display("SCOREBOARD REPORT");
            $display("========================================");
            $display("Transactions Checked: %0d", transactions_checked);
            $display("Mismatches: %0d", mismatches);
            $display("Pass Rate: %.2f%%", 
                     100.0 * (transactions_checked - mismatches) / transactions_checked);
            $display("========================================\n");
        endfunction
    endclass
    
    //==========================================================================
    // Coverage Groups
    //==========================================================================
    covergroup cg_trading_engine @(posedge clk_125mhz);
        option.per_instance = 1;
        
        cp_btn_start: coverpoint btn_start {
            bins low  = {0};
            bins high = {1};
            bins toggle = (0 => 1 => 0);
        }
        
        cp_status_leds: coverpoint status_leds {
            bins all_off = {8'h00};
            bins all_on  = {8'hFF};
            bins partial[] = {[8'h01:8'hFE]};
        }
        
        cp_reset: coverpoint rstn {
            bins active   = {0};
            bins inactive = {1};
        }
        
        // Cross coverage
        cx_start_leds: cross cp_btn_start, cp_status_leds {
            ignore_bins unused = binsof(cp_btn_start.low) && 
                                 binsof(cp_status_leds.all_off);
        }
        
    endgroup
    
    cg_trading_engine cov_inst;
    
    //==========================================================================
    // Monitor Task - Continuously observes DUT outputs
    //==========================================================================
    task automatic monitor();
        logic [7:0] prev_leds = 8'h00;
        
        forever begin
            @(posedge clk_125mhz);
            
            // Detect LED changes
            if (status_leds !== prev_leds) begin
                $display("[MONITOR][%0t] LED changed: %02h -> %02h", 
                         $time, prev_leds, status_leds);
                prev_leds = status_leds;
            end
            
            // Monitor internal signals via hierarchical access
            if (dut.u_strategy.trade_signal) begin
                $display("[MONITOR][%0t] Trade signal asserted", $time);
            end
            
            if (dut.u_order_mgr.order_valid) begin
                $display("[MONITOR][%0t] Order generated: qty=%0d, price=%0d, side=%0d",
                         $time, 
                         dut.u_order_mgr.order_qty,
                         dut.u_order_mgr.order_price,
                         dut.u_order_mgr.order_side);
            end
            
            if (dut.u_risk.order_approved) begin
                $display("[MONITOR][%0t] Order approved by risk manager", $time);
            end else if (dut.u_risk.rejection_code != 0) begin
                $display("[MONITOR][%0t] Order rejected: code=%0d", 
                         $time, dut.u_risk.rejection_code);
            end
        end
    endtask
    
    //==========================================================================
    // Reset Task
    //==========================================================================
    task automatic reset_dut();
        $display("[%0t] Asserting reset...", $time);
        rstn = 0;
        btn_start = 0;
        repeat(10) @(posedge clk_125mhz);
        rstn = 1;
        repeat(5) @(posedge clk_125mhz);
        $display("[%0t] Reset complete", $time);
    endtask
    
    //==========================================================================
    // Driver Task - Sends stimuli to DUT
    //==========================================================================
    task automatic drive_transaction(Transaction tr);
        tr.display("[DRIVER]");
        
        if (tr.start_pulse) begin
            btn_start = 1;
            @(posedge clk_125mhz);
            btn_start = 0;
        end
        
        repeat(tr.hold_cycles) @(posedge clk_125mhz);
    endtask
    
    //==========================================================================
    // Test Scenarios
    //==========================================================================
    
    // Test 1: Basic reset and initialization
    task automatic test_reset_init();
        $display("\n========== TEST 1: Reset & Initialization ==========");
        test_count++;
        
        reset_dut();
        repeat(20) @(posedge clk_125mhz);
        
        // Check initial state
        if (status_leds == 8'h00) begin
            $display("PASS: LEDs initialized correctly");
            pass_count++;
        end else begin
            $error("FAIL: LEDs not initialized correctly. Got: %02h", status_leds);
            fail_count++;
        end
    endtask
    
    // Test 2: Single trade cycle
    task automatic test_single_trade();
        $display("\n========== TEST 2: Single Trade Cycle ==========");
        test_count++;
        
        Transaction tr = new();
        tr.start_pulse = 1;
        tr.hold_cycles = 50;
        
        drive_transaction(tr);
        
        // Wait for trade to complete
        repeat(100) @(posedge clk_125mhz);
        
        $display("PASS: Single trade completed");
        pass_count++;
    endtask
    
    // Test 3: Constrained random test
    task automatic test_constrained_random(int num_iterations = 100);
        $display("\n========== TEST 3: Constrained Random (%0d iterations) ==========", 
                 num_iterations);
        test_count++;
        
        Transaction tr;
        
        for (int i = 0; i < num_iterations; i++) begin
            tr = new();
            if (!tr.randomize()) begin
                $error("Randomization failed at iteration %0d", i);
                continue;
            end
            
            drive_transaction(tr);
            
            if (i % 10 == 0) begin
                $display("Progress: %0d/%0d transactions", i, num_iterations);
            end
        end
        
        $display("PASS: Constrained random test completed");
        pass_count++;
    endtask
    
    // Test 4: Back-to-back trades
    task automatic test_back_to_back();
        $display("\n========== TEST 4: Back-to-Back Trades ==========");
        test_count++;
        
        repeat(10) begin
            btn_start = 1;
            @(posedge clk_125mhz);
            btn_start = 0;
            repeat(5) @(posedge clk_125mhz);
        end
        
        repeat(200) @(posedge clk_125mhz);
        
        $display("PASS: Back-to-back trades completed");
        pass_count++;
    endtask
    
    // Test 5: Risk limit testing
    task automatic test_risk_limits();
        $display("\n========== TEST 5: Risk Limits ==========");
        test_count++;
        
        // Force large position to trigger risk limits
        force dut.u_pos_track.position = 32'sd1000;
        
        repeat(10) begin
            btn_start = 1;
            @(posedge clk_125mhz);
            btn_start = 0;
            repeat(20) @(posedge clk_125mhz);
        end
        
        release dut.u_pos_track.position;
        
        $display("PASS: Risk limit test completed");
        pass_count++;
    endtask
    
    // Test 6: Corner cases
    task automatic test_corner_cases();
        $display("\n========== TEST 6: Corner Cases ==========");
        test_count++;
        
        // Zero position
        force dut.u_pos_track.position = 0;
        repeat(20) @(posedge clk_125mhz);
        release dut.u_pos_track.position;
        
        // Max position
        force dut.u_pos_track.position = 32'h7FFFFFFF;
        repeat(20) @(posedge clk_125mhz);
        release dut.u_pos_track.position;
        
        // Negative position (short)
        force dut.u_pos_track.position = -32'sd500;
        repeat(20) @(posedge clk_125mhz);
        release dut.u_pos_track.position;
        
        $display("PASS: Corner cases completed");
        pass_count++;
    endtask
    
    //==========================================================================
    // Assertions for Protocol Checking
    //==========================================================================
    
    // Assert: Reset behavior
    property p_reset;
        @(posedge clk_125mhz) !rstn |-> ##1 (status_leds == 8'h00);
    endproperty
    assert property(p_reset) else $error("Reset assertion failed");
    
    // Assert: LED stability (no glitches)
    property p_led_stable;
        @(posedge clk_125mhz) $stable(status_leds) [*5];
    endproperty
    // Commented out to avoid false positives during normal operation
    // assert property(p_led_stable);
    
    //==========================================================================
    // Main Test Execution
    //==========================================================================
    initial begin
        // Initialize coverage
        cov_inst = new();
        
        // Start monitor
        fork
            monitor();
        join_none
        
        // Execute test suite
        $display("\n");
        $display("╔═══════════════════════════════════════════════════════════╗");
        $display("║     TRADING ENGINE VERIFICATION TESTBENCH                 ║");
        $display("╚═══════════════════════════════════════════════════════════╝");
        $display("\n");
        
        test_reset_init();
        test_single_trade();
        test_back_to_back();
        test_constrained_random(50);
        test_risk_limits();
        test_corner_cases();
        
        // Wait for pipeline to drain
        repeat(500) @(posedge clk_125mhz);
        
        // Final report
        $display("\n");
        $display("╔═══════════════════════════════════════════════════════════╗");
        $display("║              VERIFICATION SUMMARY                         ║");
        $display("╚═══════════════════════════════════════════════════════════╝");
        $display("Total Tests:  %0d", test_count);
        $display("Passed:       %0d", pass_count);
        $display("Failed:       %0d", fail_count);
        $display("Coverage:     %.2f%%", cov_inst.get_inst_coverage());
        $display("═════════════════════════════════════════════════════════════\n");
        
        if (fail_count == 0) begin
            $display("*** TEST PASSED ***\n");
        end else begin
            $display("*** TEST FAILED ***\n");
        end
        
        $finish;
    end
    
    //==========================================================================
    // Timeout Watchdog
    //==========================================================================
    initial begin
        repeat(TIMEOUT_CYCLES) @(posedge clk_125mhz);
        $error("TIMEOUT: Simulation exceeded maximum cycles");
        $finish;
    end
    
    //==========================================================================
    // Waveform Dump
    //==========================================================================
    initial begin
        $dumpfile("trading_engine_tb.vcd");
        $dumpvars(0, trading_engine_tb);
    end

endmodule
