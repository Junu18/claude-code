`timescale 1ns / 1ps

// Full System Top Module for Single Board Testing
// Integrates both Master and Slave on one FPGA
module full_system_top (
    // Global signals
    input  logic       clk,          // 100MHz system clock
    input  logic       reset,        // Reset button (center)

    // Master control buttons
    input  logic       i_runstop,    // BTNU - Run/Stop counter
    input  logic       i_clear,      // BTND - Clear counter

    // FND outputs (from Slave)
    output logic [3:0] fnd_com,
    output logic [7:0] fnd_data,

    // Debug outputs (Master counter on LEDs)
    output logic [7:0] master_counter
);

    // Internal SPI signals (connect Master to Slave)
    logic sclk_internal;
    logic mosi_internal;
    logic miso_internal;
    logic ss_internal;

    // Full master counter for debug
    logic [13:0] master_counter_full;
    logic [13:0] slave_counter_full;
    logic        slave_data_valid;

    // Debounced button signals
    logic runstop_debounced;
    logic clear_debounced;

    // Edge-detected button signals (pulse)
    logic runstop_pulse;
    logic clear_pulse;

    // Output lower 8 bits to LEDs
    assign master_counter = master_counter_full[7:0];

    //===========================================
    // Button Debouncers
    //===========================================
    debouncer #(.DEBOUNCE_TIME_MS(20)) U_DEBOUNCE_RUNSTOP (
        .clk    (clk),
        .reset  (reset),
        .btn_in (i_runstop),
        .btn_out(runstop_debounced)
    );

    debouncer #(.DEBOUNCE_TIME_MS(20)) U_DEBOUNCE_CLEAR (
        .clk    (clk),
        .reset  (reset),
        .btn_in (i_clear),
        .btn_out(clear_debounced)
    );

    //===========================================
    // Edge Detectors (button press = rising edge)
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
    // Master Instance
    //===========================================
    master_top U_MASTER (
        .clk      (clk),
        .reset    (reset),
        .i_runstop(runstop_pulse),   // Use edge-detected pulse
        .i_clear  (clear_pulse),     // Use edge-detected pulse
        .sclk     (sclk_internal),
        .mosi     (mosi_internal),
        .miso     (miso_internal),
        .ss       (ss_internal),
        .o_counter(master_counter_full)
    );

    //===========================================
    // Slave Instance
    //===========================================
    slave_top U_SLAVE (
        .clk         (clk),
        .reset       (reset),
        .sclk        (sclk_internal),
        .mosi        (mosi_internal),
        .miso        (miso_internal),
        .ss          (ss_internal),
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
