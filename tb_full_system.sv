`timescale 1ns / 1ps

module tb_full_system;

    // Clock and Reset
    logic clk;
    logic reset;

    // Button inputs for master
    logic i_runstop;
    logic i_clear;

    // SPI signals (connect master and slave)
    logic sclk;
    logic mosi;
    logic miso;
    logic ss;

    // Master debug outputs
    logic [13:0] master_counter;

    // Slave outputs
    logic [3:0] fnd_com;
    logic [7:0] fnd_data;
    logic [13:0] slave_counter;
    logic slave_data_valid;

    //===========================================
    // DUT: Master (Fast version for simulation)
    //===========================================
    master_top_fast U_MASTER (
        .clk      (clk),
        .reset    (reset),
        .i_runstop(i_runstop),
        .i_clear  (i_clear),
        .sclk     (sclk),
        .mosi     (mosi),
        .miso     (miso),
        .ss       (ss),
        .o_counter(master_counter),
        .o_state  ()  // Not used in this test
    );

    //===========================================
    // DUT: Slave
    //===========================================
    slave_top U_SLAVE (
        .clk         (clk),
        .reset       (reset),
        .sclk        (sclk),
        .mosi        (mosi),
        .miso        (miso),
        .ss          (ss),
        .fnd_com     (fnd_com),
        .fnd_data    (fnd_data),
        .o_counter   (slave_counter),
        .o_data_valid(slave_data_valid)
    );

    //===========================================
    // Clock Generation: 100MHz (10ns period)
    //===========================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    //===========================================
    // Test Stimulus
    //===========================================
    initial begin
        // Initialize
        reset = 1;
        i_runstop = 0;
        i_clear = 0;

        #100;
        reset = 0;
        #100;

        $display("========================================");
        $display("  Full System Test: Master + Slave");
        $display("  Clock: 100MHz");
        $display("  Tick Period: 1ms (fast sim)");
        $display("========================================\n");

        // Test 1: Start counter
        $display("[%0t ns] TEST 1: Press RUN/STOP to start counter", $time);
        #1000;
        i_runstop = 1;
        #100;
        i_runstop = 0;
        $display("[%0t ns] Master counter started\n", $time);

        // Wait for several SPI transmissions
        #10_000_000;  // 10ms = 10 ticks = 10 transmissions

        $display("\n[%0t ns] Current Status:", $time);
        $display("  Master Counter: %d (0x%04h)", master_counter, master_counter);
        $display("  Slave Counter:  %d (0x%04h)", slave_counter, slave_counter);

        // Verify match
        if (master_counter == slave_counter) begin
            $display("  ✓ PASS: Master and Slave counters match!");
        end else begin
            $display("  ✗ FAIL: Master=%d, Slave=%d", master_counter, slave_counter);
        end

        // Test 2: Stop counter
        $display("\n[%0t ns] TEST 2: Press RUN/STOP to stop counter", $time);
        i_runstop = 1;
        #100;
        i_runstop = 0;
        $display("[%0t ns] Master counter stopped", $time);

        #3_000_000;  // Wait 3ms
        $display("[%0t ns] Counters should remain stable", $time);
        $display("  Master: %d, Slave: %d", master_counter, slave_counter);

        // Test 3: Clear counter
        $display("\n[%0t ns] TEST 3: Press CLEAR", $time);
        i_clear = 1;
        #100;
        i_clear = 0;
        #1000;
        $display("[%0t ns] Master counter cleared: %d", $time, master_counter);

        // Wait for next transmission
        #2_000_000;  // 2ms

        // Test 4: Restart and observe
        $display("\n[%0t ns] TEST 4: Restart counter", $time);
        i_runstop = 1;
        #100;
        i_runstop = 0;

        // Run for more time
        #15_000_000;  // 15ms

        $display("\n========================================");
        $display("  Test Complete");
        $display("========================================");
        $display("  Final Master Counter: %d (0x%04h)", master_counter, master_counter);
        $display("  Final Slave Counter:  %d (0x%04h)", slave_counter, slave_counter);

        if (master_counter == slave_counter) begin
            $display("  ✓✓✓ ALL TESTS PASSED ✓✓✓");
        end else begin
            $display("  ✗✗✗ TEST FAILED ✗✗✗");
        end
        $display("========================================");

        #1000;
        $finish;
    end

    //===========================================
    // Monitor SPI Transactions
    //===========================================
    integer transaction_count = 0;

    always @(negedge ss) begin
        transaction_count = transaction_count + 1;
        $display("[%0t ns] ═══ SPI Transaction #%0d START ═══", $time, transaction_count);
    end

    always @(posedge ss) begin
        $display("[%0t ns] ═══ SPI Transaction #%0d END ═══", $time, transaction_count);
    end

    //===========================================
    // Monitor Slave Data Valid
    //===========================================
    always @(posedge clk) begin
        if (slave_data_valid) begin
            $display("[%0t ns] ★ SLAVE: New data received! Counter = %d (0x%04h)",
                     $time, slave_counter, slave_counter);
        end
    end

    //===========================================
    // Monitor Master Tick
    //===========================================
    always @(posedge clk) begin
        if (U_MASTER.counter_tick) begin
            $display("[%0t ns] ⚡ MASTER: Tick! Counter = %d, Starting transmission...",
                     $time, master_counter);
        end
    end

    //===========================================
    // Periodic Status Report
    //===========================================
    initial begin
        #100;
        forever begin
            #5_000_000;  // Every 5ms
            if (!reset) begin
                $display("\n[%0t ns] --- Status Report ---", $time);
                $display("  Master: %4d | Slave: %4d | Match: %s",
                         master_counter, slave_counter,
                         (master_counter == slave_counter) ? "YES" : "NO");
            end
        end
    end

    //===========================================
    // Waveform Dump
    //===========================================
    initial begin
        $dumpfile("full_system.vcd");
        $dumpvars(0, tb_full_system);
    end

endmodule
