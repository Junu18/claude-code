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

    // Test tracking variables
    integer test_passed;
    integer test_failed;
    logic [7:0] master_values[20];  // Store master counter values at each tick
    logic [13:0] slave_values[20];   // Store slave counter values at each tick
    integer counter_idx;
    integer all_master_correct;
    integer all_slave_correct;
    integer all_match;
    integer tick_count;

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

    // Count ticks and store counter values
    always @(posedge clk) begin
        if (reset) begin
            tick_count <= 0;
            counter_idx <= 0;
        end else if (debug_tick) begin
            tick_count <= tick_count + 1;
            if (counter_idx < 20) begin
                master_values[counter_idx] <= master_counter;
                slave_values[counter_idx] <= DUT.slave_counter_full;
                counter_idx <= counter_idx + 1;
            end
        end
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
        test_passed = 0;
        test_failed = 0;
        tick_count = 0;
        counter_idx = 0;

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

        if (debug_runstop == 1) begin
            $display("    [PASS] debug_runstop = 1 (RUN state)");
            test_passed++;
        end else begin
            $display("    [FAIL] debug_runstop = %b (expected 1)", debug_runstop);
            test_failed++;
        end

        // Wait for 5 ticks to observe counter increment
        repeat(5) begin
            @(posedge debug_tick);
            $display("    TICK! Master Counter = %d, Slave Counter = %d",
                master_counter, DUT.slave_counter_full);
        end

        // Check counters reached 5
        if (master_counter == 5) begin
            $display("    [PASS] Master counter reached 5");
            test_passed++;
        end else begin
            $display("    [FAIL] Master counter = %d (expected 5)", master_counter);
            test_failed++;
        end

        // ==========================================
        // Test 2: Check Master and Slave match
        // ==========================================
        $display("\n>>> Test 2: Verify Master and Slave counters match");
        #1000;
        if (master_counter == DUT.slave_counter_full[7:0]) begin
            $display("    [PASS] Master (%d) == Slave (%d)",
                master_counter, DUT.slave_counter_full);
            test_passed++;
        end else begin
            $display("    [FAIL] Master (%d) != Slave (%d)",
                master_counter, DUT.slave_counter_full);
            test_failed++;
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

        if (debug_runstop == 0) begin
            $display("    [PASS] debug_runstop = 0 (STOP state)");
            test_passed++;
        end else begin
            $display("    [FAIL] debug_runstop = %b (expected 0)", debug_runstop);
            test_failed++;
        end

        // Wait and verify counter doesn't change
        logic [7:0] stopped_value = master_counter;
        #5000000;  // 5ms
        if (master_counter == stopped_value) begin
            $display("    [PASS] Counter stopped at %d (no change)", stopped_value);
            test_passed++;
        end else begin
            $display("    [FAIL] Counter changed from %d to %d (should not change)",
                stopped_value, master_counter);
            test_failed++;
        end

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

        if (master_counter == 0) begin
            $display("    [PASS] Master counter cleared to 0");
            test_passed++;
        end else begin
            $display("    [FAIL] Master counter = %d (expected 0)", master_counter);
            test_failed++;
        end

        if (DUT.slave_counter_full == 0) begin
            $display("    [PASS] Slave counter cleared to 0");
            test_passed++;
        end else begin
            $display("    [FAIL] Slave counter = %d (expected 0)", DUT.slave_counter_full);
            test_failed++;
        end

        // ==========================================
        // Test 5: Start again from 0
        // ==========================================
        $display("\n>>> Test 5: Start counting from 0 again");

        counter_idx = 0;  // Reset counter value storage
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
            $display("    [PASS] Both counters at 3");
            test_passed++;
        end else begin
            $display("    [FAIL] Master = %d, Slave = %d (expected 3, 3)",
                master_counter, DUT.slave_counter_full);
            test_failed++;
        end

        // ==========================================
        // FINAL SUMMARY - THIS IS WHAT YOU WILL COPY
        // ==========================================
        $display("\n");
        $display("=========================================");
        $display("          FINAL TEST SUMMARY             ");
        $display("=========================================");
        $display("Tests Passed: %0d", test_passed);
        $display("Tests Failed: %0d", test_failed);
        $display("=========================================");

        $display("\n--- Master Counter Increment Check ---");
        all_master_correct = 1;
        for (int i = 0; i < 3; i++) begin
            if (master_values[i] != i) begin
                all_master_correct = 0;
                $display("[ERROR] Tick %0d: Master=%0d (expected %0d)",
                    i, master_values[i], i);
            end
        end
        if (all_master_correct) begin
            $display("[OK] Master counter incremented correctly (0->1->2)");
        end else begin
            $display("[FAILED] Master counter increment has errors!");
        end

        $display("\n--- Slave Counter Increment Check ---");
        all_slave_correct = 1;
        for (int i = 0; i < 3; i++) begin
            if (slave_values[i] != i) begin
                all_slave_correct = 0;
                $display("[ERROR] Tick %0d: Slave=%0d (expected %0d)",
                    i, slave_values[i], i);
            end
        end
        if (all_slave_correct) begin
            $display("[OK] Slave counter incremented correctly (0->1->2)");
        end else begin
            $display("[FAILED] Slave counter increment has errors!");
        end

        $display("\n--- Master vs Slave Matching Check ---");
        all_match = 1;
        for (int i = 0; i < 3; i++) begin
            if (master_values[i] != slave_values[i][7:0]) begin
                all_match = 0;
                $display("[ERROR] Tick %0d: Master=%0d, Slave=%0d (mismatch)",
                    i, master_values[i], slave_values[i]);
            end
        end
        if (all_match) begin
            $display("[OK] Master and Slave counters match at all ticks");
        end else begin
            $display("[FAILED] Master and Slave counters DO NOT match!");
        end

        $display("\n--- State Information ---");
        $display("Current master counter: %0d", master_counter);
        $display("Current slave counter: %0d", DUT.slave_counter_full);
        $display("debug_runstop: %b", debug_runstop);
        $display("Total ticks received: %0d", tick_count);

        $display("\n--- Diagnosis ---");
        if (test_failed == 0 && all_master_correct && all_slave_correct && all_match) begin
            $display("✓ ALL TESTS PASSED - Full system working correctly!");
        end else begin
            $display("✗ SOME TESTS FAILED - Issues detected:");
            if (!all_master_correct) begin
                $display("  - Master counter not incrementing correctly");
                $display("    Possible issues:");
                $display("      1. tick signal not reaching master");
                $display("      2. o_runstop not maintained in RUN state");
            end
            if (!all_slave_correct) begin
                $display("  - Slave counter not incrementing correctly");
                $display("    Possible issues:");
                $display("      1. SPI transmission errors");
                $display("      2. Slave SPI reception/synchronization issues");
            end
            if (!all_match) begin
                $display("  - Master and Slave counters do not match");
                $display("    Possible issues:");
                $display("      1. SPI timing issues");
                $display("      2. 2-byte transfer sequence problem");
                $display("      3. Slave synchronizer delays");
            end
        end

        $display("\n=========================================");
        $display(">>> Copy everything above this line <<<");
        $display("=========================================\n");

        $finish;
    end

    // Timeout watchdog
    initial begin
        #200000000;  // 200ms timeout
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule
