`timescale 1ns / 1ps

module spi_slave (
    input  logic       clk,      // System clock (100MHz)
    input  logic       reset,
    // SPI signals from master
    input  logic       sclk,
    input  logic       mosi,
    output logic       miso,
    input  logic       ss,       // Slave select (active low)
    // To slave_controller
    output logic [7:0] rx_data,
    output logic       done      // 1 clock pulse when byte received
);

    // Synchronize SCLK and SS to system clock domain
    logic sclk_sync1, sclk_sync2;
    logic ss_sync1, ss_sync2;
    logic mosi_sync1, mosi_sync2;

    // Edge detection for SCLK
    logic sclk_rising_edge;

    // Internal registers
    logic [7:0] rx_shift_reg;
    logic [2:0] bit_counter;
    logic       done_reg;

    assign rx_data = rx_shift_reg;
    assign done = done_reg;
    assign miso = 1'b0;  // Not used in this design

    //===========================================
    // Synchronize external signals to clk domain
    //===========================================
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            sclk_sync1 <= 0;
            sclk_sync2 <= 0;
            ss_sync1   <= 1;  // SS inactive
            ss_sync2   <= 1;
            mosi_sync1 <= 0;
            mosi_sync2 <= 0;
        end else begin
            // Two-stage synchronizer
            sclk_sync1 <= sclk;
            sclk_sync2 <= sclk_sync1;
            ss_sync1   <= ss;
            ss_sync2   <= ss_sync1;
            mosi_sync1 <= mosi;
            mosi_sync2 <= mosi_sync1;
        end
    end

    // Detect rising edge of SCLK
    assign sclk_rising_edge = sclk_sync1 && !sclk_sync2;

    //===========================================
    // SPI Slave Logic
    //===========================================
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            rx_shift_reg <= 8'h00;
            bit_counter  <= 3'd0;
            done_reg     <= 1'b0;
        end else begin
            done_reg <= 1'b0;  // Default: clear done

            if (ss_sync2) begin
                // SS inactive (high) - reset state
                rx_shift_reg <= 8'h00;
                bit_counter  <= 3'd0;
            end else begin
                // SS active (low) - receive data
                if (sclk_rising_edge) begin
                    // Shift in new bit (MSB first)
                    rx_shift_reg <= {rx_shift_reg[6:0], mosi_sync2};
                    bit_counter  <= bit_counter + 1;

                    // Check if byte complete
                    if (bit_counter == 3'd7) begin
                        done_reg    <= 1'b1;  // Signal byte complete
                        bit_counter <= 3'd0;
                    end
                end
            end
        end
    end

endmodule
