`timescale 1ns / 1ps

// Full System Top Module for Single Board Testing
// Integrates both Master and Slave on one FPGA
// Master SPI signals output to JB port
// Slave SPI signals input from JC port
// Connect JB -> JC with jumper wires for testing
module full_system_top #(
    parameter TICK_PERIOD_MS = 1000,     // Default 1 second
    parameter DEBOUNCE_TIME_MS = 20      // Default 20ms
) (
    // Global signals
    input  logic       clk,          // 100MHz system clock
    input  logic       reset,        // Reset button (center)

    // Master control buttons
    input  logic       i_runstop,    // BTNU - Run/Stop counter
    input  logic       i_clear,      // BTND - Clear counter

    // Master SPI outputs (JB port)
    output logic       master_sclk,  // JB[0] - Master SCK output
    output logic       master_mosi,  // JB[1] - Master MOSI output
    output logic       master_ss,    // JB[2] - Master SS output

    // Slave SPI inputs (JC port)
    input  logic       slave_sclk,   // JC[0] - Slave SCK input
    input  logic       slave_mosi,   // JC[1] - Slave MOSI input
    input  logic       slave_ss,     // JC[2] - Slave SS input

    // FND outputs (from Slave)
    output logic [3:0] fnd_com,
    output logic [7:0] fnd_data,

    // Debug outputs
    output logic [7:0] master_counter,  // LED[7:0] = master counter value
    output logic       debug_runstop,   // LED[8] = o_runstop status
    output logic       debug_tick,      // LED[9] = tick signal
    output logic [3:0] slave_counter_low, // LED[13:10] = slave counter [3:0]
    output logic       debug_slave_valid, // LED[14] = slave data valid
    output logic       debug_spi_active   // LED[15] = SPI active (SS low)
);

    // MISO signals (not used in this design, but needed for module interface)
    logic master_miso;
    logic slave_miso;

    // Full master counter for debug
    logic [13:0] master_counter_full;
    logic [13:0] slave_counter_full;
    logic        slave_data_valid;

    // Debounced button signals
    logic runstop_debounced;
    logic clear_debounced;

    // Edge-detected pulse signals
    logic runstop_pulse;
    logic clear_pulse;

    // Internal debug signals from master
    logic master_runstop_status;
    logic master_tick;

    // Output to LEDs for debugging
    assign master_counter = master_counter_full[7:0];     // LED[7:0]: Master counter
    assign debug_runstop = master_runstop_status;         // LED[8]: RUN/STOP state
    assign debug_tick = master_tick;                      // LED[9]: Tick pulse
    assign slave_counter_low = slave_counter_full[3:0];   // LED[13:10]: Slave counter [3:0]
    assign debug_slave_valid = slave_data_valid;          // LED[14]: Slave received data
    assign debug_spi_active = ~slave_ss;                  // LED[15]: SPI active (SS is active low)

    // MISO not used, tie to 0
    assign master_miso = 1'b0;
    assign slave_miso = 1'b0;

    //===========================================
    // Button Debouncers
    //===========================================
    debouncer #(.DEBOUNCE_TIME_MS(DEBOUNCE_TIME_MS)) U_DEBOUNCE_RUNSTOP (
        .clk    (clk),
        .reset  (reset),
        .btn_in (i_runstop),
        .btn_out(runstop_debounced)
    );

    debouncer #(.DEBOUNCE_TIME_MS(DEBOUNCE_TIME_MS)) U_DEBOUNCE_CLEAR (
        .clk    (clk),
        .reset  (reset),
        .btn_in (i_clear),
        .btn_out(clear_debounced)
    );

    //===========================================
    // Edge Detectors (level -> pulse)
    //===========================================
    edge_detector U_EDGE_RUNSTOP (
        .clk    (clk),
        .reset  (reset),
        .i_level(runstop_debounced),
        .o_pulse(runstop_pulse)
    );

    edge_detector U_EDGE_CLEAR (
        .clk    (clk),
        .reset  (reset),
        .i_level(clear_debounced),
        .o_pulse(clear_pulse)
    );

    //===========================================
    // Master Instance - Outputs to JB port
    //===========================================
    master_top #(
        .TICK_PERIOD_MS(TICK_PERIOD_MS)
    ) U_MASTER (
        .clk             (clk),
        .reset           (reset),
        .i_runstop       (runstop_pulse),      // Use pulse signal for toggle behavior
        .i_clear         (clear_pulse),        // Use pulse signal for toggle behavior
        .sclk            (master_sclk),        // Output to JB[0]
        .mosi            (master_mosi),        // Output to JB[1]
        .miso            (master_miso),        // Not used
        .ss              (master_ss),          // Output to JB[2]
        .o_counter       (master_counter_full),
        .o_runstop_status(master_runstop_status),
        .o_tick          (master_tick)
    );

    //===========================================
    // Slave Instance - Inputs from JC port
    //===========================================
    slave_top U_SLAVE (
        .clk         (clk),
        .reset       (reset),
        .sclk        (slave_sclk),             // Input from JC[0]
        .mosi        (slave_mosi),             // Input from JC[1]
        .miso        (slave_miso),             // Not used
        .ss          (slave_ss),               // Input from JC[2]
        .fnd_com     (fnd_com),
        .fnd_data    (fnd_data),
        .o_counter   (slave_counter_full),
        .o_data_valid(slave_data_valid)
    );

endmodule


// Edge detector module
module edge_detector (
    input  logic clk,
    input  logic reset,
    input  logic i_level,  // Debounced level signal
    output logic o_pulse   // 1-clock pulse signal
);
    logic level_reg;

    always_ff @(posedge clk or posedge reset) begin
        if (reset)
            level_reg <= 1'b0;
        else
            level_reg <= i_level;
    end

    // Detect rising edge (0 -> 1 transition)
    assign o_pulse = ~level_reg && i_level;

endmodule
