# SPI Slave System - 설계 문서

## 개요

Master에서 전송한 2바이트 SPI 데이터를 수신하고, 14비트로 재조합하여 FND에 표시하는 시스템입니다.

## 시스템 구조

```
slave_top
├── spi_slave           # SPI 데이터 수신 (1바이트씩)
├── slave_controller    # 2바이트 재조합 (14비트)
└── fnd_controller      # FND 디스플레이
    ├── clk_div
    ├── counter_4
    ├── decoder_2x4
    ├── digit_spliter
    ├── mux_4x1
    └── bcd_decoder
```

## 핵심 동작 원리

### 1. SPI Slave (spi_slave.sv)

**역할**: SCLK rising edge에서 MOSI 데이터를 1비트씩 수신

```
동작:
1. System clk에 SCLK, MOSI, SS 신호 동기화 (2-stage synchronizer)
2. SCLK rising edge 감지
3. MOSI 비트를 shift register에 시프트 (MSB first)
4. 8비트 수신 완료 → done 신호 1 clock pulse 발생
5. SS = HIGH일 때 리셋
```

**주요 특징**:
- System clock 기반 동작 (안전한 클럭 도메인)
- SCLK/MOSI/SS 신호를 system clk에 동기화
- 메타스테이빌리티 방지

**포트**:
```systemverilog
input  logic       clk      // System clock (100MHz)
input  logic       reset
input  logic       sclk     // From master
input  logic       mosi     // From master
output logic       miso     // Not used
input  logic       ss       // From master (active low)
output logic [7:0] rx_data  // Received byte
output logic       done     // Pulse when byte complete
```

### 2. Slave Controller (slave_controller.sv)

**역할**: 2바이트를 수신하여 14비트 데이터로 재조합

```
FSM 상태:
IDLE       → SS가 LOW로 가면 트랜잭션 시작 대기
WAIT_HIGH  → 첫 번째 바이트(High byte) 수신 대기
WAIT_LOW   → 두 번째 바이트(Low byte) 수신 대기
DATA_READY → 14비트 데이터 재조합 & 출력

동작:
1. IDLE: SS falling edge 감지 → WAIT_HIGH
2. WAIT_HIGH: spi_slave done 신호 → high_byte 저장 → WAIT_LOW
3. WAIT_LOW: spi_slave done 신호 → low_byte 저장 → DATA_READY
4. DATA_READY: {high_byte[5:0], low_byte[7:0]} → 14bit counter 출력
5. SS rising edge 감지 → IDLE (트랜잭션 완료)
```

**데이터 재조합**:
```
Master에서 전송:
  High Byte: {2'b00, counter[13:8]}  // 상위 6비트 + 2비트 패딩
  Low Byte:  counter[7:0]             // 하위 8비트

Slave에서 재조합:
  counter[13:0] = {high_byte[5:0], low_byte[7:0]}
```

**포트**:
```systemverilog
input  logic        clk
input  logic        reset
input  logic [7:0]  rx_data      // From spi_slave
input  logic        done         // From spi_slave
input  logic        ss           // For transaction boundary
output logic [13:0] counter      // Reconstructed 14-bit data
output logic        data_valid   // Pulse when new data ready
```

### 3. FND Controller (fnd_controller.sv)

**역할**: 14비트 카운터 값을 4자리 7-segment FND에 표시

**동작**:
- 14비트 카운터를 4자리 10진수로 분해
- 1kHz 주기로 각 자리를 순차적으로 점등 (다이나믹 스캔)
- BCD → 7-segment 변환

## 타이밍 다이어그램

```
Master:
  Counter: 1234 (0x04D2)

  Tick ──┐
         └─┐
           └→ FSM: IDLE → SEND_HIGH → WAIT_HIGH → SEND_LOW → WAIT_LOW → IDLE

  SS: ────┘                                                       └────
          LOW (active)                                           HIGH

  SCLK:   _-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_

  MOSI:   [  0x04 (High)  ][  0xD2 (Low)   ]
          [0 0 0 0 0 1 0 0][1 1 0 1 0 0 1 0]

Slave:
  SS falling edge → Start transaction

  SCLK rising edges → Shift in bits

  After 8 bits → done pulse → high_byte = 0x04
  After 16 bits → done pulse → low_byte = 0xD2

  Combine: counter = {0x04[5:0], 0xD2} = {6'b000100, 8'b11010010} = 14'd1234

  SS rising edge → data_valid pulse → FND updates to "1234"
```

## 클럭 도메인

### System Clock Domain (100MHz)
- spi_slave의 내부 로직
- slave_controller
- fnd_controller
- 모든 sequential 로직

### SCLK Domain (약 1MHz)
- SCLK, MOSI는 외부 신호
- **2-stage synchronizer로 system clk에 동기화**
- 메타스테이빌리티 방지

## 신호 동기화

### 왜 필요한가?
- Master의 SCLK와 Slave의 system clk은 비동기
- 비동기 신호를 직접 사용하면 메타스테이빌리티 발생 가능
- Setup/Hold time violation 가능

### 구현
```systemverilog
// 2-stage synchronizer
logic sclk_sync1, sclk_sync2;

always_ff @(posedge clk) begin
    sclk_sync1 <= sclk;      // First stage
    sclk_sync2 <= sclk_sync1; // Second stage
end

// Use synchronized signal
assign sclk_rising_edge = sclk_sync1 && !sclk_sync2;
```

## 파일 목록

