`timescale 1ns / 1ps

module slave_top (
    // Global signals
    input  logic       clk,
    input  logic       reset,

    // SPI signals from master
    input  logic       sclk,
    input  logic       mosi,
    output logic       miso,
    input  logic       ss,

    // FND outputs
    output logic [3:0] fnd_com,
    output logic [7:0] fnd_data,

    // Debug outputs (optional)
    output logic [13:0] o_counter,
    output logic        o_data_valid
);

    // Internal signals
    logic [7:0]  spi_rx_data;
    logic        spi_done;
    logic [13:0] controller_counter;
    logic        controller_data_valid;

    // Debug outputs
    assign o_counter = controller_counter;
    assign o_data_valid = controller_data_valid;

    //===========================================
    // SPI Slave Module
    //===========================================
    spi_slave U_SPI_SLAVE (
        .clk    (clk),
        .reset  (reset),
        .sclk   (sclk),
        .mosi   (mosi),
        .miso   (miso),
        .ss     (ss),
        .rx_data(spi_rx_data),
        .done   (spi_done)
    );

    //===========================================
    // Slave Controller (2-byte combiner)
    //===========================================
    slave_controller U_SLAVE_CONTROLLER (
        .clk       (clk),
        .reset     (reset),
        .rx_data   (spi_rx_data),
        .done      (spi_done),
        .ss        (ss),
        .counter   (controller_counter),
        .data_valid(controller_data_valid)
    );

    //===========================================
    // FND Controller
    //===========================================
    fnd_controller U_FND_CONTROLLER (
        .clk     (clk),
        .reset   (reset),
        .counter (controller_counter),
        .fnd_com (fnd_com),
        .fnd_data(fnd_data)
    );

endmodule
