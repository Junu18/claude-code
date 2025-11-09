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

    // Clock generation: 100MHz (10ns period)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // DUT instantiation with fast tick for simulation
    master_top #(
        .TICK_PERIOD_MS(1)  // 1ms = 100,000 clocks (짧게 설정)
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

    // Monitoring signals
    initial begin
        $display("=====================================");
        $display("Master Top Testbench");
        $display("TICK_PERIOD = 1ms (100,000 clocks)");
        $display("=====================================");
        $display("Time(ns) | RST | BTN_RUN | RUNSTOP | TICK | COUNTER | SS | SPI_STATE");
        $display("----------------------------------------------------------------------");
    end

    // Monitor every significant change
    always @(posedge clk) begin
        if (o_tick || i_runstop || i_clear || (o_counter != 0 && o_counter < 10)) begin
            $display("%8t | %b   | %b       | %b       | %b    | %5d   | %b  | %s",
                $time, reset, i_runstop, o_runstop_status, o_tick, o_counter, ss,
                get_spi_state_name());
        end
    end

    // Function to get SPI FSM state name
    function string get_spi_state_name();
        case (DUT.state)
            DUT.IDLE:      return "IDLE     ";
            DUT.SEND_HIGH: return "SEND_HIGH";
            DUT.WAIT_HIGH: return "WAIT_HIGH";
            DUT.SEND_LOW:  return "SEND_LOW ";
            DUT.WAIT_LOW:  return "WAIT_LOW ";
            default:       return "UNKNOWN  ";
        endcase
    endfunction

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

        // Wait a bit
        #200;

        // ==========================================
        // Test 1: Press RUNSTOP button (toggle to RUN)
        // ==========================================
        $display("\n>>> Test 1: Press RUNSTOP button (start counting)");
        @(posedge clk);
        i_runstop = 1;  // Button press (pulse)
        @(posedge clk);
        i_runstop = 0;
        $display("    Expected: o_runstop_status = 1, counter starts incrementing");

        // Wait for 10 ticks to observe counter increment
        // 1 tick = 100,000 clocks = 1ms = 1,000,000 ns
        repeat(10) begin
            @(posedge o_tick);
            $display("    TICK detected! Counter = %d", o_counter);
        end

        // ==========================================
        // Test 2: Press RUNSTOP button again (toggle to STOP)
        // ==========================================
        $display("\n>>> Test 2: Press RUNSTOP button again (stop counting)");
        @(posedge clk);
        i_runstop = 1;  // Button press (pulse)
        @(posedge clk);
        i_runstop = 0;
        $display("    Expected: o_runstop_status = 0, counter stops");

        // Wait for a few potential ticks
        #5000000;  // 5ms
        $display("    After 5ms: Counter = %d (should not change)", o_counter);

        // ==========================================
        // Test 3: Press CLEAR button
        // ==========================================
        $display("\n>>> Test 3: Press CLEAR button");
        @(posedge clk);
        i_clear = 1;  // Button press (pulse)
        @(posedge clk);
        i_clear = 0;
        #100;
        $display("    Expected: Counter = 0");
        $display("    Actual: Counter = %d", o_counter);

        // ==========================================
        // Test 4: Start again and check from 0
        // ==========================================
        $display("\n>>> Test 4: Start counting from 0 again");
        @(posedge clk);
        i_runstop = 1;
        @(posedge clk);
        i_runstop = 0;

        // Wait for 5 ticks
        repeat(5) begin
            @(posedge o_tick);
            $display("    TICK! Counter = %d", o_counter);
        end

        // ==========================================
        // Summary
        // ==========================================
        $display("\n=====================================");
        $display("Test Summary:");
        $display("- Counter should increment: 0->1->2->..->10");
        $display("- Counter should stop when RUNSTOP pressed again");
        $display("- Counter should clear to 0 when CLEAR pressed");
        $display("- Counter should start from 0 again");
        $display("=====================================");

        #1000;
        $display("\n>>> Simulation Complete");
        $finish;
    end

    // Timeout watchdog
    initial begin
        #100000000;  // 100ms timeout
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule
