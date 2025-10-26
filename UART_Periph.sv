`timescale 1ns / 1ps

module UART_Periph (
    input  logic        PCLK,
    input  logic        PRESET,
    input  logic [ 3:0] PADDR,
    input  logic [31:0] PWDATA,
    input  logic        PWRITE,
    input  logic        PENABLE,
    input  logic        PSEL,
    output logic [31:0] PRDATA,
    output logic        PREADY,
    input  logic        rx,   // (idle 시 1로 유지됨)
    output logic        tx
);

    logic empty_TX, full_TX;
    logic empty_RX, full_RX;
    logic we_TX, re_RX;
    logic tick;
    logic [7:0] wdata_TX, rdata_TX;
    logic [7:0] wdata_RX, rdata_RX;
    logic rx_done;
    logic o_tx_done;

    APB_SlaveIntf_UART U_APB_SlaveIntf_UART(
        .*,
        .USR({full_RX, empty_TX, !full_TX, !empty_RX}),
        .UWD(wdata_TX),
        .URD(rdata_RX)
    );

    fifo U_FIFO_TX (
        .clk(PCLK),
        .reset(PRESET),
        .we(we_TX),
        .re(o_tx_done),
        .wdata(wdata_TX),
        .rdata(rdata_TX),
        .empty(empty_TX),
        .full(full_TX)
    );

    fifo U_FIFO_RX (
        .clk(PCLK),
        .reset(PRESET),
        .we(rx_done),
        .re(re_RX),
        .wdata(wdata_RX),
        .rdata(rdata_RX),
        .empty(empty_RX),
        .full(full_RX)
    );

    uart_rx U_RX (
        .*,
        .clk(PCLK),
        .rst(PRESET),
        .rx_data(wdata_RX)
    );

    uart_tx U_TX (
        .*,
        .clk(PCLK),
        .rst(PRESET),
        .i_data(rdata_TX),
        .tx_start(!empty_TX)
    );

    baud_tick_gen U_BAUD_TICK_GEN (
        .clk(PCLK),
        .rst(PRESET),
        .baud_tick(tick)
    );
endmodule

////////////////////////////////////////////////////////////////////////////////////////

module uart_rx (
    input logic clk,
    input logic rst,
    input logic rx,
    input logic tick,
    output logic [7:0] rx_data,
    output logic rx_done
);
    typedef enum logic [1:0] {
        IDLE  = 0,
        START = 1,
        DATA  = 2,
        STOP  = 3
    } state_t;

    state_t rx_state, rx_next;
    logic [7:0] rx_out_reg, rx_out_next;
    logic [3:0] tick_cnt_reg, tick_cnt_next;
    logic [3:0] data_cnt_reg, data_cnt_next;
    logic rx_done_reg;

    assign rx_done = rx_done_reg;
    assign rx_data = rx_out_reg;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_state <= IDLE;
            rx_out_reg <= 0;
            data_cnt_reg <= 0;
            tick_cnt_reg <= 0;
            rx_done_reg <= 0;
        end else begin
            rx_state <= rx_next;
            rx_out_reg <= rx_out_next;
            data_cnt_reg <= data_cnt_next;
            tick_cnt_reg <= tick_cnt_next;
            // rx_done을 펄스화 (STOP→IDLE 직후에만 1)
            if (rx_next == IDLE && rx_state == STOP)
                rx_done_reg <= 1'b1;
            else
                rx_done_reg <= 1'b0;
        end
    end

    always_comb begin
        rx_out_next = rx_out_reg;
        rx_next = rx_state;
        data_cnt_next = data_cnt_reg;
        tick_cnt_next = tick_cnt_reg;

        case (rx_state)
            IDLE: begin
                if (!rx) rx_next = START;
            end
            START: begin
                if (tick) begin
                    if (tick_cnt_reg == 7) begin
                        tick_cnt_next = 0;
                        rx_next = DATA;
                    end else tick_cnt_next = tick_cnt_reg + 1;
                end
            end
            DATA: begin
                if (tick) begin
                    if (tick_cnt_reg == 15) begin
                        rx_out_next[data_cnt_reg] = rx;
                        tick_cnt_next = 0;
                        if (data_cnt_reg < 7)
                            data_cnt_next = data_cnt_reg + 1;
                        else begin
                            data_cnt_next = 0;
                            rx_next = STOP;
                        end
                    end else tick_cnt_next = tick_cnt_reg + 1;
                end
            end
            STOP: begin
                if (tick) begin
                    if (tick_cnt_reg == 15) begin
                        tick_cnt_next = 0;
                        rx_next = IDLE;
                    end else tick_cnt_next = tick_cnt_reg + 1;
                end
            end
        endcase
    end
endmodule

////////////////////////////////////////////////////////////////////////////////////////

module uart_tx (
    input logic clk,
    input logic rst,
    input logic [7:0] i_data,
    input logic tick,
    input logic tx_start,
    output logic tx,
    output logic o_tx_done
);
    typedef enum logic [2:0] {
        IDLE  = 0,
        SEND  = 1,
        START = 2,
        DATA  = 3,
        STOP  = 4
    } state_t;

    state_t state, next;
    logic tx_reg, tx_next;
    logic tx_done_reg, tx_done_next;
    logic [3:0] bit_count_reg, bit_count_next;
    logic [3:0] tick_count_reg, tick_count_next;
    logic [7:0] temp_data_reg, temp_data_next;

    assign tx = tx_reg;
    assign o_tx_done = tx_done_reg;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            tx_reg <= 1'b1;
            tx_done_reg <= 0;
            bit_count_reg <= 0;
            tick_count_reg <= 0;
            temp_data_reg <= 0;
        end else begin
            state <= next;
            tx_reg <= tx_next;
            tx_done_reg <= tx_done_next;
            bit_count_reg <= bit_count_next;
            tick_count_reg <= tick_count_next;
            temp_data_reg <= temp_data_next;
        end
    end

    always_comb begin
        next = state;
        tx_next = tx_reg;
        tx_done_next = 1'b0; // 기본값: 0 (STOP 직후만 1로)
        bit_count_next = bit_count_reg;
        tick_count_next = tick_count_reg;
        temp_data_next = temp_data_reg;

        case (state)
            IDLE: begin
                tx_next = 1'b1;
                if (tx_start) begin
                    next = SEND;
                    temp_data_next = i_data;
                end
            end
            SEND: if (tick) next = START;
            START: begin
                tx_next = 1'b0;
                if (tick) begin
                    if (tick_count_reg == 15) begin
                        tick_count_next = 0;
                        bit_count_next = 0;
                        next = DATA;
                    end else tick_count_next = tick_count_reg + 1;
                end
            end
            DATA: begin
                tx_next = temp_data_reg[bit_count_reg];
                if (tick) begin
                    if (tick_count_reg == 15) begin
                        tick_count_next = 0;
                        if (bit_count_reg == 7)
                            next = STOP;
                        else
                            bit_count_next = bit_count_reg + 1;
                    end else tick_count_next = tick_count_reg + 1;
                end
            end
            STOP: begin
                tx_next = 1'b1;
                if (tick) begin
                    if (tick_count_reg == 15) begin
                        tick_count_next = 0;
                        next = IDLE;
                        tx_done_next = 1'b1; // STOP 완료 시에만 1
                    end else tick_count_next = tick_count_reg + 1;
                end
            end
        endcase
    end
endmodule

////////////////////////////////////////////////////////////////////////////////////////

module fifo (
    input  logic       clk,
    input  logic       reset,
    input  logic       we,
    input  logic       re,
    input  logic [7:0] wdata,
    output logic [7:0] rdata,
    output logic       empty,
    output logic       full
);
    logic [1:0] wptr, rptr;

    fifo_ram U_FIFO_RAM (
        .clk  (clk),
        .we   (!full & we),
        .wdata(wdata),
        .waddr(wptr),
        .raddr(rptr),
        .rdata(rdata)
    );
    fifo_CU U_FIFO_CU (.*);

endmodule

////////////////////////////////////////////////////////////////////////////////////////

module fifo_ram (
    input  logic       clk,
    input  logic       we,
    input  logic [7:0] wdata,
    input  logic [1:0] waddr,
    input  logic [1:0] raddr,
    output logic [7:0] rdata
);
    logic [7:0] mem[0:3];

    always_ff @(posedge clk) begin
        if (we)
            mem[waddr] <= wdata;
    end

    assign rdata = mem[raddr];
endmodule

////////////////////////////////////////////////////////////////////////////////////////

module fifo_CU (
    input  logic       clk,
    input  logic       reset,
    input  logic       we,
    input  logic       re,
    output logic       empty,
    output logic       full,
    output logic [1:0] rptr,
    output logic [1:0] wptr
);
    logic [1:0] wptr_reg, wptr_next;
    logic [1:0] rptr_reg, rptr_next;
    logic empty_reg, empty_next;
    logic full_reg, full_next;

    assign wptr  = wptr_reg;
    assign rptr  = rptr_reg;
    assign empty = empty_reg;
    assign full  = full_reg;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            wptr_reg  <= 0;
            rptr_reg  <= 0;
            empty_reg <= 1'b1;
            full_reg  <= 1'b0;
        end else begin
            wptr_reg  <= wptr_next;
            rptr_reg  <= rptr_next;
            empty_reg <= empty_next;
            full_reg  <= full_next;
        end
    end

    logic [1:0] fifo_state;
    assign fifo_state = {we, re};

    localparam READ = 2'b01, WRITE = 2'b10, READ_WRITE = 2'b11;

    always_comb begin
        wptr_next  = wptr_reg;
        rptr_next  = rptr_reg;
        empty_next = empty_reg;
        full_next  = full_reg;

        case (fifo_state)
            READ: begin
                if (!empty_reg) begin
                    rptr_next = rptr_reg + 1;
                    full_next = 1'b0;
                    if (wptr_next == rptr_next)
                        empty_next = 1'b1;
                end
            end
            WRITE: begin
                if (!full_reg) begin
                    wptr_next  = wptr_reg + 1;
                    empty_next = 1'b0;
                    if (wptr_next == rptr_next)
                        full_next = 1'b1;
                end
            end
            READ_WRITE: begin
                if (full_reg) begin
                    rptr_next = rptr_reg + 1;
                    full_next = 1'b0;
                end else if (empty_reg) begin
                    wptr_next  = wptr_reg + 1;
                    empty_next = 1'b0;
                end else begin
                    rptr_next = rptr_reg + 1;
                    wptr_next = wptr_reg + 1;
                end
            end
        endcase
    end
endmodule

////////////////////////////////////////////////////////////////////////////////////////
module APB_SlaveIntf_UART (
    // global signal
    input  logic        PCLK,
    input  logic        PRESET,
    // APB Interface Signals
    input  logic [ 3:0] PADDR,
    input  logic [31:0] PWDATA,
    input  logic        PWRITE,
    input  logic        PENABLE,
    input  logic        PSEL,
    output logic [31:0] PRDATA,
    output logic        PREADY,
    // internal signals
    input  logic [ 3:0] USR,
    output logic [ 7:0] UWD,
    input  logic [ 7:0] URD,
    output logic        we_TX,
    output logic        re_RX
);

    // 슬레이브 내부 레지스터 (상태/디버그용)
    logic [31:0] slv_reg0, slv_reg1, slv_reg2, slv_reg3;
    logic [31:0] slv_reg1_next, slv_reg2_next;

    // 제어 펄스 레지스터
    logic we_reg, we_next;
    logic re_reg, re_next;

    // APB 응답 레지스터
    logic [31:0] PRDATA_reg, PRDATA_next;
    logic        PREADY_reg, PREADY_next;

    // 출력 연결
    assign we_TX  = we_reg;
    assign re_RX  = re_reg;
    assign PRDATA = PRDATA_reg;
    assign PREADY = PREADY_reg;

    // TX 데이터 패스쓰루:
    //  - TDR 주소(2)로 쓰기 싸이클일 때는 PWDATA[7:0]를 직접 UWD로
    //  - 그 외에는 slv_reg2[7:0] (쉐도우) 값
    assign UWD = (PSEL && PENABLE && PWRITE && (PADDR[3:2] == 2))
               ? PWDATA[7:0]
               : slv_reg2[7:0];

    typedef enum logic [1:0] {IDLE=2'd0, READ=2'd1, WRITE=2'd2} state_e;
    state_e state_reg, state_next;

    // 시퀀셜: 동기화 캡처 (혼합 할당 금지)
    always_ff @(posedge PCLK or posedge PRESET) begin
        if (PRESET) begin
            slv_reg0     <= 32'd0;
            slv_reg1     <= 32'd0;
            slv_reg2     <= 32'd0;
            slv_reg3     <= 32'd0;
            state_reg    <= IDLE;
            we_reg       <= 1'b0;
            re_reg       <= 1'b0;
            PRDATA_reg   <= 32'd0;
            PREADY_reg   <= 1'b0;
        end else begin
            // USR/URD는 동기화해서 보관(가독/디버그용). 실제 READ 동작은 아래 always_comb에서 직접 URD 사용.
            slv_reg0[3:0] <= USR;
            slv_reg3[7:0] <= URD;

            slv_reg1   <= slv_reg1_next;
            slv_reg2   <= slv_reg2_next;
            state_reg  <= state_next;
            we_reg     <= we_next;
            re_reg     <= re_next;
            PRDATA_reg <= PRDATA_next;
            PREADY_reg <= PREADY_next;
        end
    end

    // 콤비네이셔널: APB 트랜잭션 처리
    always_comb begin
        // 기본값
        state_next    = IDLE;
        slv_reg1_next = slv_reg1;
        slv_reg2_next = slv_reg2;
        we_next       = 1'b0;
        re_next       = 1'b0;
        PRDATA_next   = PRDATA_reg;
        PREADY_next   = 1'b0;

        // APB 유효 싸이클에만 동작
        if (PSEL && PENABLE) begin
            if (PWRITE) begin
                // WRITE 사이클
                state_next  = WRITE;
                unique case (PADDR[3:2])
                    2'd1: slv_reg1_next = PWDATA;    // 옵션(사용 시)
                    2'd2: slv_reg2_next = PWDATA;    // TDR 쉐도우
                    default: /*do nothing*/;
                endcase
                we_next     = (PADDR[3:2] == 2'd2);  // TDR에 쓸 때만 TX FIFO push
                PREADY_next = 1'b1;
            end else begin
                // READ 사이클
                state_next  = READ;
                unique case (PADDR[3:2])
                    2'd0: begin
                        // USR
                        PRDATA_next = slv_reg0;
                        re_next     = 1'b0;
                    end
                    2'd1: begin
                        // (옵션) 상태/설정 레지스터
                        PRDATA_next = slv_reg1;
                        re_next     = 1'b0;
                    end
                    2'd2: begin
                        // (옵션) TDR 쉐도우
                        PRDATA_next = slv_reg2;
                        re_next     = 1'b0;
                    end
                    2'd3: begin
                        // ★ 핵심: RDR 읽기 시, 그 싸이클에 바로 URD를 반환 + pop
                        PRDATA_next = {24'b0, URD};
                        re_next     = 1'b1;          // RX FIFO pop (1사이클 펄스)
                    end
                    default: begin
                        PRDATA_next = 32'd0;
                        re_next     = 1'b0;
                    end
                endcase
                PREADY_next = 1'b1;
            end
        end
    end

endmodule

////////////////////////////////////////////////////////////////////////////////////////

module baud_tick_gen (
    input  logic clk,
    input  logic rst,
    output logic baud_tick
);
    parameter int BAUD_RATE = 9600;
    localparam int BAUD_COUNT = 100_000_000 / (BAUD_RATE * 16);

    logic [$clog2(BAUD_COUNT)-1:0] count_reg, count_next;
    logic tick_reg, tick_next;

    assign baud_tick = tick_reg;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tick_reg  <= 0;
            count_reg <= 0;
        end else begin
            tick_reg  <= tick_next;
            count_reg <= count_next;
        end
    end

    always_comb begin
        tick_next  = 1'b0;
        count_next = count_reg;
        if (count_reg == BAUD_COUNT - 1) begin
            tick_next  = 1'b1;
            count_next = 0;
        end else begin
            tick_next  = 1'b0;
            count_next = count_reg + 1;
        end
    end
endmodule
