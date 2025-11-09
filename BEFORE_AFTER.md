# 개선 전후 비교

## 1. Counter Tick 생성

### ❌ 개선 전 (문제)

```systemverilog
// spi_upcounter_dp.sv
always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
        counter <= 14'd0;
        counter_tick <= 1'b0;
    end else if (i_o_runstop) begin
        counter <= counter + 1;
        counter_tick <= 1'b1;  // ❌ 매 클럭마다 tick!
    end else begin
        counter_tick <= 1'b0;
    end
end
```

**문제점:**
- 카운터가 증가할 때마다 tick 발생 (100MHz = 10ns마다!)
- SPI 전송이 완료되기도 전에 다음 전송 시작
- 타이밍 충돌 발생

### ✅ 개선 후 (해결)

```systemverilog
// 1. spi_upcounter_dp.sv - tick 생성 제거
always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
        counter <= 14'd0;
    end else if (i_o_runstop) begin
        counter <= counter + 1;  // ✅ 카운터만 증가
    end
end

// 2. tick_gen.sv - 별도 모듈로 주기적 tick 생성
module tick_gen #(
    parameter TICK_PERIOD_MS = 100
) (
    input  logic clk,
    input  logic reset,
    output logic tick
);
    // 100ms마다 1 clock 동안 tick = 1
    // ✅ 주기적이고 예측 가능한 tick!
```

**개선 효과:**
- 100ms마다 한 번만 SPI 전송
- SPI 전송 완료 대기 가능
- 타이밍 안정성 확보

---

## 2. FSM 설계

### ❌ 개선 전 (문제)

```systemverilog
typedef enum {
    IDLE,
    WAIT_HI,
    WAIT_LW
} state_t;

always_comb begin
    case (state)
        IDLE: begin
            if (counter_tick) begin
                send_transaction = 1'b1;
                tx_data_next = tx_data;  // ❌ tx_data가 정의 안 됨!
                state_next = WAIT_HI;
            end
        end
        WAIT_HI: begin
            if (send_transaction) begin  // ❌ start 신호가 없음
                tx_data_next = tx_high_byte;
                hi_done = 1'b1;
                state = WAIT_LW;
            end
        end
        WAIT_LW: begin
            if (hi_done) begin  // ❌ done 신호 무시
                tx_data_next = tx_low_byte;
                lw_done = 1'b1;
                state = IDLE;
            end
        end
    endcase
end
```

**문제점:**
- start 신호를 spi_master에 보내지 않음
- spi_done 신호를 확인하지 않음
- 전송이 완료되기 전에 다음 상태로 이동
- hi_done이 combinational인데 sequential처럼 사용

### ✅ 개선 후 (해결)

```systemverilog
typedef enum {
    IDLE,
    SEND_HIGH,  // ✅ start 신호 보내는 상태 추가
    WAIT_HIGH,  // ✅ done 대기
    SEND_LOW,   // ✅ start 신호 보내는 상태 추가
    WAIT_LOW    // ✅ done 대기
} state_t;

always_comb begin
    state_next = state;
    tx_data_next = tx_data_reg;
    spi_start = 1'b0;  // ✅ spi_master에 보낼 start 신호

    case (state)
        IDLE: begin
            if (counter_tick) begin
                tx_data_next = tx_high_byte;  // ✅ 명확한 데이터
                state_next = SEND_HIGH;
            end
        end

        SEND_HIGH: begin
            spi_start = 1'b1;  // ✅ SPI 전송 시작 신호
            state_next = WAIT_HIGH;
        end

        WAIT_HIGH: begin
            if (spi_done) begin  // ✅ 전송 완료 대기
                tx_data_next = tx_low_byte;
                state_next = SEND_LOW;
            end
        end

        SEND_LOW: begin
            spi_start = 1'b1;  // ✅ SPI 전송 시작 신호
            state_next = WAIT_LOW;
        end

        WAIT_LOW: begin
            if (spi_done) begin  // ✅ 전송 완료 대기
                state_next = IDLE;
            end
        end
    endcase
end
```

**개선 효과:**
- SEND/WAIT 상태 분리로 명확한 제어
- spi_done 신호로 전송 완료 확인
- 안정적인 2바이트 전송

---

## 3. 신호 연결

### ❌ 개선 전 (문제)

```systemverilog
module master_top (
    input logic clk,
    input logic reset,
    input logic i_runstop,
    input logic i_clear
    // ❌ SPI 신호가 외부로 나가지 않음!
);

spi_master U_SPI_MASTER (
    .clk(clk),
    .reset(reset),
    .start(),      // ❌ 연결 안 됨
    .tx_data(tx_data),  // ❌ tx_data 정의 안 됨
    .rx_data(),
    .tx_ready(),
    .done(),       // ❌ 연결 안 됨
    .sclk(),       // ❌ 외부 포트 없음
    .mosi(),
    .miso()
);
```

**문제점:**
- SPI 신호(sclk, mosi, ss)가 외부 포트로 나가지 않음
- start, done 신호가 연결되지 않음
- tx_data가 정의되지 않음

### ✅ 개선 후 (해결)

```systemverilog
module master_top (
    input  logic clk,
    input  logic reset,
    input  logic i_runstop,
    input  logic i_clear,
    // ✅ SPI 신호 추가
    output logic sclk,
    output logic mosi,
    input  logic miso,
    output logic ss,
    // ✅ 디버그 출력
    output logic [13:0] o_counter
);

    // ✅ 내부 신호 정의
    logic        spi_start;
    logic [7:0]  spi_tx_data;
    logic        spi_done;
    logic        counter_tick;

    // ✅ Tick generator 연결
    tick_gen #(.TICK_PERIOD_MS(100)) U_TICK_GEN (
        .clk(clk),
        .reset(reset),
        .tick(counter_tick)
    );

    // ✅ SPI master 연결
    spi_master U_SPI_MASTER (
        .clk(clk),
        .reset(reset),
        .start(spi_start),      // ✅ FSM에서 제어
        .tx_data(spi_tx_data),  // ✅ FSM에서 제공
        .done(spi_done),        // ✅ FSM에서 확인
        .sclk(sclk),            // ✅ 외부 포트 연결
        .mosi(mosi),
        .miso(miso)
    );

    assign spi_tx_data = tx_data_reg;  // ✅ FSM에서 관리
    assign o_counter = w_counter;      // ✅ 디버그 출력
```

**개선 효과:**
- 모든 신호 명확하게 연결
- 외부에서 SPI 신호 사용 가능
- 디버그 용이

---

## 4. 모듈 구조

### ❌ 개선 전

```
master_top
├── spi_master (연결 불완전)
├── spi_upcounter_cu
└── spi_upcounter_dp (tick 생성 - 문제!)
```

### ✅ 개선 후

```
master_top
├── tick_gen (새로 추가 - 100ms tick)
├── spi_master (완전히 연결)
├── spi_upcounter_cu
├── spi_upcounter_dp (tick 생성 제거)
└── FSM (2바이트 전송 제어)
```

---

## 5. 타이밍 비교

### ❌ 개선 전

```
Counter: 0→1→2→3→4→5→6→7→8→9...
Tick:    ↑ ↑ ↑ ↑ ↑ ↑ ↑ ↑ ↑ ↑  (매 클럭!)
SPI:     [H][L][H][L][H][L][H][L]...  (충돌!)
         └─┘ └─┘ └─┘ └─┘
          전송 안 끝났는데 다음 시작!
```

### ✅ 개선 후

```
Counter: 0→1→2→3→...→N→N+1→...→M→M+1
Tick:    ↑                 ↑           (100ms마다)
         |                 |
SPI:     [H][L]            [H][L]      (안전!)
         └─완료─┘          └─완료─┘
```

---

## 6. 코드 라인 수 비교

| 항목 | 개선 전 | 개선 후 | 비고 |
|------|---------|---------|------|
| tick 생성 | spi_upcounter_dp 내부 | tick_gen.sv (별도) | 관심사 분리 |
| FSM 상태 | 3개 | 5개 | 명확한 제어 |
| 신호 연결 | 불완전 | 완전 | 모든 신호 연결 |
| 외부 포트 | 4개 | 8개 | SPI 신호 추가 |

---

## 7. 시뮬레이션 차이

### ❌ 개선 전 - 예상 결과

```
[1000ns] Counter: 1, Tick!
[1010ns] SPI Start - High byte
[1020ns] Counter: 2, Tick!  ← 이전 전송 중인데 또 시작!
[1030ns] ERROR: Timing violation
```

### ✅ 개선 후 - 예상 결과

```
[1,000,000ns] Counter: 100, Tick!
[1,000,010ns] FSM: IDLE → SEND_HIGH
[1,000,020ns] FSM: SEND_HIGH → WAIT_HIGH
[1,010,000ns] SPI High byte done
[1,010,010ns] FSM: WAIT_HIGH → SEND_LOW
[1,020,000ns] SPI Low byte done
[1,020,010ns] FSM: WAIT_LOW → IDLE
[2,000,000ns] Counter: 200, Tick!  ← 안전한 간격!
```

---

## 요약

| 구분 | 개선 전 | 개선 후 |
|------|---------|---------|
| **Tick 생성** | 매 클럭 | 100ms마다 |
| **타이밍** | 충돌 발생 | 안전 |
| **FSM** | 불완전 (3상태) | 완전 (5상태) |
| **신호 연결** | 불완전 | 완전 |
| **디버깅** | 어려움 | 쉬움 |
| **시뮬레이션** | 오류 | 정상 동작 |
| **실제 HW** | 동작 불가 | 동작 가능 |

## 핵심 개선 포인트

1. ✅ **Tick 생성 분리** - 타이밍 안정성
2. ✅ **FSM 재설계** - 명확한 제어 흐름
3. ✅ **신호 완전 연결** - 실제 동작 가능
4. ✅ **디버그 출력 추가** - 개발/테스트 용이
5. ✅ **시뮬레이션 지원** - fast/normal 버전 제공
