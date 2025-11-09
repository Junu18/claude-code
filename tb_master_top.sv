`timescale 1ns / 1ps

module tb_master_top;

    // Clock and Reset
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

    // Debug output
    logic [13:0] o_counter;

    //===========================================
    // DUT (Device Under Test)
    //===========================================
    master_top DUT (
        .clk      (clk),
        .reset    (reset),
        .i_runstop(i_runstop),
        .i_clear  (i_clear),
        .sclk     (sclk),
        .mosi     (mosi),
        .miso     (miso),
        .ss       (ss),
        .o_counter(o_counter)
    );

    //===========================================
    // Clock Generation: 100MHz (10ns period)
    //===========================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;  // 10ns period = 100MHz
    end

    //===========================================
    // MISO simulation (loopback for testing)
    //===========================================
    assign miso = mosi;  // Simple loopback

    //===========================================
    // Test Stimulus
    //===========================================
    initial begin
        // Initialize
        reset = 1;
        i_runstop = 0;
        i_clear = 0;

        // Wait for reset
        #100;
        reset = 0;
        #100;

        $display("========================================");
        $display("  SPI Master Top Test Start");
        $display("  Clock: 100MHz");
        $display("  Tick Period: 100ms");
        $display("========================================");

        // Test 1: Start counter (press runstop button)
        #1000;
        $display("\n[%0t ns] TEST 1: Start Counter (Press RUN/STOP)", $time);
        i_runstop = 1;
        #100;
        i_runstop = 0;
        $display("[%0t ns] Counter should start incrementing", $time);

        // Wait for a few ticks to observe SPI transmissions
        // Note: 100ms = 100,000,000 ns, but for simulation we can reduce this
        // Let's wait for some counter increments
        #50000;  // Wait 50us

        // Display counter value
        $display("[%0t ns] Current Counter Value: %d (0x%h)", $time, o_counter, o_counter);

        // Test 2: Stop counter
        #50000;
        $display("\n[%0t ns] TEST 2: Stop Counter (Press RUN/STOP again)", $time);
        i_runstop = 1;
        #100;
        i_runstop = 0;
        $display("[%0t ns] Counter should stop", $time);

        #10000;
        $display("[%0t ns] Counter Value (should be stopped): %d (0x%h)", $time, o_counter, o_counter);

        // Test 3: Clear counter
        #1000;
        $display("\n[%0t ns] TEST 3: Clear Counter (Press CLEAR)", $time);
        i_clear = 1;
        #100;
        i_clear = 0;
        $display("[%0t ns] Counter should be cleared to 0", $time);

        #1000;
        $display("[%0t ns] Counter Value (should be 0): %d (0x%h)", $time, o_counter, o_counter);

        // Test 4: Restart counter and observe SPI transmission
        #1000;
        $display("\n[%0t ns] TEST 4: Restart Counter and Observe SPI", $time);
        i_runstop = 1;
        #100;
        i_runstop = 0;

        // Wait for counter to increment
        #100000;
        $display("[%0t ns] Counter Value: %d (0x%h)", $time, o_counter, o_counter);

        // Test 5: Observe multiple SPI transmissions
        $display("\n[%0t ns] TEST 5: Observing Counter and SPI Activity...", $time);
        #200000;
        $display("[%0t ns] Counter Value: %d (0x%h)", $time, o_counter, o_counter);

        #100000;
        $display("\n========================================");
        $display("  Test Complete");
        $display("  Final Counter Value: %d (0x%h)", o_counter, o_counter);
        $display("========================================");

        #1000;
        $finish;
    end

    //===========================================
    // Monitor SPI Transactions
    //===========================================
    // Track SPI byte transmissions
    logic [7:0] spi_received_byte;
    integer bit_count;
    logic prev_sclk;

    initial begin
        bit_count = 0;
        spi_received_byte = 0;
        prev_sclk = 0;
    end

    always @(posedge clk) begin
        // Detect rising edge of SCLK
        if (sclk && !prev_sclk && !ss) begin
            spi_received_byte = {spi_received_byte[6:0], mosi};
            bit_count = bit_count + 1;

            if (bit_count == 8) begin
                $display("[%0t ns] SPI Byte Transmitted: 0x%h (%d)", $time, spi_received_byte, spi_received_byte);
                bit_count = 0;
                spi_received_byte = 0;
            end
        end
        prev_sclk = sclk;
    end

    //===========================================
    // Waveform Dump (for GTKWave or similar)
    //===========================================
    initial begin
        $dumpfile("master_top.vcd");
        $dumpvars(0, tb_master_top);
    end

    //===========================================
    // Monitor Counter Changes
    //===========================================
    always @(posedge clk) begin
        if (o_counter !== $past(o_counter)) begin
            $display("[%0t ns] Counter changed: %d -> %d", $time, $past(o_counter), o_counter);
        end
    end

endmodule
