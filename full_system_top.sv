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

    // Output lower 8 bits to LEDs
    assign master_counter = master_counter_full[7:0];

    //===========================================
    // Master Instance
    //===========================================
    master_top U_MASTER (
        .clk      (clk),
        .reset    (reset),
        .i_runstop(i_runstop),
        .i_clear  (i_clear),
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
