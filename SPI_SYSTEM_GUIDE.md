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
    ├─ Byte 1 (High): 2'b00 + [13:8] (패딩 2비트 + 상위 6비트)
    └─ Byte 2 (Low): [7:0] (하위 8비트)
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

### 3. SPI Master 시스템

SPI Master는 두 개의 계층으로 구성됩니다:
1. `spi_master.sv`: 8비트 단위 SPI 통신 (하드웨어 계층)
2. `master_top.sv`: 14비트 데이터 분할 및 전송 제어 (애플리케이션 계층)

---

#### 3-1. `spi_master.sv` - 기본 SPI 통신 모듈

##### 목적
- **8비트(1바이트) 단위** SPI 통신
- SCLK 생성 및 MOSI 데이터 전송
- 재사용 가능한 범용 SPI 모듈

##### 인터페이스
```systemverilog
module spi_master (
    input  logic       clk,       // 100MHz
    input  logic       reset,
    input  logic       start,     // 전송 시작 신호
    input  logic [7:0] tx_data,   // 전송할 8비트 데이터
    output logic [7:0] rx_data,   // 수신한 8비트 데이터
    output logic       tx_ready,  // 전송 준비 완료
    output logic       done,      // 전송 완료
    output logic       sclk,      // SPI Clock
    output logic       mosi,      // Master Out
    input  logic       miso       // Master In
);
```

##### FSM (3-State)
```
   ┌─────────┐
   │  IDLE   │ ← 대기 (tx_ready=1)
   └────┬────┘
        │ start=1
        ▼
   ┌─────────┐
   │   CP0   │ ← SCLK Low (50 clk cycles)
   └────┬────┘
        │ 50 cycles 완료
        ▼
   ┌─────────┐
   │   CP1   │ ← SCLK High (50 clk cycles)
   └────┬────┘
        │ 8비트 완료 시
        ▼
   (IDLE로 복귀, done=1)
```

##### 코드 분석
```systemverilog
typedef enum {
    IDLE,  // 대기
    CP0,   // Clock Phase 0 (SCLK LOW)
    CP1    // Clock Phase 1 (SCLK HIGH)
} state_t;

state_t state, state_next;
logic [7:0] tx_data_reg, tx_data_next;
logic [7:0] rx_data_reg, rx_data_next;
logic [5:0] sclk_counter_reg, sclk_counter_next;  // 0~49
logic [2:0] bit_counter_reg, bit_counter_next;    // 0~7
logic sclk_reg, sclk_next;

assign mosi = tx_data_reg[7];  // MSB부터 전송
assign sclk = sclk_reg;
```

##### SCLK 생성 (1MHz)
```
100MHz / 100 = 1MHz SCLK

CP0: 50 cycles (SCLK=LOW)  → 500ns
CP1: 50 cycles (SCLK=HIGH) → 500ns
Total: 1us per bit, 8us per byte
```

**타이밍 다이어그램:**
```
clk (100MHz)  ┌┐┌┐┌┐...┌┐┌┐┌┐...
              └┘└┘└┘   └┘└┘└┘

sclk_counter  0→1→2...→49→0→1...→49
              └─ CP0 ──┘ └─ CP1 ──┘

sclk          ────────────┐        ┌────
                          └────────┘
              └── 500ns ──┘└ 500ns ┘

mosi          ─────[bit7]──[bit6]──...
```

##### 핵심 특징
- **SS 신호 없음**: 외부(master_top)에서 제어
- **1바이트만 전송**: 여러 바이트는 여러 번 호출
- **done 신호**: 전송 완료 통지

##### 설계 결정 사항

**Q: 왜 50 클럭씩 사용하는가?**
- A: 1MHz SCLK 생성 (100MHz / 100 = 1MHz)
  - Slave가 안정적으로 읽을 수 있는 속도

**Q: 왜 MSB부터 전송하는가?**
- A: SPI 표준 (Big-Endian)
  - 네트워크 바이트 순서와 일치

---

#### 3-2. `master_top.sv` - 2바이트 전송 제어 모듈

##### 목적
- **14비트 카운터**를 2바이트로 분할
- **spi_master를 2번 호출**하여 순차 전송
- **SS 신호 제어** (2바이트 전송 동안 LOW 유지)

##### 14비트 → 2바이트 분할
```systemverilog
// 카운터: 14비트 [13:0]
// 분할 방식:
assign tx_high_byte = {2'b00, w_counter[13:8]};  // 상위 6비트 + 패딩
assign tx_low_byte  = w_counter[7:0];            // 하위 8비트
```

**예시:**
```
카운터 = 1234 (10진수) = 00_0100_1101_0010

tx_high_byte = 00_000100 = 0x04
tx_low_byte  = 11010010  = 0xD2

Slave 재조합: {0x04[5:0], 0xD2} = 1234 ✓
```

##### FSM (5-State)
```
    ┌─────────────┐
    │    IDLE     │ ← SS=HIGH
    └──────┬──────┘
           │ counter_tick=1 (1초마다)
           ▼
    ┌─────────────┐
    │  SEND_HIGH  │ ← SS=LOW, spi_start=1
    └──────┬──────┘      (상위 바이트 전송 시작)
           ▼
    ┌─────────────┐
    │  WAIT_HIGH  │ ← SS=LOW 유지
    └──────┬──────┘      (spi_done 대기)
           │ spi_done=1
           ▼
    ┌─────────────┐
    │  SEND_LOW   │ ← SS=LOW, spi_start=1
    └──────┬──────┘      (하위 바이트 전송 시작)
           ▼
    ┌─────────────┐
    │  WAIT_LOW   │ ← SS=LOW 유지
    └──────┬──────┘      (spi_done 대기)
           │ spi_done=1
           ▼
    (IDLE로 복귀, SS=HIGH)
```

##### 코드 분석
```systemverilog
typedef enum logic [2:0] {
    IDLE,
    SEND_HIGH,
    WAIT_HIGH,
    SEND_LOW,
    WAIT_LOW
} state_t;

// SS 신호 제어
assign ss = ss_reg;

case (state)
    IDLE: begin
        ss_next = 1'b1;  // SS inactive (HIGH)
        if (counter_tick) begin
            tx_data_next = tx_high_byte;
            ss_next      = 1'b0;  // SS active (LOW) - 트랜잭션 시작
            state_next   = SEND_HIGH;
        end
    end

    SEND_HIGH: begin
        ss_next   = 1'b0;     // Keep SS active
        spi_start = 1'b1;     // spi_master 시작
        state_next = WAIT_HIGH;
    end

    WAIT_HIGH: begin
        ss_next = 1'b0;       // Keep SS active
        if (spi_done) begin
            tx_data_next = tx_low_byte;
            state_next   = SEND_LOW;
        end
    end

    SEND_LOW: begin
        ss_next   = 1'b0;
        spi_start = 1'b1;     // spi_master 다시 시작
        state_next = WAIT_LOW;
    end

    WAIT_LOW: begin
        if (spi_done) begin
            ss_next    = 1'b1;  // SS inactive (HIGH) - 트랜잭션 완료
            state_next = IDLE;
        end else begin
            ss_next = 1'b0;     // Keep SS active
        end
    end
endcase
```

##### 타이밍 다이어그램
```
tick      ─┐  ┌─────────────────
           └──┘

SS        ────┐             ┌────
              └─────────────┘
              ↑             ↑
           2바이트 전송   완료

SCLK      ────┐┐┐┐┐┐┐┐┐┐┐┐┐┐┐┐────
              └┘└┘└┘└┘└┘└┘└┘└┘
              └─ 8us ─┘└─ 8us ─┘

MOSI      ────[H7...H0][L7...L0]────
              └ Byte1 ┘└ Byte2 ┘
```

##### 설계 결정 사항

**Q: 왜 spi_master를 8비트로만 만들었는가?**
- A: **재사용성과 범용성**
  - 8비트는 SPI 표준 단위
  - 다양한 데이터 크기에 재사용 가능
  - 상위 모듈에서 필요한 만큼 조합

**Q: 왜 SS 신호를 master_top에서 제어하는가?**
- A: **트랜잭션 경계 제어**
  - 2바이트를 하나의 메시지로 묶기 위함
  - SS=LOW 동안이 하나의 트랜잭션
  - Slave가 바이트 경계를 명확히 인식

**Q: 왜 상위 바이트를 먼저 보내는가?**
- A: **Big-Endian 방식**
  - 네트워크 바이트 순서 표준
  - 디버깅 시 읽기 쉬움

---

### 4. SPI Slave 시스템

SPI Slave도 Master와 같이 두 개의 계층으로 구성됩니다:
1. `spi_slave.sv`: 8비트 단위 SPI 수신 (하드웨어 계층)
2. `slave_controller.sv`: 2바이트 수집 및 14비트 재조합 (애플리케이션 계층)

