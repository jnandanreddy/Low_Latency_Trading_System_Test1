`timescale 1ps / 1ps

module tb_order_entry ();

    reg clk_125, rstn_raw;
    wire [7:0] status_leds;
    
    // Instantiate top module
    trading_engine_top DUT (
        .clk_125mhz  (clk_125),
        .rstn_raw    (rstn_raw),
        .status_leds (status_leds)
    );
    
    // Clock generation: 125 MHz
    initial begin
        clk_125 = 0;
        forever #4 clk_125 = ~clk_125;  // 8 ns period = 125 MHz
    end
    
    // Test sequence
    initial begin
        $dumpfile("tb_order_entry.vcd");
        $dumpvars(0, tb_order_entry);
        
        // Reset
        rstn_raw = 0;
        #100;
        rstn_raw = 1;
        #100;
        
        $display("[%0t] Starting simulation", $time);
        
        // Let design run for 1 ms
        #1_000_000;
        
        $display("[%0t] Simulation complete", $time);
        $finish;
    end

endmodule

