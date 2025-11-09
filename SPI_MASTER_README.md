# SPI Master System - 설계 문서

## 개요

14비트 카운터 값을 SPI를 통해 2바이트로 나누어 전송하는 시스템입니다.

## 시스템 사양

- **시스템 클럭**: 100MHz
- **Tick 주기**: 100ms (실제) / 1ms (시뮬레이션용)
- **SPI 전송**: 1MHz (SCLK)
- **데이터 포맷**: 14비트 → High Byte (6bit + 2bit padding) + Low Byte (8bit)

## 모듈 구조

```
master_top
├── tick_gen           # 주기적 tick 생성 (100ms)
├── spi_master         # SPI 1바이트 전송기
├── spi_upcounter_cu   # 카운터 제어 유닛
├── spi_upcounter_dp   # 카운터 데이터패스
└── FSM                # 2바이트 전송 제어
```

## 주요 개선 사항

### 1. Tick Generator 추가
- **문제**: 카운터가 증가할 때마다 SPI 전송하면 타이밍 문제 발생
- **해결**: 별도의 tick_gen 모듈로 주기적(100ms)으로만 전송

### 2. FSM 재설계
```
IDLE → SEND_HIGH → WAIT_HIGH → SEND_LOW → WAIT_LOW → IDLE
```

- **IDLE**: tick 대기
- **SEND_HIGH**: High byte 전송 시작
- **WAIT_HIGH**: High byte 전송 완료 대기
- **SEND_LOW**: Low byte 전송 시작
- **WAIT_LOW**: Low byte 전송 완료 대기

### 3. 데이터 분할

14비트 카운터를 2바이트로 분할:
```
counter[13:0] = 0x1234 (예시)

High Byte = {2'b00, counter[13:8]} = 0x12
Low Byte  = counter[7:0]            = 0x34
```

## 파일 목록

### 핵심 모듈
1. **tick_gen.sv** - Tick 생성기
2. **spi_master.sv** - SPI 마스터 (1바이트 전송)
3. **spi_upcounter_cu.sv** - 카운터 제어 유닛
4. **spi_upcounter_dp.sv** - 카운터 데이터패스
5. **master_top.sv** - 최상위 모듈 (100ms tick)
6. **master_top_fast.sv** - 빠른 시뮬레이션용 (1ms tick)

### 테스트벤치
1. **tb_master_top.sv** - 기본 테스트벤치
2. **tb_master_fast.sv** - 빠른 시뮬레이션용 테스트벤치

### 스크립트
1. **run_sim.sh** - 시뮬레이션 실행 스크립트

## 시뮬레이션 방법

### Icarus Verilog 사용

```bash
# 빠른 시뮬레이션 (1ms tick)
./run_sim.sh fast

# 일반 시뮬레이션 (100ms tick)
./run_sim.sh normal
```

### 수동 컴파일 (Icarus Verilog)

```bash
# 컴파일
iverilog -g2012 -o sim.vvp \
    tick_gen.sv \
    spi_master.sv \
    spi_upcounter_cu.sv \
    spi_upcounter_dp.sv \
    master_top_fast.sv \
    tb_master_fast.sv

# 실행
vvp sim.vvp

# 파형 보기
gtkwave master_top_fast.vcd
```

### Verilator 사용

```bash
verilator --binary -j 0 --timing \
    tick_gen.sv \
    spi_master.sv \
    spi_upcounter_cu.sv \
    spi_upcounter_dp.sv \
    master_top_fast.sv \
    tb_master_fast.sv \
    --top-module tb_master_fast

./obj_dir/Vtb_master_fast
```

### Vivado 사용

1. Vivado에서 새 프로젝트 생성
2. 모든 .sv 파일 추가
3. tb_master_fast.sv를 시뮬레이션 소스로 설정
4. Run Simulation

## 동작 흐름

### Master 동작

1. **카운터 동작**
   - i_runstop 버튼으로 시작/정지
   - i_clear 버튼으로 리셋
   - 매 클럭마다 증가 (RUN 상태일 때)

2. **Tick 발생**
   - 100ms마다 tick 신호 발생
   - tick이 발생하면 현재 카운터 값을 2바이트로 전송 시작

3. **SPI 전송**
   - tick → High byte 전송 → Low byte 전송 → 대기

### 타이밍 다이어그램

```
Counter:    0 → 1 → 2 → 3 → ... (매 클럭)
            |             |
Tick:       ↓             ↓         (100ms마다)
            |             |
SPI TX:   [H][L]        [H][L]     (2바이트씩)
```

## 포트 설명

### master_top

**입력:**
- `clk`: 100MHz 시스템 클럭
- `reset`: 비동기 리셋 (active high)
- `i_runstop`: RUN/STOP 버튼
- `i_clear`: CLEAR 버튼
- `miso`: SPI MISO (현재 사용 안 함)

**출력:**
- `sclk`: SPI 클럭 (~1MHz)
- `mosi`: SPI MOSI 데이터
- `ss`: Slave Select (active low)
- `o_counter`: 현재 카운터 값 (디버그용)

## 테스트 시나리오

### 테스트벤치에서 검증하는 항목

1. **카운터 시작/정지**
   - RUN/STOP 버튼으로 카운터 제어 확인

2. **카운터 클리어**
   - CLEAR 버튼으로 0으로 리셋 확인

3. **SPI 전송**
   - tick마다 2바이트 전송 확인
   - High/Low byte 순서 확인
   - 데이터 정합성 확인

4. **FSM 상태 전이**
   - IDLE → SEND_HIGH → WAIT_HIGH → SEND_LOW → WAIT_LOW → IDLE

## 파형 분석 포인트

GTKWave에서 확인할 신호들:

1. **클럭/리셋**
   - clk, reset

2. **카운터**
   - o_counter

3. **Tick**
   - counter_tick (내부 신호)

4. **FSM**
   - o_state (IDLE=0, SEND_HIGH=1, WAIT_HIGH=2, SEND_LOW=3, WAIT_LOW=4)

5. **SPI**
   - sclk, mosi, ss
   - spi_start, spi_done (내부 신호)

6. **데이터**
   - tx_high_byte, tx_low_byte (내부 신호)
   - spi_tx_data (내부 신호)

## 예상 결과

카운터 값이 `0x1234` (4660)일 때:

```
High Byte: 0x12 (00010010)
Low Byte:  0x34 (00110100)
```

SPI 전송 순서:
1. High Byte: MSB first → `0 0 0 1 0 0 1 0`
2. Low Byte:  MSB first → `0 0 1 1 0 1 0 0`

## 다음 단계 (Slave 설계)

Slave에서 구현해야 할 기능:
1. SPI Slave 모듈 - 2바이트 수신
2. Slave Controller - 2바이트 재조합 (`{high[5:0], low[7:0]}`)
3. FND Controller 연결

## 주의사항

1. **Tick 주기**
   - 실제: 100ms (master_top.sv)
   - 시뮬레이션: 1ms (master_top_fast.sv)
   - 필요에 따라 tick_gen의 파라미터 조정

2. **SPI 클럭**
   - 현재 1MHz (50 클럭 주기)
   - 필요시 spi_master.sv에서 조정

3. **시뮬레이션 시간**
   - Fast 버전: ~15ms 권장
   - Normal 버전: 긴 시간 소요 (실제 100ms tick)

## 문의/개선사항

- FSM 타이밍 최적화 가능
- SPI 클럭 속도 조정 가능
- Tick 주기 파라미터화 가능
