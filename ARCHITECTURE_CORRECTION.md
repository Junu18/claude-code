# SPI 시스템 아키텍처 정정

## ⚠️ 중요한 수정사항

기존 `SPI_SYSTEM_GUIDE.md` 문서에서 SPI Master 부분을 잘못 설명했습니다.
실제 코드 구조에 맞게 정정합니다.

---

## 실제 코드 구조

### ❌ 문서에 설명한 것 (잘못됨)
- `spi_master_tx.sv`: 14비트를 2바이트로 나누고 전송

### ✅ 실제 구조 (올바름)
1. **`spi_master.sv`**: 8비트(1바이트)만 전송하는 기본 SPI 모듈
2. **`master_top.sv`**: 14비트를 2바이트로 나누고, spi_master를 2번 호출하는 상위 모듈

---

## 모듈별 상세 설명

### 1. `spi_master.sv` - 기본 SPI 통신 모듈

#### 목적
- **8비트(1바이트) 단위** SPI 통신
- SCLK 생성 및 MOSI 데이터 전송
- 재사용 가능한 범용 SPI 모듈

#### 인터페이스
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

#### FSM (3-State)
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

#### SCLK 생성
```
100MHz / 100 = 1MHz SCLK
CP0: 50 cycles (LOW)
CP1: 50 cycles (HIGH)
```

#### 데이터 전송
```systemverilog
// MOSI = tx_data_reg의 MSB
assign mosi = tx_data_reg[7];

// CP1에서 왼쪽 시프트 (다음 비트 준비)
tx_data_next = {tx_data_reg[6:0], 1'b0};
```

#### 핵심 특징
- **SS 신호 없음** → 외부에서 제어
- **1바이트만 전송** → 여러 바이트는 여러 번 호출
- **done 신호로 완료 통지**

---

### 2. `master_top.sv` - 2바이트 전송 제어 모듈

#### 목적
- **14비트 카운터**를 2바이트로 분할
- **spi_master를 2번 호출**하여 순차 전송
- **SS 신호 제어** (2바이트 전송 동안 LOW 유지)

#### 14비트 → 2바이트 분할
```systemverilog
// 카운터: 14비트 [13:0]
// 상위 바이트: [13:8] + 2비트 패딩 = 00[13:8]
// 하위 바이트: [7:0]

assign tx_high_byte = {2'b00, w_counter[13:8]};
assign tx_low_byte  = w_counter[7:0];
```

**예시:**
```
카운터 = 1234 (10진수) = 0000_0100_1101_0010 (2진수)
                         [13:8]=[000100]  [7:0]=[11010010]

tx_high_byte = 00_000100 = 0x04
tx_low_byte  = 11010010  = 0xD2
```

#### FSM (5-State)
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

#### 타이밍 다이어그램
```
tick      ─┐  ┌─────────────────
           └──┘

SS        ────┐             ┌────
              └─────────────┘
              ↑             ↑
           2바이트 전송   트랜잭션 완료

SCLK      ────┐┐┐┐┐┐┐┐┐┐┐┐┐┐┐┐────
              └┘└┘└┘└┘└┘└┘└┘└┘
              └─ Byte1 ─┘└─ Byte2 ─┘

MOSI      ────[  H7...H0  ][  L7...L0  ]────
```

#### 코드 흐름
```systemverilog
case (state)
    IDLE: begin
        ss_next = 1'b1;  // SS inactive
        if (counter_tick) begin
            tx_data_next = tx_high_byte;  // 상위 바이트 준비
            ss_next      = 1'b0;          // SS active
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
            tx_data_next = tx_low_byte;  // 하위 바이트 준비
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
            ss_next    = 1'b1;  // SS inactive
            state_next = IDLE;
        end else begin
            ss_next = 1'b0;     // Keep SS active
        end
    end
endcase
```

#### 핵심 특징
- **SS 신호 제어**: 2바이트 전송 동안 LOW 유지
- **순차 전송**: 상위 → 하위 바이트 순서
- **tick 기반**: 1초마다 카운터 값 전송

---

## Slave 측 수신

### `spi_slave.sv` + `slave_controller.sv`