---

#### 4-1. `spi_slave.sv` - 기본 SPI 수신 모듈

##### 목적
- **8비트(1바이트) 단위** SPI 수신
- SCLK 상승 엣지에서 MOSI 데이터 수신
- 재사용 가능한 범용 SPI 모듈

##### 인터페이스
```systemverilog
module spi_slave (
    input  logic       clk,       // 100MHz 시스템 클럭
    input  logic       reset,
    input  logic       sclk,      // SPI Clock (from Master)
    input  logic       mosi,      // Master Out
    output logic       miso,      // Master In (미사용)
    input  logic       ss,        // Slave Select (active low)
    output logic [7:0] rx_data,   // 수신한 8비트 데이터
    output logic       done       // 1클럭 펄스 (바이트 수신 완료)
);
```

##### 왜 Synchronizer가 필요한가?

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

##### Synchronizer 구조

```systemverilog
logic sclk_sync1, sclk_sync2;
logic mosi_sync1, mosi_sync2;
logic ss_sync1, ss_sync2;

always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
        sclk_sync1 <= 0;
        sclk_sync2 <= 0;
        ss_sync1   <= 1;  // SS inactive
        ss_sync2   <= 1;
        mosi_sync1 <= 0;
        mosi_sync2 <= 0;
    end else begin
        // 2단 동기화
        sclk_sync1 <= sclk;
        sclk_sync2 <= sclk_sync1;
        ss_sync1   <= ss;
        ss_sync2   <= ss_sync1;
        mosi_sync1 <= mosi;
        mosi_sync2 <= mosi_sync1;
    end
end

// SCLK 상승 엣지 검출
assign sclk_rising_edge = sclk_sync1 && !sclk_sync2;
```

##### 데이터 수신 과정

```
1. SS가 LOW이면 수신 활성화
2. SCLK 상승 엣지마다 MOSI 비트를 shift register로 읽음
3. 8비트 완료 시 done 신호 1클럭 펄스
4. slave_controller가 done 신호로 바이트 수신
```

##### 코드 분석

```systemverilog
logic [7:0] rx_shift_reg;
logic [2:0] bit_counter;  // 0~7
logic       done_reg;

assign rx_data = rx_shift_reg;
assign done = done_reg;

always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
        rx_shift_reg <= 8'h00;
        bit_counter  <= 3'd0;
        done_reg     <= 1'b0;
    end else begin
        done_reg <= 1'b0;  // Default: clear done

        if (ss_sync2) begin
            // SS inactive (high) - 리셋
            rx_shift_reg <= 8'h00;
            bit_counter  <= 3'd0;
        end else begin
            // SS active (low) - 수신
            if (sclk_rising_edge) begin
                // MSB first로 비트 수신
                rx_shift_reg <= {rx_shift_reg[6:0], mosi_sync2};
                bit_counter  <= bit_counter + 1;

                // 8비트 완료 확인
                if (bit_counter == 3'd7) begin
                    done_reg    <= 1'b1;  // 1클럭 펄스
                    bit_counter <= 3'd0;  // 리셋
                end
            end
        end
    end
end
```

##### 핵심 특징
- **FSM 없음**: 단순 shift register 기반
- **8비트만 수신**: 여러 바이트는 done 신호로 상위 모듈이 처리
- **done 펄스**: 바이트 완료 시 1클럭 신호

---

#### 4-2. `slave_controller.sv` - 2바이트 수집 및 재조합 모듈

##### 목적
- **spi_slave로부터 2바이트 수집**
- **14비트로 재조합**
- **트랜잭션 경계 관리** (SS 신호 모니터링)

##### FSM (4-State)
```
    ┌─────────────┐
    │    IDLE     │
    └──────┬──────┘
           │ ss=LOW (트랜잭션 시작)
           ▼
    ┌─────────────┐
    │ WAIT_HIGH   │ ← 첫 번째 바이트 대기
    └──────┬──────┘
           │ done=1
           ▼
    ┌─────────────┐
    │ WAIT_LOW    │ ← 두 번째 바이트 대기
    └──────┬──────┘
           │ done=1
           ▼
    ┌─────────────┐
    │ DATA_READY  │ ← 14비트 재조합
    └──────┬──────┘
           │ ss=HIGH (트랜잭션 완료)
           ▼
    (IDLE로 복귀)
```

##### 코드 분석
```systemverilog
typedef enum logic [1:0] {
    IDLE,
    WAIT_HIGH,
    WAIT_LOW,
    DATA_READY
} state_t;

logic [7:0] high_byte_reg, high_byte_next;
logic [7:0] low_byte_reg, low_byte_next;
logic [13:0] counter_reg, counter_next;

case (state)
    IDLE: begin
        // SS LOW 대기 (트랜잭션 시작)
        if (!ss_sync2) begin
            state_next = WAIT_HIGH;
        end
    end

    WAIT_HIGH: begin
        // 첫 번째 바이트 대기
        if (ss_rising_edge) begin
            // 트랜잭션 중단
            state_next = IDLE;
        end else if (done) begin
            // 상위 바이트 수신
            high_byte_next = rx_data;
            state_next     = WAIT_LOW;
        end
    end

    WAIT_LOW: begin
        // 두 번째 바이트 대기
        if (ss_rising_edge) begin
            // 트랜잭션 중단
            state_next = IDLE;
        end else if (done) begin
            // 하위 바이트 수신
            low_byte_next = rx_data;
            state_next    = DATA_READY;
        end
    end

    DATA_READY: begin
        // 14비트 재조합
        counter_next = {high_byte_reg[5:0], low_byte_reg[7:0]};
        data_valid_next = 1'b1;  // 유효 데이터 신호

        // SS 상승 엣지 대기 (트랜잭션 완료)
        if (ss_rising_edge) begin
            state_next = IDLE;
        end
    end
endcase
```

##### 핵심 특징
- **SS 엣지 검출**: 트랜잭션 경계 감지
- **2바이트 순차 수집**: WAIT_HIGH → WAIT_LOW
- **14비트 재조합**: {high[5:0], low[7:0]}
- **data_valid 펄스**: FND 업데이트 신호

##### 설계 결정 사항

**Q: 왜 spi_slave를 8비트로만 만들었는가?**
- A: **재사용성과 범용성**
  - 8비트는 SPI 표준 단위
  - 다양한 프로토콜에 재사용 가능
  - 상위 모듈에서 필요한 만큼 조합

**Q: 왜 2단 Synchronizer를 사용하는가?**
- A: **메타스테이블 방지**
  - 1단은 메타스테이블 발생 가능성이 높음
  - 2단을 사용하면 시스템 전파 확률이 매우 낮아짐 (10^-12 이하)

**Q: 왜 상승 엣지에서 데이터를 읽는가?**
- A: **SPI Mode 0 규칙**
  - Master는 하강 엣지에서 데이터 준비
  - Slave는 상승 엣지에서 데이터 읽음
  - 데이터가 안정적인 시점에 읽을 수 있음

**Q: 왜 slave_controller를 분리했는가?**
- A: **관심사의 분리 (Separation of Concerns)**
  - spi_slave: 하드웨어 프로토콜 처리
  - slave_controller: 애플리케이션 로직 처리
  - SS 엣지 감지로 트랜잭션 경계 명확화

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
│  LED (Master):                  │
│  - LED[7:0]: Master Counter    │
│  - LED[8]: Run/Stop 상태       │
│  - LED[9]: Tick 신호           │
│                                 │
│  LED (Slave 디버깅):           │
│  - LED[10-13]: Slave Counter[3:0] │
│  - LED[14]: Slave Data Valid   │
│  - LED[15]: SPI Active (SS)    │
│                                 │
│  FND: 4자리 Slave 카운터 표시 │
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
// Master 상태 LED
// LED[7:0]: Master Counter 값 (2진수)
// LED[8]: RunStop 상태 (1=RUN, 0=STOP)
// LED[9]: Tick 신호 (1초마다 깜빡임)

// Slave 디버깅 LED (추가됨)
// LED[10-13]: Slave Counter[3:0] (하위 4비트)
// LED[14]: Slave Data Valid (SPI 수신 성공 시 켜짐)
// LED[15]: SPI Active (SS 신호, 전송 중 깜빡임)

예시: Master Counter = 5, Slave도 정상 수신
LED[15-0]: 1 1 0 1 0 1 0 0 0 0 0 1 0 1
           ↑ ↑ ↑─┬─↑ ↑           ↑─┬─↑
          SPI│ Slave │          Master=5
         Active Valid=5

