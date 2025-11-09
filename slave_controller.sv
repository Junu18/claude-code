`timescale 1ns / 1ps

module slave_controller (
    input  logic        clk,
    input  logic        reset,
    // From spi_slave
    input  logic [7:0]  rx_data,
    input  logic        done,
    // From master (for transaction boundary detection)
    input  logic        ss,
    // To fnd_controller
    output logic [13:0] counter,
    output logic        data_valid  // Pulse when new 14-bit data is ready
);

    typedef enum logic [1:0] {
        IDLE,
        WAIT_HIGH,
        WAIT_LOW,
        DATA_READY
    } state_t;

    state_t state, state_next;

    logic [7:0] high_byte_reg, high_byte_next;
    logic [7:0] low_byte_reg, low_byte_next;
    logic [13:0] counter_reg, counter_next;
    logic data_valid_reg, data_valid_next;

    // Edge detection for SS
    logic ss_sync1, ss_sync2;
    logic ss_rising_edge;

    assign counter = counter_reg;
    assign data_valid = data_valid_reg;

    //===========================================
    // Synchronize SS and detect rising edge
    //===========================================
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            ss_sync1 <= 1'b1;
            ss_sync2 <= 1'b1;
        end else begin
            ss_sync1 <= ss;
            ss_sync2 <= ss_sync1;
        end
    end

    assign ss_rising_edge = ss_sync1 && !ss_sync2;  // Transaction end

    //===========================================
    // State Machine
    //===========================================
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state         <= IDLE;
            high_byte_reg <= 8'h00;
            low_byte_reg  <= 8'h00;
            counter_reg   <= 14'd0;
            data_valid_reg <= 1'b0;
        end else begin
            state         <= state_next;
            high_byte_reg <= high_byte_next;
            low_byte_reg  <= low_byte_next;
            counter_reg   <= counter_next;
            data_valid_reg <= data_valid_next;
        end
    end

    always_comb begin
        state_next      = state;
        high_byte_next  = high_byte_reg;
        low_byte_next   = low_byte_reg;
        counter_next    = counter_reg;
        data_valid_next = 1'b0;  // Default: no pulse

        case (state)
            IDLE: begin
                // Wait for SS to go low (transaction start)
                if (!ss_sync2) begin
                    state_next = WAIT_HIGH;
                end
            end

            WAIT_HIGH: begin
                // Wait for first byte (high byte)
                if (ss_rising_edge) begin
                    // Transaction aborted
                    state_next = IDLE;
                end else if (done) begin
                    // High byte received
                    high_byte_next = rx_data;
                    state_next     = WAIT_LOW;
                end
            end

            WAIT_LOW: begin
                // Wait for second byte (low byte)
                if (ss_rising_edge) begin
                    // Transaction aborted
                    state_next = IDLE;
                end else if (done) begin
                    // Low byte received - combine into 14-bit counter
                    low_byte_next = rx_data;
                    state_next    = DATA_READY;
                end
            end

            DATA_READY: begin
                // Combine high and low bytes
                // High byte format: {2'b00, counter[13:8]} -> use only [5:0]
                // Low byte format:  counter[7:0]
                counter_next = {high_byte_reg[5:0], low_byte_reg[7:0]};
                data_valid_next = 1'b1;  // Signal valid data

                // Wait for SS rising edge (transaction complete)
                if (ss_rising_edge) begin
                    state_next = IDLE;
                end
            end

            default: begin
                state_next = IDLE;
            end
        endcase
    end

endmodule
