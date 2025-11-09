`timescale 1ns / 1ps

module master_top_tb;

    // Clock and reset
    logic clk;
    logic reset;

    // Button inputs
    logic i_runstop;
    logic i_clear;

    // SPI signals
    logic sclk;
    logic mosi;
    logic miso;
    logic ss;

    // Debug outputs
    logic [13:0] o_counter;
    logic        o_runstop_status;
    logic        o_tick;

    // Test tracking variables
    integer tick_count;
    integer test_passed;
    integer test_failed;
    logic [13:0] counter_values[20];  // Store counter values at each tick
    integer counter_idx;
    integer all_correct;  // For final summary

    // Test 2 variables
    logic [13:0] stopped_value;

    // Test 5 variables
    logic [63:0] tick_time1, tick_time2;
    logic [63:0] tick_period_ns;

    // Test 6 variables
    logic cu_stop, cu_run;

    // Clock generation: 100MHz (10ns period)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // DUT instantiation with fast tick for simulation
    master_top #(
        .TICK_PERIOD_MS(1)  // 1ms = 100,000 clocks
    ) DUT (
        .clk             (clk),
        .reset           (reset),
        .i_runstop       (i_runstop),
        .i_clear         (i_clear),
        .sclk            (sclk),
        .mosi            (mosi),
        .miso            (miso),
        .ss              (ss),
        .o_counter       (o_counter),
        .o_runstop_status(o_runstop_status),
        .o_tick          (o_tick)
    );

    // MISO tied to 0 (not used)
    assign miso = 1'b0;

    // Count ticks
    always @(posedge clk) begin
        if (reset) begin
            tick_count <= 0;
            counter_idx <= 0;
        end else if (o_tick) begin
            tick_count <= tick_count + 1;
            counter_values[counter_idx] <= o_counter;
            counter_idx <= counter_idx + 1;
        end
    end

    // Helper task for button press (pulse)
    task press_button(input logic is_runstop);
        begin
            if (is_runstop) begin
                @(posedge clk);
                i_runstop = 1;
                @(posedge clk);
                i_runstop = 0;
            end else begin
                @(posedge clk);
                i_clear = 1;
                @(posedge clk);
                i_clear = 0;
            end
            #100;  // Wait for edge detector
        end
    endtask

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

        $display("=====================================");
        $display("Master Top Testbench");
        $display("TICK_PERIOD = 1ms (100,000 clocks)");
        $display("=====================================\n");

        // Reset for 100ns
        #100;
        reset = 0;
        #200;

        // ==========================================
        // Test 1: Press RUNSTOP (toggle to RUN)
        // ==========================================
        $display(">>> Test 1: Press RUNSTOP button (start counting)");
        press_button(1);  // Press runstop

        if (o_runstop_status == 1) begin
            $display("    [PASS] o_runstop_status = 1 (RUN state)");
            test_passed++;
        end else begin
            $display("    [FAIL] o_runstop_status = %b (expected 1)", o_runstop_status);
            test_failed++;
        end

        // Wait for 10 ticks
        $display("    Waiting for 10 ticks...");
        repeat(10) @(posedge o_tick);

        // Check counter incremented
        $display("    Counter progression:");
        for (int i = 0; i < 10; i++) begin
            $display("      Tick %2d: Counter = %5d (expected %5d) %s",
                i, counter_values[i], i,
                (counter_values[i] == i) ? "[OK]" : "[ERROR]");
        end

        // Verify counter = 10
        if (o_counter == 10) begin
            $display("    [PASS] Counter reached 10");
            test_passed++;
        end else begin
            $display("    [FAIL] Counter = %d (expected 10)", o_counter);
            test_failed++;
        end

        // ==========================================
        // Test 2: Press RUNSTOP again (toggle to STOP)
        // ==========================================
        $display("\n>>> Test 2: Press RUNSTOP button again (stop counting)");
        stopped_value = o_counter;
        press_button(1);  // Press runstop

        if (o_runstop_status == 0) begin
            $display("    [PASS] o_runstop_status = 0 (STOP state)");
            test_passed++;
        end else begin
            $display("    [FAIL] o_runstop_status = %b (expected 0)", o_runstop_status);
            test_failed++;
        end

        // Wait 5ms and check counter didn't change
        #5000000;
        if (o_counter == stopped_value) begin
            $display("    [PASS] Counter stopped at %d", stopped_value);
            test_passed++;
        end else begin
            $display("    [FAIL] Counter changed from %d to %d (should not change)",
                stopped_value, o_counter);
            test_failed++;
        end

        // ==========================================
        // Test 3: Press CLEAR button
        // ==========================================
        $display("\n>>> Test 3: Press CLEAR button");
        press_button(0);  // Press clear
        #100;

        if (o_counter == 0) begin
            $display("    [PASS] Counter cleared to 0");
            test_passed++;
        end else begin
            $display("    [FAIL] Counter = %d (expected 0)", o_counter);
            test_failed++;
        end

        // ==========================================
        // Test 4: Start again from 0
        // ==========================================
        $display("\n>>> Test 4: Start counting from 0 again");
        counter_idx = 0;  // Reset counter value storage
        press_button(1);  // Press runstop

        // Wait for 5 ticks
        repeat(5) @(posedge o_tick);

        $display("    Counter progression from 0:");
        for (int i = 0; i < 5; i++) begin
            $display("      Tick %2d: Counter = %5d (expected %5d) %s",
                i, counter_values[i], i,
                (counter_values[i] == i) ? "[OK]" : "[ERROR]");
        end

        if (o_counter == 5) begin
            $display("    [PASS] Counter correctly incremented from 0 to 5");
            test_passed++;
        end else begin
            $display("    [FAIL] Counter = %d (expected 5)", o_counter);
            test_failed++;
        end

        // ==========================================
        // Test 5: Verify tick timing
        // ==========================================
        $display("\n>>> Test 5: Verify tick timing (should be ~1ms apart)");

        @(posedge o_tick);
        tick_time1 = $time;
        @(posedge o_tick);
        tick_time2 = $time;

        tick_period_ns = tick_time2 - tick_time1;

        $display("    Tick period: %0d ns (expected ~1,000,000 ns)", tick_period_ns);
        if (tick_period_ns >= 999000 && tick_period_ns <= 1001000) begin
            $display("    [PASS] Tick period within 0.1%% tolerance");
            test_passed++;
        end else begin
            $display("    [FAIL] Tick period out of tolerance");
            test_failed++;
        end

        // ==========================================
        // Test 6: Verify CU state machine
        // ==========================================
        $display("\n>>> Test 6: Verify CU FSM states");
        press_button(1);  // Stop
        #100;

        cu_stop = (DUT.U_SPI_UPCOUNT_CU.state == DUT.U_SPI_UPCOUNT_CU.STOP);
        cu_run = (DUT.U_SPI_UPCOUNT_CU.state == DUT.U_SPI_UPCOUNT_CU.RUN);

        if (cu_stop) begin
            $display("    [PASS] CU in STOP state");
            test_passed++;
        end else if (cu_run) begin
            $display("    [FAIL] CU in RUN state (expected STOP)");
            test_failed++;
        end else begin
            $display("    [FAIL] CU in unknown state");
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

        $display("\n--- Counter Increment Check ---");
        all_correct = 1;
        for (int i = 0; i < 10; i++) begin
            if (counter_values[i] != i) begin
                all_correct = 0;
                $display("[ERROR] Tick %0d: Counter=%0d (expected %0d)",
                    i, counter_values[i], i);
            end
        end
        if (all_correct) begin
            $display("[OK] All counters incremented correctly (0->1->2->...->9)");
        end else begin
            $display("[FAILED] Counter increment has errors!");
        end

        $display("\n--- State Information ---");
        $display("Current counter value: %0d", o_counter);
        $display("o_runstop_status: %b", o_runstop_status);
        $display("CU FSM state: %s",
            (DUT.U_SPI_UPCOUNT_CU.state == DUT.U_SPI_UPCOUNT_CU.STOP) ? "STOP" :
            (DUT.U_SPI_UPCOUNT_CU.state == DUT.U_SPI_UPCOUNT_CU.RUN) ? "RUN" :
            (DUT.U_SPI_UPCOUNT_CU.state == DUT.U_SPI_UPCOUNT_CU.CLEAR) ? "CLEAR" : "UNKNOWN");
        $display("Total ticks received: %0d", tick_count);

        $display("\n--- Diagnosis ---");
        if (test_failed == 0) begin
            $display("✓ ALL TESTS PASSED - Master is working correctly!");
        end else begin
            $display("✗ SOME TESTS FAILED - Issues detected:");
            if (!all_correct) begin
                $display("  - Counter not incrementing correctly (0->1->2->...)");
                $display("  - Possible issues:");
                $display("    1. tick signal not reaching datapath");
                $display("    2. o_runstop not maintained in RUN state");
                $display("    3. Counter increment condition wrong");
            end
            if (o_runstop_status != (DUT.U_SPI_UPCOUNT_CU.state == DUT.U_SPI_UPCOUNT_CU.STOP ? 0 : 1)) begin
                $display("  - CU state mismatch with o_runstop_status");
            end
        end

        $display("\n=========================================");
        $display(">>> Copy everything above this line <<<");
        $display("=========================================\n");

        $finish;
    end

    // Timeout watchdog
    initial begin
        #100000000;  // 100ms timeout
        $display("\nERROR: Simulation timeout!");
        $display("This might indicate:");
        $display("  - tick signal never generated");
        $display("  - FSM stuck in a state");
        $finish;
    end

endmodule
