# Basys3 Constraint 파일 가이드

## 개요

SPI Master-Slave 시스템을 Basys3 보드에 구현하기 위한 3가지 constraint 옵션을 제공합니다.

## 파일 목록

1. **basys3_full_system.xdc** - 한 보드에서 Master + Slave 통합 테스트
2. **basys3_master.xdc** - Master 보드용 (두 보드 사용 시)
3. **basys3_slave.xdc** - Slave 보드용 (두 보드 사용 시)

---

## 옵션 1: 한 보드에서 테스트 (권장)

### Top Module
**full_system_top.sv** 사용

### Constraint 파일
**basys3_full_system.xdc** 사용

### 포트 매핑

| 신호 | Basys3 핀 | 설명 |
|------|-----------|------|
| **클럭/리셋** |
| clk | W5 | 100MHz 시스템 클럭 |
| reset | U18 (BTNC) | 중앙 버튼 - 리셋 |
| **Master 제어** |
| i_runstop | T18 (BTNU) | 위 버튼 - Run/Stop |
| i_clear | U17 (BTND) | 아래 버튼 - Clear |
| **FND 출력** |
| fnd_data[7:0] | W7,W6,U8,V8,U5,V5,U7,V7 | 7-segment 데이터 |
| fnd_com[3:0] | U2,U4,V4,W4 | 7-segment 자리 선택 |
| **디버그** |
| master_counter[7:0] | U16,E19,U19,V19,W18,U15,U14,V14 | LED - Master 카운터 하위 8비트 |

### 동작 방식
- Master와 Slave가 하나의 FPGA 내부에서 동작
- SPI 신호는 내부 연결 (외부로 나가지 않음)
- FND에 Slave가 받은 데이터 표시
- LED에 Master 카운터 값 표시

### Vivado 사용법
```tcl
# 1. 프로젝트 생성
create_project full_system ./full_system -part xc7a35tcpg236-1

# 2. 소스 파일 추가
add_files {
    tick_gen.sv
    spi_master.sv
    spi_upcounter_cu.sv
    spi_upcounter_dp.sv
    master_top.sv
    spi_slave.sv
    slave_controller.sv
    fnd_controller.sv
    slave_top.sv
    full_system_top.sv
}

# 3. Constraint 추가
add_files -fileset constrs_1 basys3_full_system.xdc

# 4. Top module 설정
set_property top full_system_top [current_fileset]

# 5. 합성 및 구현
launch_runs synth_1
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream
wait_on_run impl_1

# 6. 비트스트림 프로그램
open_hw_manager
connect_hw_server
open_hw_target
set_property PROGRAM.FILE {./full_system/full_system.runs/impl_1/full_system_top.bit} [get_hw_devices xc7a35t_0]
program_hw_devices [get_hw_devices xc7a35t_0]
```

### 사용 방법
1. BTNC (중앙 버튼): Reset
2. BTNU (위 버튼): Run/Stop - 카운터 시작/정지
3. BTND (아래 버튼): Clear - 카운터 0으로 리셋
4. FND: Slave가 수신한 14비트 값을 4자리로 표시
5. LED: Master 카운터 하위 8비트 표시

---

## 옵션 2: 두 보드 사용

### 필요한 것
- Basys3 보드 2개
- Pmod 케이블 (6핀 이상)
- 또는 점퍼 와이어 4개 (SCLK, MOSI, SS, GND)

### Master 보드

#### Top Module
**master_top.sv** 사용

#### Constraint 파일
**basys3_master.xdc** 사용

#### Pmod JA 핀 매핑
| 신호 | Pmod JA 핀 | Basys3 핀 | 방향 |
|------|------------|-----------|------|
| SCLK | JA1 | J1 | 출력 |
| MOSI | JA2 | L2 | 출력 |
| MISO | JA3 | J2 | 입력 (현재 미사용) |
| SS | JA4 | G2 | 출력 |
| GND | GND | - | - |

#### 포트 매핑
| 신호 | Basys3 핀 | 설명 |
|------|-----------|------|
| clk | W5 | 100MHz |
| reset | U18 (BTNC) | 리셋 |
| i_runstop | T18 (BTNU) | Run/Stop |
| i_clear | U17 (BTND) | Clear |
| o_counter[13:0] | LED[13:0] | 카운터 값 표시 |

### Slave 보드

#### Top Module
**slave_top.sv** 사용

#### Constraint 파일
**basys3_slave.xdc** 사용

#### Pmod JA 핀 매핑
| 신호 | Pmod JA 핀 | Basys3 핀 | 방향 |
|------|------------|-----------|------|
| SCLK | JA1 | J1 | 입력 |
| MOSI | JA2 | L2 | 입력 |
| MISO | JA3 | J2 | 출력 (현재 미사용) |
| SS | JA4 | G2 | 입력 |
| GND | GND | - | - |

#### 포트 매핑
| 신호 | Basys3 핀 | 설명 |
|------|-----------|------|
| clk | W5 | 100MHz |
| reset | U18 (BTNC) | 리셋 |
| fnd_data[7:0] | W7~V7 | 7-segment |
| fnd_com[3:0] | U2~W4 | 7-segment COM |
| o_counter[13:0] | LED[13:0] | 수신 값 표시 |
| o_data_valid | LED14 | 새 데이터 수신 표시 |

