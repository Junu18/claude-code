# SPI Master - 빠른 시작 가이드

## 생성된 파일

### 📁 핵심 모듈 (5개)
```
tick_gen.sv              - Tick 생성기 (100ms 주기)
spi_master.sv            - SPI 1바이트 전송기
spi_upcounter_cu.sv      - 버튼 제어 유닛
spi_upcounter_dp.sv      - 카운터 (14비트)
master_top.sv            - 메인 모듈 (실제 100ms)
master_top_fast.sv       - 빠른 시뮬레이션용 (1ms)
```

### 📁 테스트벤치 (1개)
```
tb_master_fast.sv        - 시뮬레이션 테스트벤치
```

### 📁 문서 (2개)
```
SPI_MASTER_README.md     - 상세 설명서
SPI_QUICK_START.md       - 이 파일
```

## 🎯 핵심 개선사항

### 1. Tick Generator 추가 ✅
```systemverilog
// 문제: 매 클럭마다 전송 시도 → 타이밍 오류
counter_tick <= 1'b1;  // ❌ 잘못됨

// 해결: 100ms마다 한 번만 전송
tick_gen #(.TICK_PERIOD_MS(100)) U_TICK_GEN (
    .clk(clk),
    .reset(reset),
    .tick(counter_tick)  // ✅ 주기적 tick
);
```

### 2. FSM 재설계 ✅
```
기존 (문제있음):
IDLE → WAIT_HI → WAIT_LW

개선 (올바름):
IDLE → SEND_HIGH → WAIT_HIGH → SEND_LOW → WAIT_LOW
      ↑                                          |
      └──────────────────────────────────────────┘
```

### 3. 신호 연결 완료 ✅
- sclk, mosi, miso, ss 모두 연결
- counter_tick을 별도 tick_gen에서 생성
- FSM이 start 신호를 spi_master에 전달

## 🔧 시뮬레이션 방법

### Vivado에서 실행
1. Vivado 프로젝트 생성
2. 다음 파일 추가:
   - tick_gen.sv
   - spi_master.sv
   - spi_upcounter_cu.sv
   - spi_upcounter_dp.sv
   - master_top_fast.sv ← **이것 사용**
   - tb_master_fast.sv
3. `tb_master_fast`를 시뮬레이션 소스로 설정
4. Run Simulation

### ModelSim에서 실행
```bash
vlog -sv tick_gen.sv spi_master.sv spi_upcounter_cu.sv \
         spi_upcounter_dp.sv master_top_fast.sv tb_master_fast.sv

vsim tb_master_fast
run -all
```

### Icarus Verilog에서 실행
```bash
./run_sim.sh fast
gtkwave master_top_fast.vcd
```

## 📊 예상 동작

### 타이밍
```
Time: 0ns
  - Reset
  - Counter = 0
  - State = IDLE

Time: 1000ns
  - Press RUN/STOP button
  - Counter starts incrementing

Time: ~1,100,000ns (1.1ms)
  - First TICK occurs
  - FSM: IDLE → SEND_HIGH
  - SPI transmits High Byte

Time: ~1,110,000ns
  - SPI done
  - FSM: SEND_LOW
  - SPI transmits Low Byte

Time: ~1,120,000ns
  - SPI done
  - FSM: IDLE
  - Wait for next tick...
```

### 데이터 예시
```
Counter = 1234 (decimal) = 0x04D2

High Byte = {2'b00, 0x04D2[13:8]}
          = {2'b00, 6'b000100}
          = 8'b00000100
          = 0x04

Low Byte  = 0x04D2[7:0]
          = 8'b11010010
          = 0xD2

SPI 전송 순서:
1st byte: 0x04 (High)
2nd byte: 0xD2 (Low)
```

## 🎨 파형 확인 포인트

GTKWave 또는 Vivado Waveform에서 확인:

```
그룹 1: Clock & Reset
  - clk
  - reset

그룹 2: Control
  - i_runstop
  - i_clear

그룹 3: Counter
  - o_counter [13:0]

그룹 4: FSM
  - o_state [2:0]
    0=IDLE, 1=SEND_HIGH, 2=WAIT_HIGH, 3=SEND_LOW, 4=WAIT_LOW

그룹 5: Tick
  - counter_tick (내부)

그룹 6: SPI
  - sclk
  - mosi
  - ss
  - spi_start (내부)
  - spi_done (내부)
  - spi_tx_data [7:0] (내부)
```

## ✅ 검증 체크리스트

- [ ] Counter가 RUN/STOP 버튼으로 시작/정지하는가?
- [ ] CLEAR 버튼으로 카운터가 0으로 리셋되는가?
- [ ] 1ms(시뮬레이션)마다 tick이 발생하는가?
- [ ] Tick마다 2바이트 SPI 전송이 발생하는가?
- [ ] FSM 상태가 올바르게 전이하는가?
- [ ] High byte가 먼저, Low byte가 나중에 전송되는가?
- [ ] SPI SCLK이 올바르게 토글하는가?
- [ ] MOSI 데이터가 올바른가?

## 🚀 다음 단계: Slave 설계

Slave 측에서 구현할 것:

1. **spi_slave.sv**
   - sclk 엣지에서 데이터 수신
   - 2바이트 수신 후 done 신호 발생

2. **slave_controller.sv**
   - 2바이트 재조합: `{high_byte[5:0], low_byte[7:0]}`
   - 14비트 데이터 출력

3. **연결**
   ```
   spi_slave → slave_controller → fnd_controller → FND
   ```

## 💡 팁

1. **시뮬레이션 시간 단축**
   - `master_top_fast.sv` 사용 (1ms tick)
   - 원하면 더 짧게: `TICK_PERIOD_MS` 파라미터 수정

2. **디버깅**
   - `o_counter` 포트로 현재 카운터 값 확인
   - `o_state` 포트로 FSM 상태 확인 (fast 버전만)

3. **실제 하드웨어 배포**
   - `master_top.sv` 사용 (100ms tick)
   - Top module의 포트를 제약 파일에 매핑

## 📞 문제 해결

**Q: tick이 너무 자주/드물게 발생해요**
A: `tick_gen` 인스턴스의 `TICK_PERIOD_MS` 파라미터 조정

**Q: SPI 클럭이 너무 빠르거나 느려요**
A: `spi_master.sv`의 `sclk_counter_reg == 49` 값 조정
   - 작게 → 빠름
   - 크게 → 느림

**Q: 시뮬레이션이 너무 오래 걸려요**
A: `master_top_fast.sv` 사용하고 테스트벤치 시간 단축

**Q: FSM이 IDLE에서 멈춰요**
A: `counter_tick` 신호 확인 → tick_gen 동작 확인