정상 동작 시:
- LED[7:0]와 LED[10-13]이 같이 증가 (Master = Slave)
- LED[14] 계속 켜짐 (데이터 수신 성공)
- LED[15] 1초마다 짧게 깜빡임 (SPI 전송)
```

### 예상 동작

1. **리셋 후**
   - LED[7:0] = 0 (Master 카운터)
   - LED[8] = 0 (STOP 상태)
   - LED[9] = 깜빡임 (tick은 계속 발생)
   - LED[10-13] = 0 (Slave 카운터)
   - LED[14] = 0 (아직 데이터 없음)
   - LED[15] = 0 (SPI 비활성)
   - FND = "0000"

2. **BTNU 누름 (RUN 시작)**
   - LED[8] = 1 (RUN 상태)
   - 1초마다:
     - LED[7:0] 증가 (Master 카운터)
     - LED[15] 짧게 깜빡 (SPI 전송)
     - LED[10-13] 증가 (Slave 카운터)
     - LED[14] = 1 (데이터 수신 성공)
     - FND 값 증가

3. **BTNU 다시 누름 (STOP)**
   - LED[8] = 0 (STOP 상태)
   - LED[7:0] 고정 (Master 정지)
   - LED[10-13] 고정 (Slave도 정지)
   - LED[15] = 0 (SPI 전송 없음)
   - FND 고정

4. **BTND 누름 (CLEAR)**
   - LED[7:0] = 0 (Master 초기화)
   - LED[10-13] = 0 (Slave 초기화)
   - FND = "0000"

### 문제 해결

| 증상 | 원인 | 해결 |
|------|------|------|
| FND가 "0000"만 표시 | SPI 통신 실패 | LED[15] 확인 (점퍼 와이어) |
| LED[15]가 안 깜빡임 | Master SPI 미동작 | Master 코드 확인 |
| LED[15]는 깜빡이는데 LED[14]가 꺼짐 | Slave 수신 실패 | 점퍼 와이어 재연결 |
| LED[14]는 켜지는데 FND가 안 증가 | FND 컨트롤러 문제 | slave_top 확인 |
| LED[10-13]과 LED[7:0]이 다름 | 동기화 문제 | 드물게 발생, 무시 가능 |
| 카운터가 안 증가 | STOP 상태 | BTNU로 RUN 시작 |
| 버튼이 안 먹힘 | Debouncer 시간 | 20ms 파라미터 확인 |
| LED[9]가 안 깜빡임 | Tick 생성 문제 | tick_gen 모듈 확인 |

#### SPI 통신 디버깅 순서

1. **LED[9] 확인**: 1초마다 깜빡이는가?
   - NO → Tick Generator 문제
   - YES → 다음 단계

2. **LED[8] 확인**: RUN 상태인가?
   - NO → BTNU 버튼 누름
   - YES → 다음 단계

3. **LED[7:0] 확인**: 1초마다 증가하는가?
   - NO → Counter/FSM 문제
   - YES → Master 정상, 다음 단계

4. **LED[15] 확인**: 1초마다 짧게 깜빡이는가?
   - NO → SPI Master TX 문제
   - YES → Master 전송 정상, 다음 단계

5. **LED[14] 확인**: 켜져 있는가?
   - NO → **점퍼 와이어 연결 확인!**
   - YES → SPI 수신 성공, 다음 단계

6. **LED[10-13] 확인**: LED[7:0]의 하위 4비트와 같은가?
   - NO → Slave 카운터 업데이트 문제
   - YES → 전체 시스템 정상!

7. **FND 확인**: 숫자가 증가하는가?
   - NO → FND Controller 문제
   - YES → 완벽!

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
✅ **디버깅 기법** (LED 상태 표시)

### 성공적인 구현 확인

정상 동작 시 다음을 확인할 수 있습니다:
- **FND**: 1초마다 증가하는 카운터 표시 (0000→0001→0002→...)
- **LED[7:0]**: Master 카운터 (2진수)
- **LED[10-13]**: Slave 카운터 (Master와 동일)
- **LED[14]**: 항상 켜짐 (SPI 수신 성공)
- **LED[15]**: 1초마다 짧게 깜빡임 (SPI 전송)

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
**최종 수정일**: 2025-01-10
**버전**: 1.1
**프로젝트**: SPI Master-Slave Counter System

### 변경 이력

**v1.1** (2025-01-10)
- 디버깅 LED 추가 (LED[10-15])
- SPI 통신 디버깅 순서 가이드 추가
- 문제 해결 섹션 확장
- 성공적인 구현 확인 섹션 추가

**v1.0** (2025-01-09)
- 초기 문서 작성
- 전체 시스템 설계 설명
- 모든 모듈 상세 분석
