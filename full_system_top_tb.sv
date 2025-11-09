`timescale 1ns / 1ps

module full_system_top_tb;

    // Clock and reset
    logic clk;
    logic reset;

    // Button inputs
    logic i_runstop;
    logic i_clear;

    // FND outputs
    logic [3:0] fnd_com;
    logic [7:0] fnd_data;

    // Debug outputs
    logic [7:0] master_counter;
    logic       debug_runstop;
    logic       debug_tick;

    // Clock generation: 100MHz (10ns period)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // DUT instantiation with fast parameters for simulation
    full_system_top #(
        .TICK_PERIOD_MS(1),      // 1ms instead of 1000ms
        .DEBOUNCE_TIME_MS(1)     // 1ms instead of 20ms (100,000 clocks)
    ) DUT (
        .clk          (clk),
        .reset        (reset),
        .i_runstop    (i_runstop),
        .i_clear      (i_clear),
        .fnd_com      (fnd_com),
        .fnd_data     (fnd_data),
        .master_counter(master_counter),
        .debug_runstop(debug_runstop),
        .debug_tick   (debug_tick)
    );

    // Monitoring
    initial begin
        $display("=====================================");
        $display("Full System Top Testbench");
        $display("TICK_PERIOD = 1ms, DEBOUNCE = 1ms");
        $display("=====================================");
        $display("Time(ns) | RST | BTN | DEBOUNCED | PULSE | RUNSTOP | TICK | COUNTER | SLAVE_CNT | FND");
        $display("----------------------------------------------------------------------------------------");
    end

    // Monitor every significant change
    logic prev_tick;
    always @(posedge clk) begin
        if (debug_tick !== prev_tick || i_runstop || i_clear ||
            (master_counter > 0 && master_counter < 10)) begin
            $display("%8t | %b   | %b   | %b         | %b     | %b       | %b    | %3d     | %5d     | %4b %8b",
                $time, reset, i_runstop,
                DUT.runstop_debounced, DUT.runstop_pulse,
                debug_runstop, debug_tick, master_counter,
                DUT.slave_counter_full, fnd_com, fnd_data);
        end
        prev_tick = debug_tick;
    end

    // Test stimulus
    initial begin
        // Initialize
        reset = 1;
        i_runstop = 0;
        i_clear = 0;

        // Reset for 100ns
        #100;
        reset = 0;
        $display(">>> RESET Released");
        #200;

        // ==========================================
        // Test 1: Press RUNSTOP button (toggle to RUN)
        // ==========================================
        $display("\n>>> Test 1: Press and hold RUNSTOP button");
        $display("    Debounce requires 1ms = 100,000 clocks");

        // Hold button for 2ms to pass debouncer
        @(posedge clk);
        i_runstop = 1;
        #2000000;  // 2ms
        i_runstop = 0;
        #100000;   // Wait for edge detector

        $display("    Expected: debug_runstop = 1, counter starts incrementing");
        $display("    Actual:   debug_runstop = %b", debug_runstop);

        // Wait for 5 ticks to observe counter increment
        repeat(5) begin
            @(posedge debug_tick);
            $display("    TICK! Master Counter = %d, Slave Counter = %d",
                master_counter, DUT.slave_counter_full);
        end

        // ==========================================
        // Test 2: Check Master and Slave match
        // ==========================================
        $display("\n>>> Test 2: Verify Master and Slave counters match");
        #1000;
        if (master_counter == DUT.slave_counter_full[7:0]) begin
            $display("    PASS: Master (%d) == Slave (%d)",
                master_counter, DUT.slave_counter_full);
        end else begin
            $display("    FAIL: Master (%d) != Slave (%d)",
                master_counter, DUT.slave_counter_full);
        end

        // ==========================================
        // Test 3: Press RUNSTOP button again (toggle to STOP)
        // ==========================================
        $display("\n>>> Test 3: Press RUNSTOP button again (stop counting)");

        @(posedge clk);
        i_runstop = 1;
        #2000000;  // 2ms
        i_runstop = 0;
        #100000;

        $display("    Expected: debug_runstop = 0, counter stops");
        $display("    Actual:   debug_runstop = %b", debug_runstop);

        // Wait and verify counter doesn't change
        #5000000;  // 5ms
        logic [7:0] stopped_value = master_counter;
        $display("    Counter stopped at: %d", stopped_value);

        // ==========================================
        // Test 4: Press CLEAR button
        // ==========================================
        $display("\n>>> Test 4: Press CLEAR button");

        @(posedge clk);
        i_clear = 1;
        #2000000;  // 2ms
        i_clear = 0;
        #100000;

        $display("    Expected: Master counter = 0, Slave counter = 0");
        $display("    Actual:   Master = %d, Slave = %d",
            master_counter, DUT.slave_counter_full);

        // ==========================================
        // Test 5: Start again from 0
        // ==========================================
        $display("\n>>> Test 5: Start counting from 0 again");

        @(posedge clk);
        i_runstop = 1;
        #2000000;  // 2ms
        i_runstop = 0;
        #100000;

        // Wait for 3 ticks
        repeat(3) begin
            @(posedge debug_tick);
            $display("    TICK! Master = %d, Slave = %d",
                master_counter, DUT.slave_counter_full);
        end

        // Verify they match
        if (master_counter == 3 && DUT.slave_counter_full == 3) begin
            $display("    PASS: Both counters at 3");
        end else begin
            $display("    FAIL: Master = %d, Slave = %d (expected 3, 3)",
                master_counter, DUT.slave_counter_full);
        end

        // ==========================================
        // Summary
        // ==========================================
        $display("\n=====================================");
        $display("Test Summary:");
        $display("- Counter should increment: 0->1->2->3...");
        $display("- Master and Slave should match");
        $display("- Counter should stop when RUNSTOP pressed");
        $display("- Counter should clear to 0 when CLEAR pressed");
        $display("- FND should display correct values");
        $display("=====================================");

        #1000;
        $display("\n>>> Simulation Complete");
        $finish;
    end

    // Timeout watchdog
    initial begin
        #200000000;  // 200ms timeout
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule
