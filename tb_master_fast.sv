`timescale 1ns / 1ps

module tb_master_fast;

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

    // Debug outputs
    logic [13:0] o_counter;
    logic [2:0]  o_state;

    //===========================================
    // DUT (Device Under Test) - Fast version
    //===========================================
    master_top_fast DUT (
        .clk      (clk),
        .reset    (reset),
        .i_runstop(i_runstop),
        .i_clear  (i_clear),
        .sclk     (sclk),
        .mosi     (mosi),
        .miso     (miso),
        .ss       (ss),
        .o_counter(o_counter),
        .o_state  (o_state)
    );

    //===========================================
    // Clock Generation: 100MHz (10ns period)
    //===========================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    //===========================================
    // MISO simulation (loopback)
    //===========================================
    assign miso = mosi;

    //===========================================
    // State Name Display
    //===========================================
    function string state_name(logic [2:0] s);
        case (s)
            3'b000:  return "IDLE";
            3'b001:  return "SEND_HIGH";
            3'b010:  return "WAIT_HIGH";
            3'b011:  return "SEND_LOW";
            3'b100:  return "WAIT_LOW";
            default: return "UNKNOWN";
        endcase
    endfunction

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
        $display("  SPI Master Fast Test");
        $display("  Clock: 100MHz");
        $display("  Tick Period: 1ms (fast sim)");
        $display("========================================\n");

        // Test 1: Start counter
        $display("[%0t ns] TEST 1: Press RUN/STOP to start counter", $time);
        #1000;
        i_runstop = 1;
        #100;
        i_runstop = 0;
        $display("[%0t ns] Counter started\n", $time);

        // Wait for several tick periods to see SPI transmissions
        // 1ms = 1,000,000 ns = 100,000 clocks
        #5_000_000;  // 5ms = 5 ticks

        $display("\n[%0t ns] Current counter: %d (0x%04h)", $time, o_counter, o_counter);

        // Test 2: Stop counter
        $display("\n[%0t ns] TEST 2: Press RUN/STOP to stop counter", $time);
        i_runstop = 1;
        #100;
        i_runstop = 0;
        $display("[%0t ns] Counter stopped", $time);

        #2_000_000;
        $display("[%0t ns] Counter value (stopped): %d (0x%04h)\n", $time, o_counter, o_counter);

        // Test 3: Clear counter
        $display("[%0t ns] TEST 3: Press CLEAR", $time);
        i_clear = 1;
        #100;
        i_clear = 0;
        #1000;
        $display("[%0t ns] Counter cleared: %d\n", $time, o_counter);

        // Test 4: Restart and observe multiple transmissions
        $display("[%0t ns] TEST 4: Restart and observe SPI transmissions", $time);
        i_runstop = 1;
        #100;
        i_runstop = 0;

        // Run for several ticks
        #10_000_000;  // 10ms = 10 ticks

        $display("\n========================================");
        $display("  Test Complete");
        $display("  Final Counter: %d (0x%04h)", o_counter, o_counter);
        $display("  High Byte: 0x%02h", {2'b00, o_counter[13:8]});
        $display("  Low Byte:  0x%02h", o_counter[7:0]);
        $display("========================================");

        #1000;
        $finish;
    end

    //===========================================
    // Monitor SPI Byte Transmissions
    //===========================================
    logic [7:0] spi_byte;
    integer bit_idx;
    logic prev_sclk;
    logic [1:0] byte_count;

    initial begin
        bit_idx = 0;
        spi_byte = 0;
        prev_sclk = 0;
        byte_count = 0;
    end

    always @(posedge clk) begin
        // Rising edge of SCLK
        if (sclk && !prev_sclk && !ss) begin
            spi_byte = {spi_byte[6:0], mosi};
            bit_idx = bit_idx + 1;

            if (bit_idx == 8) begin
                byte_count = byte_count + 1;
                if (byte_count == 1) begin
                    $display("[%0t ns] → SPI TX High Byte: 0x%02h", $time, spi_byte);
                end else if (byte_count == 2) begin
                    $display("[%0t ns] → SPI TX Low Byte:  0x%02h", $time, spi_byte);
                    byte_count = 0;
                end
                bit_idx = 0;
                spi_byte = 0;
            end
        end
        prev_sclk = sclk;
    end

    //===========================================
    // Monitor FSM State Changes
    //===========================================
    logic [2:0] prev_state;
    initial prev_state = 0;

    always @(posedge clk) begin
        if (o_state != prev_state) begin
            $display("[%0t ns] FSM: %s → %s", $time,
                     state_name(prev_state), state_name(o_state));
            prev_state = o_state;
        end
    end

    //===========================================
    // Monitor Tick Events
    //===========================================
    always @(posedge clk) begin
        if (DUT.counter_tick) begin
            $display("[%0t ns] ★ TICK occurred! Counter=%d", $time, o_counter);
        end
    end

    //===========================================
    // Monitor SS (Slave Select) Signal
    //===========================================
    logic prev_ss;
    initial prev_ss = 1'b1;

    always @(posedge clk) begin
        // Falling edge: Transaction starts
        if (!ss && prev_ss) begin
            $display("[%0t ns] ▼ SS: Transaction START (SS goes LOW)", $time);
        end
        // Rising edge: Transaction ends
        if (ss && !prev_ss) begin
            $display("[%0t ns] ▲ SS: Transaction END (SS goes HIGH)", $time);
        end
        prev_ss = ss;
    end

    //===========================================
    // Waveform Dump
    //===========================================
    initial begin
        $dumpfile("master_top_fast.vcd");
        $dumpvars(0, tb_master_fast);
    end

endmodule