#### 수신 과정
1. SS=LOW 감지 → 수신 시작
2. SCLK 상승 엣지마다 MOSI 비트 읽기
3. 8비트 완료 → byte1 저장
4. 8비트 완료 → byte2 저장
5. 14비트 재조합
   ```systemverilog
   counter_14bit = {byte1[5:0], byte2};
   ```

#### 데이터 재조합 (Slave)
```
수신: byte1=0x04, byte2=0xD2

byte1 = 00000100 → [5:0] = 000100
byte2 = 11010010 → [7:0] = 11010010

재조합: {000100, 11010010} = 0000_0100_1101_0010 = 1234 ✓
```

---

## 전체 데이터 흐름

```
Master Side:
┌─────────────┐
│ 14비트      │ = 1234
│ w_counter   │
└──────┬──────┘
       │ 분할
       ├─────────┬─────────┐
       │         │         │
  tx_high_byte  tx_low_byte
    = 0x04      = 0xD2
       │         │
       ▼         ▼
  ┌─────────────────┐
  │  spi_master     │ (2번 호출)
  │  8비트 전송     │
  └────────┬────────┘
           │ SPI 신호
  ─────────┼─────────
           │
Slave Side:
  ┌────────▼────────┐
  │  spi_slave      │
  │  8비트 수신     │ (2번)
  └────────┬────────┘
           │
      byte1, byte2
       │         │
       └─────┬───┘
             │ 재조합
        ┌────▼─────┐
        │ 14비트   │ = 1234
        │ counter  │
        └──────────┘
```

---

## 설계 이유

### Q: 왜 spi_master를 8비트로만 만들었는가?
**A: 재사용성과 범용성**
- 8비트는 SPI 표준 단위
- 다양한 데이터 크기에 재사용 가능
- 14비트, 16비트, 32비트 등 상위 모듈에서 조합

### Q: 왜 SS 신호를 master_top에서 제어하는가?
**A: 트랜잭션 경계 제어**
- 2바이트를 하나의 트랜잭션으로 묶기 위함
- SS=LOW 동안이 하나의 메시지
- Slave가 바이트 경계를 명확히 알 수 있음

### Q: 왜 상위 바이트를 먼저 보내는가?
**A: Big-Endian 방식**
- 네트워크 바이트 순서 표준
- 디버깅 시 읽기 쉬움
- 확장성 (16비트, 32비트로 확장 용이)

---

## 타이밍 계산

### 1바이트 전송 시간
```
SCLK = 1MHz (100 clk / 1 cycle = 1us per cycle)
8비트 = 8 cycles = 8us
```

### 2바이트 전송 시간
```
Byte1: 8us
Byte2: 8us
상태 전환: ~1us
Total: ~17us
```

### 전송 효율
```
1초마다 1번 전송
전송 시간: 17us
유휴 시간: 999,983us
효율: 0.0017% (충분히 여유 있음)
```

---

## 실제 파일 구조 요약

```
Master Side:
├── master_top.sv          (14비트 → 2바이트 분할, FSM)
│   ├── spi_master.sv      (8비트 SPI 전송)
│   ├── tick_gen.sv        (1초 타이머)
│   ├── spi_upcounter_cu.sv (RUN/STOP 제어)
│   └── spi_upcounter_dp.sv (14비트 카운터)

Slave Side:
├── slave_top.sv           (전체 통합)
│   ├── spi_slave.sv       (8비트 SPI 수신)
│   ├── slave_controller.sv (2바이트 재조합)
│   └── fnd_controller.sv  (7-segment 표시)

System:
└── full_system_top.sv     (Master + Slave 통합)
```

---

## 결론

- `spi_master.sv`: 범용 8비트 SPI 통신 모듈
- `master_top.sv`: 애플리케이션 특화 2바이트 전송 제어
- 모듈 분리로 재사용성과 유지보수성 향상

**문서 `SPI_SYSTEM_GUIDE.md`의 "SPI Master Transmitter" 섹션은 이 내용으로 대체되어야 합니다.**

---

**작성일**: 2025-01-10
**목적**: SPI 시스템 아키텍처 정정 및 명확화