### 연결 방법

#### Pmod 케이블 사용
```
Master Pmod JA ←→ Slave Pmod JA (1:1 연결)
```

#### 점퍼 와이어 사용
```
Master JA1 (J1) ──→ Slave JA1 (J1)  [SCLK]
Master JA2 (L2) ──→ Slave JA2 (L2)  [MOSI]
Master JA4 (G2) ──→ Slave JA4 (G2)  [SS]
Master GND      ──→ Slave GND       [GND - 공통 접지 필수!]
```

**⚠️ 중요: GND(공통 접지) 연결 필수!**

### Vivado 사용법

**Master 보드:**
```tcl
create_project master ./master -part xc7a35tcpg236-1
add_files {tick_gen.sv spi_master.sv spi_upcounter_cu.sv spi_upcounter_dp.sv master_top.sv}
add_files -fileset constrs_1 basys3_master.xdc
set_property top master_top [current_fileset]
# 합성 및 프로그램
```

**Slave 보드:**
```tcl
create_project slave ./slave -part xc7a35tcpg236-1
add_files {spi_slave.sv slave_controller.sv fnd_controller.sv slave_top.sv}
add_files -fileset constrs_1 basys3_slave.xdc
set_property top slave_top [current_fileset]
# 합성 및 프로그램
```

---

## 동작 확인

### 정상 동작 시나리오

1. **한 보드 테스트**
   - Reset (BTNC)
   - Run/Stop (BTNU) 누름
   - FND에 카운터 증가하는 것 표시 (0000 → 0001 → 0002 ...)
   - LED에도 동일한 값의 하위 8비트 표시

2. **두 보드 테스트**
   - 두 보드 모두 Reset
   - Master 보드: Run/Stop (BTNU) 누름
   - Master LED: 카운터 증가 표시
   - Slave FND: Master와 동일한 값 표시
   - Slave LED14: 새 데이터 수신 시 깜빡임

### 디버깅

**FND에 아무것도 안 나옴:**
- Slave reset 확인
- SPI 연결 확인 (두 보드 사용 시)
- Master가 동작 중인지 확인 (LED 확인)

**Master와 Slave 값이 다름:**
- GND 연결 확인 (두 보드 사용 시)
- SCLK 연결 확인
- SS 연결 확인
- Slave reset 후 재시작

**카운터가 너무 빠름:**
- master_top.sv의 tick_gen 주기 확인
- TICK_PERIOD_MS를 더 크게 (예: 1000ms = 1초)

---

## Pmod JA 핀아웃 참고

```
Basys3 Pmod JA (상단 커넥터)

Top Row:    JA1  JA2  JA3  JA4  (신호)
            J1   L2   J2   G2

Bottom Row: JA7  JA8  JA9  JA10 (GND/VCC)
            H1   K2   H2   G3
```

**핀 용도:**
- JA1-4 (상단): 신호선
- JA7,9 (하단): GND
- JA8,10 (하단): VCC (3.3V)

---

## 타이밍 파라미터 조정

### Tick 주기 변경
**파일:** tick_gen.sv 인스턴스 (master_top.sv)

```systemverilog
// 100ms (기본값)
tick_gen #(.TICK_PERIOD_MS(100)) U_TICK_GEN (...)

// 1초로 변경
tick_gen #(.TICK_PERIOD_MS(1000)) U_TICK_GEN (...)

// 10ms로 변경 (빠른 카운트)
tick_gen #(.TICK_PERIOD_MS(10)) U_TICK_GEN (...)
```

### SPI 클럭 속도 변경
**파일:** spi_master.sv

```systemverilog
// 현재: 1MHz (50 system clocks per edge)
if (sclk_counter_reg == 49) begin

// 2MHz로 변경
if (sclk_counter_reg == 24) begin

// 500kHz로 변경
if (sclk_counter_reg == 99) begin
```

---

## 리소스 사용량 (예상)

### 한 보드 (Full System)
- LUT: ~500
- FF: ~300
- BRAM: 0
- DSP: 0

### Master만
- LUT: ~250
- FF: ~150

### Slave만
- LUT: ~300
- FF: ~180

Basys3 (XC7A35T) 리소스:
- LUT: 20,800 (충분함)
- FF: 41,600 (충분함)

---

## 추가 개선 사항

### FND 밝기 조정
fnd_controller.sv의 clk_div 주파수 조정:
```systemverilog
// 현재: 1kHz refresh
parameter F_COUNT = 100_000_000 / 1_000;

// 더 밝게: 2kHz
parameter F_COUNT = 100_000_000 / 2_000;
```

### Counter 범위 변경
14비트 = 0~16383

더 큰 범위가 필요하면:
- counter를 16비트로 확장
- High/Low byte 분할 로직 수정

---

## 문의사항

각 옵션의 장단점:

**옵션 1 (한 보드):**
- ✅ 간단함, 케이블 불필요
- ✅ 디버깅 쉬움
- ❌ 실제 SPI 통신 확인 불가

**옵션 2 (두 보드):**
- ✅ 실제 SPI 통신 확인 가능
- ✅ 실제 하드웨어 인터페이스 학습
- ❌ 보드 2개 필요
- ❌ 연결 오류 가능성

**권장:** 먼저 옵션 1로 로직 검증 → 옵션 2로 실제 통신 테스트
