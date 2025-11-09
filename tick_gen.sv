`timescale 1ns / 1ps

// 100MHz 클럭 기준 tick 생성기
// 기본: 100ms마다 tick 발생 (10,000,000 클럭)
module tick_gen #(
    parameter TICK_PERIOD_MS = 100  // ms 단위
) (
    input  logic clk,
    input  logic reset,
    output logic tick
);

    // 100MHz = 100,000,000 Hz
    // 1ms = 100,000 clocks
    // 100ms = 10,000,000 clocks
    localparam CLOCKS_PER_MS = 100_000;
    localparam TICK_COUNT = TICK_PERIOD_MS * CLOCKS_PER_MS;

    localparam COUNTER_WIDTH = $clog2(TICK_COUNT);

    logic [COUNTER_WIDTH-1:0] counter;
    logic tick_reg;

    assign tick = tick_reg;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            counter  <= 0;
            tick_reg <= 0;
        end else begin
            if (counter == TICK_COUNT - 1) begin
                counter  <= 0;
                tick_reg <= 1'b1;
            end else begin
                counter  <= counter + 1;
                tick_reg <= 1'b0;
            end
        end
    end

endmodule
