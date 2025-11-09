`timescale 1ns / 1ps

module slave_top_tb;

    // Clock and reset
    logic clk;
    logic reset;

    // SPI signals (manually generated)
    logic sclk;
    logic mosi;
    logic miso;
    logic ss;

    // FND outputs
    logic [3:0] fnd_com;
    logic [7:0] fnd_data;

    // Debug outputs
    logic [13:0] o_counter;
    logic        o_data_valid;

    // Clock generation: 100MHz (10ns period)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // DUT instantiation
    slave_top DUT (
        .clk         (clk),
        .reset       (reset),
        .sclk        (sclk),
        .mosi        (mosi),
        .miso        (miso),
        .ss          (ss),
        .fnd_com     (fnd_com),
        .fnd_data    (fnd_data),
        .o_counter   (o_counter),
        .o_data_valid(o_data_valid)
    );

    // SPI clock generation task (~1MHz = 1us period)
    task automatic send_spi_byte(input logic [7:0] data);
        integer i;
        begin
            $display("    Sending SPI byte: 0x%02X", data);
            for (i = 7; i >= 0; i--) begin
                // Setup data
                mosi = data[i];
                #500;  // 0.5us
                // Rising edge of SCLK
                sclk = 1;
                #500;  // 0.5us
                // Falling edge of SCLK
                sclk = 0;
            end
        end
    endtask

    // Monitor
    initial begin
        $display("=====================================");
        $display("Slave Top Testbench");
        $display("=====================================");
        $display("Time(ns) | SS | VALID | COUNTER | FND_COM | FND_DATA");
        $display("----------------------------------------------------");
    end

    // Monitor data_valid
    always @(posedge clk) begin
        if (o_data_valid) begin
            $display("%8t | %b  | %b     | %5d   | %4b    | %8b",
                $time, ss, o_data_valid, o_counter, fnd_com, fnd_data);
        end
    end

    // Test stimulus
    initial begin
        // Initialize
        reset = 1;
        sclk = 0;
        mosi = 0;
        ss = 1;  // Inactive

        // Reset for 100ns
        #100;
        reset = 0;
        $display(">>> RESET Released");
        #200;

        // ==========================================
        // Test 1: Send counter value = 1 (0x0001)
        // ==========================================
        $display("\n>>> Test 1: Send 14-bit counter = 1");
        $display("    High byte = 0x00, Low byte = 0x01");

        // Start transaction (SS low)
        ss = 0;
        #1000;

        // Send high byte: {2'b00, counter[13:8]} = 0x00
        send_spi_byte(8'h00);
        #1000;

        // Send low byte: counter[7:0] = 0x01
        send_spi_byte(8'h01);
        #1000;

        // End transaction (SS high)
        ss = 1;
        #5000;

        $display("    Expected: o_counter = 1");
        $display("    Actual:   o_counter = %d", o_counter);

        // ==========================================
        // Test 2: Send counter value = 255 (0x00FF)
        // ==========================================
        $display("\n>>> Test 2: Send 14-bit counter = 255");
        $display("    High byte = 0x00, Low byte = 0xFF");

        ss = 0;
        #1000;
        send_spi_byte(8'h00);
        #1000;
        send_spi_byte(8'hFF);
        #1000;
        ss = 1;
        #5000;

        $display("    Expected: o_counter = 255");
        $display("    Actual:   o_counter = %d", o_counter);

        // ==========================================
        // Test 3: Send counter value = 256 (0x0100)
        // ==========================================
        $display("\n>>> Test 3: Send 14-bit counter = 256");
        $display("    High byte = 0x01, Low byte = 0x00");

        ss = 0;
        #1000;
        send_spi_byte(8'h01);
        #1000;
        send_spi_byte(8'h00);
        #1000;
        ss = 1;
        #5000;

        $display("    Expected: o_counter = 256");
        $display("    Actual:   o_counter = %d", o_counter);

        // ==========================================
        // Test 4: Send counter value = 1234 (0x04D2)
        // ==========================================
        $display("\n>>> Test 4: Send 14-bit counter = 1234");
        $display("    High byte = 0x04, Low byte = 0xD2");

        ss = 0;
        #1000;
        send_spi_byte(8'h04);
        #1000;
        send_spi_byte(8'hD2);
        #1000;
        ss = 1;
        #5000;

        $display("    Expected: o_counter = 1234");
        $display("    Actual:   o_counter = %d", o_counter);

        // ==========================================
        // Test 5: Send max 14-bit value = 16383 (0x3FFF)
        // ==========================================
        $display("\n>>> Test 5: Send 14-bit counter = 16383 (max)");
        $display("    High byte = 0x3F, Low byte = 0xFF");

        ss = 0;
        #1000;
        send_spi_byte(8'h3F);
        #1000;
        send_spi_byte(8'hFF);
        #1000;
        ss = 1;
        #5000;

        $display("    Expected: o_counter = 16383");
        $display("    Actual:   o_counter = %d", o_counter);

        // ==========================================
        // Summary
        // ==========================================
        $display("\n=====================================");
        $display("Test Summary:");
        $display("- All received counters should match expected values");
        $display("- FND should display correct digits");
        $display("=====================================");

        #1000;
        $display("\n>>> Simulation Complete");
        $finish;
    end

    // Timeout watchdog
    initial begin
        #10000000;  // 10ms timeout
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule
