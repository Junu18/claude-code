`timescale 1ns / 1ps

// Button debouncer module
module debouncer #(
    parameter DEBOUNCE_TIME_MS = 20  // 20ms debounce time
) (
    input  logic clk,
    input  logic reset,
    input  logic btn_in,      // Raw button input
    output logic btn_out      // Debounced output
);

    // 100MHz clock, 20ms = 2,000,000 clocks
    localparam DEBOUNCE_CLOCKS = DEBOUNCE_TIME_MS * 100_000;
    localparam COUNTER_WIDTH = $clog2(DEBOUNCE_CLOCKS);

    logic [COUNTER_WIDTH-1:0] counter;
    logic btn_sync1, btn_sync2;  // Synchronizer
    logic btn_stable;

    // 2-stage synchronizer
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            btn_sync1 <= 1'b0;
            btn_sync2 <= 1'b0;
        end else begin
            btn_sync1 <= btn_in;
            btn_sync2 <= btn_sync1;
        end
    end

    // Debounce logic
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            counter <= 0;
            btn_stable <= 1'b0;
        end else begin
            if (btn_sync2 != btn_stable) begin
                // Button state is changing
                if (counter == DEBOUNCE_CLOCKS - 1) begin
                    btn_stable <= btn_sync2;
                    counter <= 0;
                end else begin
                    counter <= counter + 1;
                end
            end else begin
                counter <= 0;
            end
        end
    end

    assign btn_out = btn_stable;

endmodule
