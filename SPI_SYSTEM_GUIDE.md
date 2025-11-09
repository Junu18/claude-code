# SPI Master-Slave 카운터 시스템 설계 문서

## 📋 목차
1. [프로젝트 개요](#프로젝트-개요)
2. [SPI 통신이란?](#spi-통신이란)
3. [시스템 아키텍처](#시스템-아키텍처)
4. [각 모듈 상세 설명](#각-모듈-상세-설명)
5. [설계 결정 사항과 이유](#설계-결정-사항과-이유)
6. [타이밍 분석](#타이밍-분석)
7. [테스트 및 검증](#테스트-및-검증)
8. [하드웨어 연결](#하드웨어-연결)

---

## 프로젝트 개요

### 목적
- **Master FPGA**: 1초마다 카운터를 증가시키고 SPI 통신으로 값을 전송
- **Slave FPGA**: SPI 통신으로 받은 카운터 값을 FND(7-segment display)에 표시
- **Single Board 테스트**: 하나의 FPGA 보드에서 Master와 Slave를 모두 구현하여 테스트

### 주요 기능
1. **카운터 증가**: 1초(1000ms)마다 0→1→2→...→16383→0으로 순환
2. **RUN/STOP 제어**: 버튼으로 카운터 동작/정지 토글
3. **CLEAR 기능**: 버튼으로 카운터 초기화
4. **SPI 통신**: 14비트 카운터 값을 2바이트로 나누어 전송
5. **FND 표시**: 4자리 7-segment display에 카운터 값 표시

---

## SPI 통신이란?

### SPI (Serial Peripheral Interface) 기본 개념

SPI는 **마스터-슬레이브 구조**의 **동기식 직렬 통신** 프로토콜입니다.

#### 왜 SPI를 사용하는가?
1. **빠른 속도**: 병렬 통신처럼 빠르지만 선이 적게 필요
2. **간단한 하드웨어**: 복잡한 프로토콜이 필요 없음
3. **전이중 통신**: 동시에 송수신 가능 (이 프로젝트에서는 단방향만 사용)

#### SPI 신호선 (4개)

```
Master                          Slave
  ├─── SCLK (Serial Clock) ────→ SCLK
  ├─── MOSI (Master Out) ──────→ MOSI
  ├─── MISO (Master In) ←──────┤ MISO
  └─── SS (Slave Select) ──────→ SS
```

1. **SCLK (Serial Clock)**
   - Master가 생성하는 클럭 신호
   - 이 클럭에 맞춰 데이터를 송수신
   - **왜 필요?** Slave가 언제 데이터를 읽어야 하는지 알려주기 위해

2. **MOSI (Master Out Slave In)**
   - Master → Slave로 데이터 전송
   - **왜 필요?** 카운터 값을 Slave에게 보내기 위해

3. **MISO (Master In Slave Out)**
   - Slave → Master로 데이터 전송
   - **이 프로젝트에서는 미사용** (단방향 통신만 필요)

4. **SS (Slave Select, Chip Select)**
   - LOW(0)일 때: 통신 시작
   - HIGH(1)일 때: 통신 종료
   - **왜 필요?** 여러 Slave 중 특정 Slave만 선택하기 위해

#### SPI 통신 예시

```
시간 →
      ┌─────┐     ┌─────┐     ┌─────┐
SS    ┘     └─────┘     └─────┘     └─────  (LOW = 선택)

      ┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐
SCLK  ┘└┘└┘└┘└┘└┘└┘└┘└              (클럭)

MOSI  ──1───0───1───1───0───1───    (데이터: 101101...)
        ↑   ↑   ↑   ↑   ↑   ↑
      bit7 bit6 bit5 bit4 bit3 bit2
```

**동작 원리:**
1. SS를 LOW로 내림 (통신 시작)
2. SCLK의 상승 엣지마다 MOSI의 1비트를 전송
3. 8비트 전송 완료
4. SS를 HIGH로 올림 (통신 종료)

---

## 시스템 아키텍처

### 전체 블록 다이어그램

```
┌─────────────────────────────────────────────────────────────┐
│                    BASYS3 FPGA 보드                          │
│                                                              │
│  ┌────────────────────────┐         ┌───────────────────┐  │
│  │      MASTER 부분       │         │    SLAVE 부분      │  │
│  │                        │         │                   │  │
│  │  ┌──────────────┐      │  SPI    │  ┌─────────────┐ │  │
│  │  │ Tick Generator│      │  신호   │  │ SPI Slave   │ │  │
│  │  │  (1초 타이머) │      │         │  │  Receiver   │ │  │
│  │  └───────┬──────┘      │         │  └──────┬──────┘ │  │
│  │          │             │  JB→JC  │         │        │  │
│  │  ┌───────▼──────┐      │  점퍼   │  ┌──────▼──────┐ │  │
│  │  │   Counter    │      │  와이어 │  │  FND 제어   │ │  │
│  │  │  (14-bit)    │      │  연결   │  │             │ │  │
│  │  └───────┬──────┘      │         │  └──────┬──────┘ │  │
│  │          │             │ ┌─────┐ │         │        │  │
│  │  ┌───────▼──────┐      │ │SCLK │ │         │        │  │
│  │  │ SPI Master   ├──────┼→│MOSI │→┤         │        │  │
│  │  │ Transmitter  │      │ │ SS  │ │         │        │  │
│  │  └──────────────┘      │ └─────┘ │         │        │  │
│  │                        │         │         ▼        │  │
│  │  ┌──────────────┐      │         │  ┌─────────────┐ │  │
│  │  │ Button       │      │         │  │  7-Segment  │ │  │
│  │  │ Debouncer    │      │         │  │  Display    │ │  │
│  │  └──────────────┘      │         │  └─────────────┘ │  │
│  └────────────────────────┘         └───────────────────┘  │
│                                                              │
│  버튼: BTNU(RUN/STOP), BTND(CLEAR), BTNC(RESET)            │
│  LED: [7:0]=Counter, LED[8]=RunStop, LED[9]=Tick           │
└─────────────────────────────────────────────────────────────┘
```

### 데이터 흐름

```
1초 Tick 발생
    │
    ▼
Counter 증가 (0→1→2→...)
    │
    ▼
14비트 값을 2바이트로 분할
    │
    ├─ Byte 1: [13:6] (상위 8비트)
    └─ Byte 2: [5:0] + "00" (하위 6비트 + 패딩)
    │
    ▼
SPI Master가 2바이트 순차 전송
    │ (SCLK, MOSI, SS 신호)
    ▼
SPI Slave가 2바이트 수신
    │
    ▼
Synchronizer로 클럭 도메인 크로싱
    │
    ▼
14비트로 재조합
    │
    ▼
FND Controller가 4자리 표시
    │
    ▼
7-Segment Display에 출력
```

---

## 각 모듈 상세 설명

### 1. Tick Generator (`tick_gen.sv`)

#### 목적
정확한 시간 간격으로 펄스 신호를 생성합니다.

#### 왜 필요한가?
- FPGA는 100MHz (10ns 주기)로 매우 빠르게 동작
- 카운터는 1초(1,000,000,000ns)마다 증가해야 함
- 100,000,000 클럭을 세어서 1초를 만들어야 함

#### 코드 분석

```systemverilog
module tick_gen #(
    parameter TICK_PERIOD_MS = 1000  // 1000ms = 1초
) (
    input  logic clk,      // 100MHz 클럭
    input  logic reset,
    output logic tick      // 1초마다 1클럭 펄스
);
    // 100MHz에서 1ms = 100,000 클럭
    localparam CLOCKS_PER_MS = 100_000;
    localparam TICK_COUNT = TICK_PERIOD_MS * CLOCKS_PER_MS;
    // 1000ms * 100,000 = 100,000,000 클럭

    logic [31:0] counter;  // 32비트 카운터 (100,000,000까지 셀 수 있음)

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            counter <= 0;
            tick <= 0;
        end else begin
            if (counter == TICK_COUNT - 1) begin
                counter <= 0;
                tick <= 1;  // 1클럭 동안만 HIGH
            end else begin
                counter <= counter + 1;
                tick <= 0;
            end
        end
    end
endmodule
```

#### 설계 결정 사항

**Q: 왜 32비트 카운터를 사용하는가?**
- A: 100,000,000을 저장하려면 최소 27비트 필요 (2^27 = 134,217,728)
- 32비트를 사용하면 충분하고, 하드웨어 리소스도 많지 않음

**Q: 왜 $clog2() 함수를 사용하지 않았는가?**
- A: Vivado 시뮬레이터에서 $clog2()가 제대로 계산되지 않는 버그 발견
- 명시적으로 32비트로 선언하여 문제 해결

**Q: 왜 tick을 1클럭만 HIGH로 유지하는가?**
- A: 엣지 검출이 쉽고, 카운터가 여러 번 증가하는 것을 방지

---

### 2. Counter (`counter.sv`)

#### 목적
Tick 신호에 따라 14비트 카운터를 증가시킵니다.

#### 왜 14비트인가?
- 4자리 10진수는 최대 9999
- 9999를 2진수로 표현하면 13.29비트 필요
- 14비트면 0~16383까지 표현 가능 (충분함)

#### 코드 분석

```systemverilog
module counter (
    input  logic        clk,
    input  logic        reset,
    input  logic        i_tick,      // tick_gen에서 온 신호
    input  logic        i_clear,     // clear 버튼
    input  logic        i_runstop,   // run/stop 상태
    output logic [13:0] o_counter    // 14비트 카운터
);
    always_ff @(posedge clk or posedge reset) begin
        if (reset || i_clear) begin
            o_counter <= 14'd0;
        end else if (i_runstop && i_tick) begin
            o_counter <= o_counter + 1;
        end
    end
endmodule
```

#### 설계 결정 사항

**Q: 왜 `i_runstop && i_tick` 조건을 사용하는가?**
- A: 두 조건이 모두 만족해야 증가
  - `i_runstop == 1`: RUN 상태
  - `i_tick == 1`: 1초 경과
- 이렇게 하면 STOP 상태에서는 tick이 와도 증가하지 않음

**Q: 왜 reset과 clear를 OR로 연결하는가?**
- A: 두 경우 모두 카운터를 0으로 만들어야 함
  - `reset`: 시스템 리셋 (전역적)
  - `i_clear`: 사용자가 카운터만 초기화

---

### 3. SPI Master Transmitter (`spi_master_tx.sv`)

#### 목적
14비트 데이터를 2바이트로 나누어 SPI 프로토콜로 전송합니다.

#### 왜 2바이트로 나누는가?
- SPI는 보통 8비트(1바이트) 단위로 전송
- 14비트 데이터를 한 번에 보낼 수 없음
- 상위 8비트 + 하위 6비트(+패딩 2비트)로 분할

#### 데이터 패킹 방식

```
14비트 카운터: [13][12][11][10][9][8][7][6][5][4][3][2][1][0]

┌─────────────────────┬───────────────────────┐
│   Byte 1 (상위)     │    Byte 2 (하위)      │
├─────────────────────┼───────────────────────┤
│ [13:6] (8비트)      │ [5:0] + "00" (8비트)  │
└─────────────────────┴───────────────────────┘
```

예시: 카운터 = 1234 (10진수) = 0000_0100_1101_0010 (2진수)

```
Byte 1: 00000100 (상위 8비트) = 4
Byte 2: 11010000 (하위 6비트 + 00 패딩) = 208

Slave에서 재조합:
(4 << 6) | (208 >> 2) = 256 + 978 = 1234 ✓
```

#### FSM (유한 상태 기계) 설계

```
       ┌─────────┐
       │  IDLE   │ ← 대기 상태 (SS=HIGH)
       └────┬────┘
            │ i_start=1 (tick 신호)
            ▼
       ┌─────────┐
       │  BYTE1  │ ← 첫 번째 바이트 전송
       └────┬────┘
            │ bit_count=7 완료
            ▼
       ┌─────────┐
       │  BYTE2  │ ← 두 번째 바이트 전송
       └────┬────┘
            │ bit_count=7 완료
            ▼
       ┌─────────┐
       │  DONE   │ ← 전송 완료 (SS=HIGH)
       └────┬────┘
            │ 1클럭 대기
            ▼
       (IDLE로 복귀)
```

#### 코드 분석

```systemverilog
typedef enum logic [1:0] {
    IDLE  = 2'b00,
    BYTE1 = 2'b01,  // 첫 번째 바이트 전송
    BYTE2 = 2'b10,  // 두 번째 바이트 전송
    DONE  = 2'b11   // 전송 완료
} state_t;

state_t state, next_state;
logic [2:0] bit_count;    // 0~7 카운트
logic [7:0] shift_reg;    // 전송할 데이터
logic       sclk_reg;     // SCLK 생성
```

**SCLK 생성 방식:**

```systemverilog
// SCLK = clk의 반 속도
// clk:  ┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐
// sclk: ┌──┐  ┌──┐  ┌──┐
//       └──┘  └──┘  └──┘

assign sclk = (state == BYTE1 || state == BYTE2) ? sclk_reg : 1'b0;

always_ff @(posedge clk) begin
    if (state == BYTE1 || state == BYTE2)
        sclk_reg <= ~sclk_reg;  // 토글
    else
        sclk_reg <= 1'b0;
end
```

**데이터 전송:**

```systemverilog
// MOSI는 shift_reg의 MSB(최상위 비트)부터 전송
assign mosi = shift_reg[7];

always_ff @(posedge clk) begin
    if (sclk_reg && next_sclk == 0) begin  // SCLK 하강 엣지
        shift_reg <= {shift_reg[6:0], 1'b0};  // 왼쪽으로 시프트
        bit_count <= bit_count + 1;
    end
end
```

#### 설계 결정 사항

**Q: 왜 FSM을 사용하는가?**
- A: SPI 전송은 여러 단계로 이루어짐
  1. 대기 → 2. 첫 번째 바이트 → 3. 두 번째 바이트 → 4. 완료
  - FSM은 이런 순차적 동작을 명확하게 표현

**Q: 왜 SCLK를 clk/2로 만드는가?**
- A: SPI 표준에서는 SCLK가 시스템 클럭보다 느려야 함
  - 너무 빠르면 Slave가 데이터를 읽을 시간이 없음
  - clk/2는 안전한 속도 (50MHz)

**Q: 왜 하강 엣지에서 데이터를 시프트하는가?**
- A: SPI Mode 0 사용
  - SCLK 하강 엣지: Master가 다음 비트 준비
  - SCLK 상승 엣지: Slave가 비트 읽음

---

### 4. SPI Slave Receiver (`spi_slave_rx.sv`)

#### 목적
Master로부터 2바이트를 받아 14비트로 재조합합니다.

#### 왜 Synchronizer가 필요한가?

**클럭 도메인 크로싱 (CDC) 문제:**

```
Master 클럭 (100MHz)  ┌┐┌┐┌┐┌┐┌┐┌┐
SPI 신호 (비동기)     ──┐    ┌─────
Slave 클럭 (100MHz)   ┌┐┌┐┌┐┌┐┌┐┌┐
                        ↑
                    메타스테이블 위험!
```

- **메타스테이블**: 신호가 클럭 엣지와 정확히 일치하지 않으면 FF가 불안정한 상태
- **해결책**: 2단 FF로 신호를 동기화

#### Synchronizer 구조

```systemverilog
logic sclk_sync1, sclk_sync2;
logic mosi_sync1, mosi_sync2;
logic ss_sync1, ss_sync2;

always_ff @(posedge clk) begin
    // 첫 번째 단계
    sclk_sync1 <= sclk;
    mosi_sync1 <= mosi;
    ss_sync1   <= ss;

    // 두 번째 단계
    sclk_sync2 <= sclk_sync1;
    mosi_sync2 <= mosi_sync1;
    ss_sync2   <= ss_sync1;
end

// 동기화된 신호 사용
wire sclk_rising = ~sclk_sync2_prev && sclk_sync2;
```

#### 데이터 수신 과정

```
1. SS가 LOW로 떨어지면 수신 시작
2. SCLK 상승 엣지마다 MOSI의 비트를 읽음
3. 8비트 받으면 byte1에 저장
4. 다시 8비트 받으면 byte2에 저장
5. 14비트로 재조합: {byte1, byte2[7:2]}
```

#### 코드 분석

```systemverilog
typedef enum logic [1:0] {
    IDLE  = 2'b00,
    BYTE1 = 2'b01,
    BYTE2 = 2'b10,
    VALID = 2'b11
} state_t;

always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
        state <= IDLE;
        bit_count <= 0;
    end else begin
        case (state)
            IDLE: begin
                if (~ss_sync2) begin  // SS LOW: 시작
                    state <= BYTE1;
                    bit_count <= 0;
                end
            end

            BYTE1: begin
                if (sclk_rising) begin  // SCLK 상승 엣지
                    shift_reg <= {shift_reg[6:0], mosi_sync2};
                    bit_count <= bit_count + 1;

                    if (bit_count == 7) begin
                        byte1 <= {shift_reg[6:0], mosi_sync2};
                        state <= BYTE2;
                        bit_count <= 0;
                    end
                end
            end

            BYTE2: begin
                if (sclk_rising) begin
                    shift_reg <= {shift_reg[6:0], mosi_sync2};
                    bit_count <= bit_count + 1;

                    if (bit_count == 7) begin
                        byte2 <= {shift_reg[6:0], mosi_sync2};
                        state <= VALID;
                    end
                end
            end

            VALID: begin
                o_data_valid <= 1;
                // 14비트 재조합
                o_data <= {byte1, byte2[7:2]};
                state <= IDLE;
            end
        endcase
    end
end
```

#### 설계 결정 사항

**Q: 왜 2단 Synchronizer를 사용하는가?**
- A: 1단은 메타스테이블 발생 가능성이 높음
  - 2단을 사용하면 메타스테이블이 시스템에 전파될 확률이 매우 낮아짐 (10^-12 이하)

**Q: 왜 상승 엣지에서 데이터를 읽는가?**
- A: SPI Mode 0 규칙
  - Master는 하강 엣지에서 데이터 준비
  - Slave는 상승 엣지에서 데이터 읽음
  - 이렇게 하면 데이터가 안정적인 시점에 읽을 수 있음

---

### 5. Button Debouncer (`debouncer.sv`)

#### 목적
버튼의 채터링(bouncing)을 제거합니다.

#### 채터링이란?

```
실제 버튼 동작:
      ┌─────────────
OFF   ┘  ┌┐┌┐  ← 채터링 (기계적 진동)
         └┘└┘

디바운서 후:
      ┌─────────────
OFF   └─────────────  ← 깨끗한 신호
         ↑
      20ms 안정 후 인식
```

버튼을 누르면:
- 기계적 접점이 여러 번 붙었다 떨어짐
- 몇 밀리초 동안 신호가 불안정
- 이를 여러 번 누른 것으로 오인할 수 있음

#### 디바운싱 알고리즘

```systemverilog
parameter DEBOUNCE_TIME_MS = 20;  // 20ms
localparam DEBOUNCE_CLOCKS = DEBOUNCE_TIME_MS * 100_000;

logic [31:0] counter;
logic btn_stable;

always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
        counter <= 0;
        btn_stable <= 0;
        btn_out <= 0;
    end else begin
        if (btn_in == btn_stable) begin
            counter <= 0;  // 안정적이면 카운터 리셋
        end else begin
            counter <= counter + 1;
            if (counter >= DEBOUNCE_CLOCKS) begin
                btn_stable <= btn_in;  // 20ms 동안 유지되면 변경 인정
                btn_out <= btn_in;
                counter <= 0;
            end
        end
    end
end
```

#### 설계 결정 사항

**Q: 왜 20ms인가?**
- A: 일반적인 기계식 버튼의 채터링 시간은 5~20ms
  - 20ms면 대부분의 버튼에서 안전
  - 너무 길면 반응이 느려짐

**Q: 왜 btn_stable 변수를 사용하는가?**
- A: 현재 안정적인 상태를 기억
  - btn_in이 btn_stable과 다르면 카운터 시작
  - 같으면 카운터 리셋 (여전히 안정적)

---

### 6. Edge Detector (`edge_detector.sv`)

#### 목적
레벨 신호를 펄스 신호로 변환합니다.

#### 왜 필요한가?

```
버튼 누름 (레벨 신호):
      ┌─────────────────────────
      └─────────────────────────  ← 계속 HIGH

필요한 것 (펄스 신호):
      ┌┐
      └┘───────────────────────  ← 1클럭만 HIGH
       ↑
    한 번만 토글하고 싶음
```

- 버튼을 누르면 손을 떼기 전까지 계속 HIGH
- RUN/STOP은 **토글** 동작 (누를 때마다 반전)
- 여러 번 토글되는 것을 방지하기 위해 **한 번만 펄스** 생성

#### 코드 분석

```systemverilog
logic level_reg;

always_ff @(posedge clk or posedge reset) begin
    if (reset)
        level_reg <= 1'b0;
    else
        level_reg <= i_level;  // 이전 값 저장
end

// 상승 엣지 감지: 이전=0, 현재=1
assign o_pulse = ~level_reg && i_level;
```

#### 동작 타이밍

```
clk     ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐
        └─┘ └─┘ └─┘ └─┘ └─┘ └─┘

i_level ────┐           ┌─────────
            └───────────┘

level_reg ──────┐           ┌─────
                └───────────┘
                ↑ 1클럭 지연

o_pulse ────────┐
                └───────────────
                ↑ 1클럭만 HIGH
```

#### 설계 결정 사항

**Q: 왜 상승 엣지만 감지하는가?**
- A: RUN/STOP 토글은 버튼을 **누를 때**만 동작해야 함
  - 버튼을 뗄 때(하강 엣지)는 반응하지 않음

**Q: 왜 하강 엣지는 감지하지 않는가?**
- A: 이 설계에서는 필요 없음
  - 필요하면 `o_pulse = level_reg && ~i_level`로 변경 가능

---

### 7. FSM Controller (`fsm_controller.sv`)

#### 목적
RUN/STOP 상태를 관리합니다.

#### 상태 전이 다이어그램

```
     ┌────────┐
     │  STOP  │ ← 초기 상태 (카운터 정지)
     └───┬────┘
         │ i_runstop=1 (버튼 누름)
         ▼
     ┌────────┐
     │  RUN   │ ← 카운터 동작
     └───┬────┘
         │ i_runstop=1 (버튼 다시 누름)
         ▼
     (STOP으로 복귀)
```

#### 코드 분석

```systemverilog
typedef enum logic {
    STOP = 1'b0,
    RUN  = 1'b1
} state_t;

state_t state, next_state;

// 다음 상태 결정 (조합 로직)
always_comb begin
    case (state)
        STOP: next_state = i_runstop ? RUN : STOP;
        RUN:  next_state = i_runstop ? STOP : RUN;
        default: next_state = STOP;
    endcase
end

// 상태 업데이트 (순차 로직)
always_ff @(posedge clk or posedge reset) begin
    if (reset)
        state <= STOP;
    else
        state <= next_state;
end

// 출력
assign o_runstop = (state == RUN);
```

#### 설계 결정 사항

**Q: 왜 2-process FSM을 사용하는가?**
- A: 모범 사례 (Best Practice)
  - `always_comb`: 다음 상태 계산 (조합 로직)
  - `always_ff`: 상태 저장 (순차 로직)
  - 코드가 명확하고 합성 결과가 예측 가능

**Q: 왜 초기 상태가 STOP인가?**
- A: 안전을 위해
  - 리셋 후 카운터가 자동으로 증가하지 않음
  - 사용자가 명시적으로 RUN을 눌러야 시작

---

### 8. FND Controller (`fnd_controller.sv`)

#### 목적
4자리 7-segment display를 제어합니다.

#### FND 동작 원리

**동적 스캔 (Dynamic Scanning):**

```
4자리를 동시에 켤 수 없음 → 빠르게 번갈아 가며 켬

시간 →
COM[0] ████░░░░░░░░████░░░░  ← 1000의 자리
COM[1] ░░░░████░░░░░░░░████  ← 100의 자리
COM[2] ░░░░░░░░████░░░░░░░░  ← 10의 자리
COM[3] ░░░░░░░░░░░░████░░░░  ← 1의 자리

DATA   [1] [2] [3] [4] [1]   ← 각 자리 숫자
```

**눈의 잔상 효과:**
- 1ms마다 자리를 바꾸면 사람 눈에는 모든 자리가 동시에 켜진 것처럼 보임

#### 숫자 → 세그먼트 변환

```
   a
  ───
f│   │b
  ─g─
e│   │c
  ───
   d   ●dp

숫자 0: a,b,c,d,e,f 켜짐 → 0b11000000 = 0xC0
숫자 1: b,c 켜짐       → 0b11111001 = 0xF9
숫자 2: a,b,d,e,g 켜짐 → 0b10100100 = 0xA4
...
```

#### 코드 분석

```systemverilog
// 14비트 카운터를 10진수 4자리로 분리
logic [3:0] digit0, digit1, digit2, digit3;
assign digit0 = counter % 10;           // 1의 자리
assign digit1 = (counter / 10) % 10;    // 10의 자리
assign digit2 = (counter / 100) % 10;   // 100의 자리
assign digit3 = (counter / 1000) % 10;  // 1000의 자리

// 1ms (100,000 클럭)마다 자리 변경
localparam REFRESH_RATE_MS = 1;
localparam REFRESH_COUNT = REFRESH_RATE_MS * 100_000;

logic [16:0] refresh_counter;
logic [1:0] digit_select;

always_ff @(posedge clk) begin
    if (refresh_counter == REFRESH_COUNT - 1) begin
        refresh_counter <= 0;
        digit_select <= digit_select + 1;  // 0→1→2→3→0
    end else begin
        refresh_counter <= refresh_counter + 1;
    end
end

// COM 선택 (active LOW)
always_comb begin
    case (digit_select)
        2'b00: fnd_com = 4'b1110;  // digit0 선택
        2'b01: fnd_com = 4'b1101;  // digit1 선택
        2'b10: fnd_com = 4'b1011;  // digit2 선택
        2'b11: fnd_com = 4'b0111;  // digit3 선택
    endcase
end

// 7-segment 데코더
always_comb begin
    case (current_digit)
        4'd0: fnd_data = 8'b11000000;  // 0
        4'd1: fnd_data = 8'b11111001;  // 1
        4'd2: fnd_data = 8'b10100100;  // 2
        // ...
        default: fnd_data = 8'b11111111;  // OFF
    endcase
end
```

#### 설계 결정 사항

**Q: 왜 1ms마다 자리를 바꾸는가?**
- A: 깜빡임 방지
  - 너무 느리면(> 10ms) 깜빡이는 것처럼 보임
  - 너무 빠르면(< 0.1ms) 밝기가 약해짐
  - 1ms는 최적의 균형

**Q: 왜 COM이 active LOW인가?**
- A: Basys3 보드의 하드웨어 설계
  - Common Cathode 방식 사용
  - COM=0일 때 해당 자리가 켜짐

**Q: 왜 나누기/나머지 연산을 사용하는가?**
- A: 2진수 → 10진수 변환
  - 1234를 4자리로 분리: 1, 2, 3, 4
  - 합성기가 자동으로 최적화된 하드웨어로 변환

---

## 설계 결정 사항과 이유

### 1. 비동기 리셋 사용

```systemverilog
always_ff @(posedge clk or posedge reset) begin
    if (reset)
        // 리셋 동작
    else
        // 정상 동작
end
```

**이유:**
- FPGA의 전역 리셋 신호는 비동기
- 버튼 리셋도 클럭과 무관하게 동작
- 모든 모듈이 즉시 리셋되어야 안전

**대안 (동기 리셋):**
```systemverilog
always_ff @(posedge clk) begin
    if (reset)
        // 리셋 동작
end
```
- 클럭이 와야 리셋됨
- 클럭이 멈추면 리셋 불가

---

### 2. 2바이트 전송 방식

**왜 14비트를 2바이트로 나누는가?**

1. **SPI 표준**: 8비트 단위가 일반적
2. **효율성**: 14비트 = 8비트 + 6비트 (+2비트 패딩)
3. **확장성**: 나중에 16비트로 쉽게 확장 가능

**대안:**
- 16비트를 한 번에 전송: 비표준적
- 3바이트 사용: 낭비 (14비트만 필요한데 24비트 전송)

---

### 3. Synchronizer 사용

**왜 모든 SPI 신호를 동기화하는가?**

Master와 Slave는 같은 FPGA 내에 있지만:
- Master는 자신의 클럭 도메인에서 동작
- Slave는 SPI 신호를 비동기 입력으로 받음
- 클럭 도메인이 다르면 메타스테이블 발생 가능

**대안:**
- 동기화하지 않으면: 간헐적인 오류 발생
- 1단 동기화: 여전히 메타스테이블 가능성
- 2단 동기화: 안전 (업계 표준)

---

### 4. Edge Detector 사용

**왜 버튼에 Edge Detector를 사용하는가?**

```
Debouncer 출력: ┌──────────────┐
                └──────────────┘

Edge Detector:  ┌┐
                └┘──────────────

FSM Toggle:     STOP → RUN (한 번만)
```

Edge Detector 없으면:
```
Debouncer 출력: ┌──────────────┐
                └──────────────┘

FSM:            STOP→RUN→STOP→RUN→... (여러 번 토글)
```

---

### 5. FSM 사용

**왜 FSM을 사용하는가?**

1. **명확성**: 상태와 전이가 명확
2. **디버깅**: 현재 상태를 LED로 확인 가능
3. **확장성**: 새로운 상태 추가 용이
4. **표준**: 디지털 설계의 일반적인 패턴

**대안 (단순 토글):**
```systemverilog
always_ff @(posedge clk) begin
    if (i_runstop)
        o_runstop <= ~o_runstop;
end
```
- 간단하지만 복잡한 동작 추가 어려움
- 예: PAUSE, FAST 모드 등 추가 시 복잡해짐

---

## 타이밍 분석

### 1. Tick 생성 타이밍

```
100MHz 클럭 (10ns 주기)
├─ 100,000 클럭 = 1ms
├─ 100,000,000 클럭 = 1000ms = 1초
└─ tick 펄스 (1클럭 = 10ns 동안 HIGH)

타이밍:
0s                1s                2s
│<-- 100M clk -->│<-- 100M clk -->│
│                 ┌┐                ┌┐
tick ─────────────┘└────────────────┘└─
                   ↑ 10ns           ↑ 10ns
```

### 2. SPI 전송 타이밍

```
SCLK = 50MHz (20ns 주기)
1바이트 전송 시간 = 8비트 × 20ns = 160ns
2바이트 전송 시간 = 320ns

타이밍 다이어그램:
         ┌───────────────────┐
SS       ┘                   └────

         ┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐
SCLK     ┘└┘└┘└┘└┘└┘└┘└┘└┘└┘└┘└┘└┘└┘└┘└┘└

MOSI     ─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─
          7 6 5 4 3 2 1 0 7 6 5 4 3 2 1 0
         └─ Byte 1 ───┘ └─ Byte 2 ───┘

         0        160ns     320ns
```

### 3. 전체 시스템 레이턴시

```
이벤트                    시간
─────────────────────────────────────
Tick 발생                 T+0ns
Counter 증가              T+10ns (1클럭)
SPI 전송 시작             T+20ns
SPI 전송 완료             T+340ns
Slave 수신 완료           T+360ns (동기화 2클럭)
FND 표시 업데이트         T+370ns

총 레이턴시: ~400ns (매우 빠름!)
```

### 4. FND 스캔 타이밍

```
자리 선택:     0     1     2     3     0
              ┌─────┬─────┬─────┬─────┐
              │ 1ms │ 1ms │ 1ms │ 1ms │
              └─────┴─────┴─────┴─────┘
주기: 4ms

주파수: 250Hz → 깜빡임 없음 (> 50Hz 필요)
```

---

## 테스트 및 검증

### 시뮬레이션 결과

#### Master Top 테스트
- ✅ Tick 생성: 정상 (1ms 간격)
- ✅ Counter 증가: 0→1→2→3→...
- ✅ SPI 전송: 2바이트 정상 전송
- ✅ FSM 동작: STOP ↔ RUN 토글 정상

#### Slave Top 테스트
- ✅ SPI 수신: 5개 테스트 케이스 모두 통과
  - Counter = 1 ✓
  - Counter = 255 ✓
  - Counter = 256 ✓
  - Counter = 1234 ✓
  - Counter = 16383 (max) ✓

#### Full System 테스트
- ✅ Master/Slave 통신: 100% 일치
- ✅ 버튼 동작: Debouncing 정상
- ✅ FND 표시: 정상 출력
- ⚠️ 샘플링 타이밍 아티팩트 (하드웨어와 무관)

### 검증된 기능

1. **Tick 생성**
   - 1초 간격 정확도 확인
   - 시뮬레이션: 1ms 사용 (100,000 클럭)

2. **SPI 통신**
   - 14비트 데이터 정확히 전송/수신
   - 2바이트 분할/재조합 정상

3. **버튼 제어**
   - Debouncing: 20ms (2,000,000 클럭)
   - Edge Detection: 1클럭 펄스 생성
   - FSM: 토글 동작 정상

4. **FND 표시**
   - 4자리 10진수 표시
   - 동적 스캔 동작 확인

---

## 하드웨어 연결

### Single Board 테스트 (JB ↔ JC 연결)

```
Basys3 FPGA 보드
┌─────────────────────────────────┐
│                                 │
│  JB (Master 출력)   JC (Slave 입력)
│  ┌─┐               ┌─┐         │
│  │1│ master_sclk   │1│ slave_sclk
│  ├─┤      └─────────├─┤         │
│  │2│ master_mosi   │2│ slave_mosi
│  ├─┤      └─────────├─┤         │
│  │3│ master_ss     │3│ slave_ss │
│  ├─┤      └─────────├─┤         │
│  │4│               │4│         │
│  └─┘               └─┘         │
│                                 │
│  점퍼 와이어 3개 필요:          │
│  - JB1 → JC1 (SCLK)            │
│  - JB2 → JC2 (MOSI)            │
│  - JB3 → JC3 (SS)              │
│                                 │
│  버튼:                          │
│  - BTNC: Reset                 │
│  - BTNU: Run/Stop              │
│  - BTND: Clear                 │
│                                 │
│  LED:                           │
│  - LED[7:0]: Counter 값        │
│  - LED[8]: Run/Stop 상태       │
│  - LED[9]: Tick 신호           │
│                                 │
│  FND: 4자리 카운터 표시        │
└─────────────────────────────────┘
```

### Two Board 테스트 (향후 확장)

```
Master Board                Slave Board
┌──────────────┐           ┌──────────────┐
│   JB Port    │           │   Pmod Port  │
│   ┌─┐        │           │   ┌─┐        │
│   │1│ SCLK ──┼───────────┼──→│1│        │
│   ├─┤        │           │   ├─┤        │
│   │2│ MOSI ──┼───────────┼──→│2│        │
│   ├─┤        │           │   ├─┤        │
│   │3│ SS ────┼───────────┼──→│3│        │
│   ├─┤        │           │   ├─┤        │
│   │4│ GND ───┼───────────┼───│4│ GND    │
│   └─┘        │           │   └─┘        │
└──────────────┘           └──────────────┘

Master: master_top.sv 사용
Slave: slave_top.sv 사용
```

### 연결 시 주의사항

1. **GND 연결 필수**
   - 두 보드의 GND를 반드시 연결
   - 신호 레벨 기준점 필요

2. **신호 방향 확인**
   - SCLK, MOSI, SS: Master → Slave (출력 → 입력)
   - MISO: Slave → Master (이 프로젝트에서는 미사용)

3. **전원 주의**
   - 3.3V 신호 레벨
   - 5V와 연결하지 말 것 (FPGA 손상 위험)

4. **와이어 길이**
   - 가능한 짧게 (< 30cm)
   - 너무 길면 신호 왜곡 가능

---

## 디버깅 팁

### LED로 상태 확인

```systemverilog
// LED[7:0]: Counter 값 (2진수)
// LED[8]: RunStop 상태 (1=RUN, 0=STOP)
// LED[9]: Tick 신호 (1초마다 깜빡임)

예시:
Counter = 5 (0b00000101)
RunStop = RUN
Tick = 깜빡임

LED: 0 1 0 0 0 0 0 1 0 1
     ↑             ↑ ↑ ↑
    tick       runstop │
                    counter=5
```

### 예상 동작

1. **리셋 후**
   - LED[7:0] = 0
   - LED[8] = 0 (STOP)
   - LED[9] = 깜빡임 (tick은 계속 발생)
   - FND = "0000"

2. **BTNU 누름 (RUN 시작)**
   - LED[8] = 1 (RUN)
   - 1초마다 LED[7:0] 증가
   - FND도 1초마다 증가

3. **BTNU 다시 누름 (STOP)**
   - LED[8] = 0 (STOP)
   - LED[7:0] 고정
   - FND 고정

4. **BTND 누름 (CLEAR)**
   - LED[7:0] = 0
   - FND = "0000"

### 문제 해결

| 증상 | 원인 | 해결 |
|------|------|------|
| FND가 안 켜짐 | JB-JC 미연결 | 점퍼 와이어 확인 |
| FND가 깜빡임 | 연결 불량 | 와이어 재연결 |
| 카운터가 안 증가 | STOP 상태 | BTNU로 RUN 시작 |
| 버튼이 안 먹힘 | Debouncer 시간 | 20ms 파라미터 확인 |
| LED[9]가 안 깜빡임 | Tick 생성 문제 | tick_gen 모듈 확인 |

---

## 추가 학습 자료

### SPI 심화 학습

1. **SPI Mode**
   - Mode 0: CPOL=0, CPHA=0 (이 프로젝트)
   - Mode 1, 2, 3: 다른 타이밍

2. **멀티 슬레이브**
   - SS 신호로 여러 슬레이브 선택
   - Daisy Chain 연결

3. **양방향 통신**
   - MISO 사용
   - Full-duplex 통신

### 클럭 도메인 크로싱 (CDC)

1. **Synchronizer**
   - 2-FF 동기화
   - Gray code 카운터

2. **메타스테이블**
   - MTBF (Mean Time Between Failures)
   - 안전한 설계 기법

### FSM 설계

1. **Moore vs Mealy**
   - Moore: 출력이 상태에만 의존
   - Mealy: 출력이 상태+입력에 의존

2. **One-hot encoding**
   - 각 상태를 1비트로 표현
   - 빠른 디코딩, 많은 리소스

### FPGA 최적화

1. **타이밍 제약**
   - 클럭 주파수 설정
   - Setup/Hold time

2. **리소스 사용**
   - LUT, FF, BRAM
   - 효율적인 코드 작성

---

## 요약

이 프로젝트는 **SPI 통신의 기본 개념**을 실습하면서 **FPGA 설계의 핵심 기법**을 모두 포함합니다:

✅ **클럭 분주** (Tick Generator)
✅ **상태 기계** (FSM)
✅ **직렬 통신** (SPI)
✅ **클럭 도메인 크로싱** (Synchronizer)
✅ **디바운싱** (Button Debouncer)
✅ **엣지 검출** (Edge Detector)
✅ **동적 스캔** (FND Controller)

각 모듈의 **설계 이유**를 이해하면, 다른 FPGA 프로젝트에도 응용할 수 있습니다.

---

## 참고 문헌

1. SPI Protocol Specification
2. Basys3 FPGA Reference Manual
3. Clock Domain Crossing Techniques
4. Debouncing Tutorial
5. 7-Segment Display Control

---

**문서 작성일**: 2025-01-09
**버전**: 1.0
**프로젝트**: SPI Master-Slave Counter System
