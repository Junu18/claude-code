`timescale 1ns / 1ps

module master_top (
    //global signals
    input  logic clk,
    input  logic reset,

    // button inputs
    input  logic i_runstop,
    input  logic i_clear,

    // SPI signals
    output logic sclk,
    output logic mosi,
    input  logic miso,
    output logic ss,

    // debug outputs (optional)
    output logic [13:0] o_counter
);

    // Internal signals
    logic        w_o_runstop;
    logic        w_o_clear;
    logic [13:0] w_counter;

    // SPI master signals
    logic        spi_start;
    logic [7:0]  spi_tx_data;
    logic [7:0]  spi_rx_data;
    logic        spi_tx_ready;
    logic        spi_done;

    // Tick generation
    logic        counter_tick;

    // Byte splitting
    logic [7:0]  tx_high_byte;
    logic [7:0]  tx_low_byte;

    // FSM signals
    typedef enum logic [2:0] {
        IDLE,
        SEND_HIGH,
        WAIT_HIGH,
        SEND_LOW,
        WAIT_LOW
    } state_t;

    state_t state, state_next;
    logic [7:0] tx_data_reg, tx_data_next;
    logic ss_reg, ss_next;

    // Debug output
    assign o_counter = w_counter;

    // Byte splitting: 14-bit counter -> 2 bytes
    // High byte: 2-bit padding + upper 6 bits
    // Low byte: lower 8 bits
    assign tx_high_byte = {2'b00, w_counter[13:8]};
    assign tx_low_byte  = w_counter[7:0];

    // Slave Select (active low, controlled by FSM)
    assign ss = ss_reg;

    //===========================================
    // Tick Generator (100ms period)
    //===========================================
    tick_gen #(
        .TICK_PERIOD_MS(100)  // 100ms마다 tick
    ) U_TICK_GEN (
        .clk  (clk),
        .reset(reset),
        .tick (counter_tick)
    );

    //===========================================
    // SPI Master Module
    //===========================================
    spi_master U_SPI_MASTER (
        .clk     (clk),
        .reset   (reset),
        .start   (spi_start),
        .tx_data (spi_tx_data),
        .rx_data (spi_rx_data),
        .tx_ready(spi_tx_ready),
        .done    (spi_done),
        .sclk    (sclk),
        .mosi    (mosi),
        .miso    (miso)
    );

    //===========================================
    // Counter Control Unit
    //===========================================
    spi_upcounter_cu U_SPI_UPCOUNT_CU (
        .clk      (clk),
        .reset    (reset),
        .i_runstop(i_runstop),
        .i_clear  (i_clear),
        .o_runstop(w_o_runstop),
        .o_clear  (w_o_clear)
    );

    //===========================================
    // Counter Datapath
    //===========================================
    spi_upcounter_dp U_SPI_UPCOUNT_DP (
        .clk        (clk),
        .reset      (reset),
        .i_o_runstop(w_o_runstop),
        .i_o_clear  (w_o_clear),
        .counter    (w_counter)
    );

    //===========================================
    // FSM: 2-Byte SPI Transmission Control
    //===========================================

    // State register
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state       <= IDLE;
            tx_data_reg <= 8'h00;
            ss_reg      <= 1'b1;  // Inactive at reset
        end else begin
            state       <= state_next;
            tx_data_reg <= tx_data_next;
            ss_reg      <= ss_next;
        end
    end

    // SPI tx_data assignment
    assign spi_tx_data = tx_data_reg;

    // Next state logic
    always_comb begin
        state_next   = state;
        tx_data_next = tx_data_reg;
        ss_next      = ss_reg;
        spi_start    = 1'b0;

        case (state)
            IDLE: begin
                ss_next = 1'b1;  // SS inactive (high)
                if (counter_tick) begin
                    // Tick 발생 시 high byte 전송 준비
                    tx_data_next = tx_high_byte;
                    ss_next      = 1'b0;  // SS active (low) - 트랜잭션 시작
                    state_next   = SEND_HIGH;
                end
            end

            SEND_HIGH: begin
                ss_next   = 1'b0;  // Keep SS active
                spi_start = 1'b1;
                state_next = WAIT_HIGH;
            end

            WAIT_HIGH: begin
                ss_next = 1'b0;  // Keep SS active
                if (spi_done) begin
                    tx_data_next = tx_low_byte;
                    state_next   = SEND_LOW;
                end
            end

            SEND_LOW: begin
                ss_next   = 1'b0;  // Keep SS active
                spi_start = 1'b1;
                state_next = WAIT_LOW;
            end

            WAIT_LOW: begin
                if (spi_done) begin
                    ss_next    = 1'b1;  // SS inactive (high) - 트랜잭션 완료
                    state_next = IDLE;
                end else begin
                    ss_next = 1'b0;  // Keep SS active during transmission
                end
            end

            default: begin
                ss_next    = 1'b1;
                state_next = IDLE;
            end
        endcase
    end

endmodule