### Slave 모듈
1. **spi_slave.sv** - SPI 수신 모듈
2. **slave_controller.sv** - 2바이트 재조합 컨트롤러
3. **slave_top.sv** - Slave 최상위 모듈
4. **fnd_controller.sv** - FND 제어 및 하위 모듈들

### 테스트
5. **tb_full_system.sv** - Master + Slave 통합 테스트

### 스크립트
6. **run_full_sim.sh** - 전체 시스템 시뮬레이션

## 시뮬레이션 방법

### Full System Test (Master + Slave)

```bash
./run_full_sim.sh
```

### 수동 컴파일 (Icarus Verilog)

```bash
iverilog -g2012 -o sim.vvp \
    tick_gen.sv \
    spi_master.sv \
    spi_upcounter_cu.sv \
    spi_upcounter_dp.sv \
    master_top_fast.sv \
    spi_slave.sv \
    slave_controller.sv \
    fnd_controller.sv \
    slave_top.sv \
    tb_full_system.sv

vvp sim.vvp
gtkwave full_system.vcd
```

### Vivado 시뮬레이션

1. 모든 .sv 파일을 프로젝트에 추가
2. tb_full_system.sv를 시뮬레이션 소스로 설정
3. Run Simulation
4. 파형에서 확인:
   - master_counter vs slave_counter
   - SS 신호 (트랜잭션 경계)
   - sclk, mosi (SPI 통신)
   - slave_data_valid (수신 완료)

## 예상 결과

테스트벤치 출력 예시:
```
[1,100,000 ns] ⚡ MASTER: Tick! Counter = 110, Starting transmission...
[1,100,020 ns] ═══ SPI Transaction #1 START ═══
[1,110,000 ns] First byte received by slave: 0x00
[1,120,000 ns] Second byte received by slave: 0x6E
[1,120,010 ns] ★ SLAVE: New data received! Counter = 110 (0x006E)
[1,120,020 ns] ═══ SPI Transaction #1 END ═══

--- Status Report ---
  Master:  110 | Slave:  110 | Match: YES
  ✓ PASS: Master and Slave counters match!
```

## 검증 포인트

### 기능 검증
- [ ] Slave가 2바이트를 올바르게 수신하는가?
- [ ] 2바이트가 14비트로 올바르게 재조합되는가?
- [ ] Master counter와 Slave counter가 일치하는가?
- [ ] SS 신호로 트랜잭션 경계를 올바르게 감지하는가?
- [ ] FND에 올바른 값이 표시되는가?

### 타이밍 검증
- [ ] SCLK rising edge에서 데이터 수신하는가?
- [ ] SS falling edge에서 트랜잭션 시작하는가?
- [ ] SS rising edge에서 트랜잭션 종료하는가?
- [ ] done 신호가 8비트마다 발생하는가?
- [ ] data_valid 신호가 적절히 발생하는가?

### 에러 처리
- [ ] SS가 중간에 HIGH가 되면 리셋되는가?
- [ ] Reset 신호로 모든 상태가 초기화되는가?

## 파형 분석 포인트

GTKWave나 Vivado에서 확인할 신호들:

### Master 측
- clk, reset
- master_counter[13:0]
- SS (트랜잭션 경계)
- SCLK, MOSI
- Master FSM state

### Slave 측
- slave_counter[13:0]
- spi_rx_data[7:0]
- spi_done
- slave_data_valid
- Slave controller FSM state
- high_byte_reg, low_byte_reg (내부 신호)

### 비교
- master_counter vs slave_counter (일치 여부)

## 최적화 및 개선 가능성

### 현재 구현
- ✅ 안전한 클럭 도메인 크로싱
- ✅ 2-stage synchronizer 사용
- ✅ 명확한 FSM 구조
- ✅ SS 신호로 트랜잭션 경계 감지

### 개선 가능
- **CRC 추가**: 데이터 무결성 검증
- **패리티 비트**: 간단한 에러 검증
- **타임아웃**: 트랜잭션 실패 감지
- **버퍼링**: 여러 트랜잭션 버퍼링
- **Flow control**: Slave busy 신호

## 문제 해결

**Q: Slave counter가 Master와 다릅니다**
A:
1. SS 신호 확인 (LOW 동안 전송, HIGH에서 완료)
2. SCLK 엣지 확인 (rising edge에서 수신)
3. 재조합 로직 확인 ({high[5:0], low[7:0]})

**Q: done 신호가 발생하지 않습니다**
A:
1. SCLK가 토글하는지 확인
2. bit_counter가 증가하는지 확인
3. SS가 LOW인지 확인

**Q: 동기화 문제가 발생합니다**
A:
1. 2-stage synchronizer 확인
2. 클럭 도메인 확인
3. Setup/Hold time 여유 확인

**Q: FND에 아무것도 표시되지 않습니다**
A:
1. slave_counter 값 확인
2. fnd_controller 입력 확인
3. clk_div가 1kHz 생성하는지 확인

## 다음 단계

1. ✅ Master 설계 완료
2. ✅ Slave 설계 완료
3. ✅ Full system 테스트벤치 완료
4. ⏭️ 실제 하드웨어 테스트
5. ⏭️ 에러 처리 추가
6. ⏭️ CRC/패리티 추가 (선택)

## 참고사항

- System clock: 100MHz
- SPI clock (SCLK): 약 1MHz (50 system clks per edge)
- FND refresh rate: 1kHz
- Tick period: 1ms (simulation) / 100ms (real)
