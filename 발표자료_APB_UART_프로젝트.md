# APB 기반 UART 설계 및 RISC-V 연동 프로젝트
## 발표 자료

---

## 1. 프로젝트 개요

### 1.1 프로젝트 목표
- **APB 버스 기반 UART 주변장치 설계**
- **RISC-V 32I 프로세서와 통합**
- **PC ↔ FPGA 양방향 통신 구현**
- **Class 기반 SystemVerilog Verification**

### 1.2 테스트 시나리오
1. **PC → FPGA**: 텍스트 데이터 전송 → LED/FND로 수신 표시
2. **FPGA → PC**: 주기적으로 상태 데이터 전송 → PC 모니터링

### 1.3 사용 보드
- **Basys-3 FPGA Board** (Xilinx Artix-7)
- 100MHz 시스템 클럭
- UART: 9600 baud rate

---

## 2. 시스템 아키텍처

### 2.1 전체 시스템 구조
```
┌─────────────────────────────────────────────────────┐
│                    MCU (최상위)                      │
│  ┌──────────────┐      ┌─────────────────────────┐ │
│  │  RISC-V CPU  │─────►│    APB Master           │ │
│  │  (RV32I)     │      │  (Decoder + Mux)        │ │
│  └──────────────┘      └──────┬──────────────────┘ │
│         │                     │ APB Bus            │
│    ┌────▼────┐         ┌──────▼─────────────────┐ │
│    │   ROM   │         │  APB Slaves:           │ │
│    │ (code)  │         │  - RAM                 │ │
│    └─────────┘         │  - UART_Periph ◄─► PC │ │
│                        │  - FND_Periph          │ │
│                        │  - GPIO/GPI/GPO        │ │
│                        └────────────────────────┘ │
└─────────────────────────────────────────────────────┘
```

### 2.2 메모리 맵 (Address Mapping)
| 주소 범위 | 주변장치 | 설명 |
|----------|---------|------|
| `0x1000_0xxx` | RAM | 데이터 메모리 |
| `0x1000_1xxx` | GPO | General Purpose Output |
| `0x1000_2xxx` | GPI | General Purpose Input |
| `0x1000_3xxx` | GPIO | General Purpose I/O |
| `0x1000_4xxx` | **UART** | **UART 주변장치 (핵심)** |
| `0x1000_5xxx` | FND | 7-Segment Display |

---

## 3. APB 버스 설계

### 3.1 APB 프로토콜 개요
- **AMBA APB (Advanced Peripheral Bus)**: ARM의 저속 주변장치용 버스
- **장점**: 간단한 인터페이스, 낮은 전력 소비
- **3단계 프로토콜**: IDLE → SETUP → ACCESS

### 3.2 APB 마스터 동작 (APB_Master.sv)

#### 상태 머신
```
IDLE: transfer 신호 대기
  ↓ (transfer=1)
SETUP: PSEL=1, PADDR/PWRITE/PWDATA 설정
  ↓
ACCESS: PENABLE=1, PREADY 대기
  ↓ (PREADY=1)
IDLE: 트랜잭션 완료
```

#### 주요 신호
- **PADDR[31:0]**: 주소
- **PWRITE**: 쓰기(1) / 읽기(0)
- **PWDATA[31:0]**: 쓰기 데이터
- **PRDATA[31:0]**: 읽기 데이터
- **PSEL**: 슬레이브 선택
- **PENABLE**: Enable 신호
- **PREADY**: 슬레이브 준비 신호

#### 디코더 로직 (APB_Master.sv:154-163)
```systemverilog
casex (sel)
    32'h1000_0xxx: PSEL_RAM  = 1
    32'h1000_1xxx: PSEL_GPO  = 1
    32'h1000_2xxx: PSEL_GPI  = 1
    32'h1000_3xxx: PSEL_GPIO = 1
    32'h1000_4xxx: PSEL_UART = 1  // ← UART 선택
    32'h1000_5xxx: PSEL_FND  = 1
endcase
```

---

## 4. UART 주변장치 설계 (핵심)

### 4.1 UART_Periph 구조
```
┌─────────────────────────────────────────────────┐
│            UART_Periph Module                   │
│                                                 │
│  APB Interface                                  │
│  ┌──────────────────────┐                      │
│  │ APB_SlaveIntf_UART   │ ◄─── APB Bus         │
│  └──────┬───────┬───────┘                      │
│         │       │                               │
│    ┌────▼──┐ ┌─▼─────┐                        │
│    │TX FIFO│ │RX FIFO│                        │
│    │(4byte)│ │(4byte)│                        │
│    └───┬───┘ └───▲───┘                        │
│        │         │                             │
│    ┌───▼──┐  ┌──┴────┐                        │
│    │uart_tx│ │uart_rx│                        │
│    └───┬───┘ └──▲────┘                        │
│        │        │                              │
│        └────────┴──────► baud_tick_gen        │
│                          (9600 baud)           │
│         tx ─────────────────►  (to PC)        │
│         rx ◄────────────────── (from PC)      │
└─────────────────────────────────────────────────┘
```

### 4.2 레지스터 맵 (UART_Periph)
| 오프셋 | 이름 | 설명 | R/W |
|--------|------|------|-----|
| 0x00 | USR | UART Status Register | R |
| 0x04 | - | Reserved | - |
| 0x08 | TDR | Transmit Data Register | W |
| 0x0C | RDR | Receive Data Register | R |

#### USR (Status Register) 비트 필드
```
[3]: RX FIFO Full
[2]: TX FIFO Empty
[1]: TX FIFO Not Full (쓰기 가능)
[0]: RX FIFO Not Empty (읽기 가능)
```

### 4.3 UART TX/RX 동작

#### TX 경로 (APB → UART TX)
1. CPU가 TDR(0x08)에 데이터 쓰기 → APB Write
2. APB_SlaveIntf_UART가 TX FIFO에 push (we_TX=1)
3. TX FIFO가 비어있지 않으면 uart_tx 모듈이 자동 전송
4. uart_tx: START bit → 8 data bits → STOP bit 전송

#### RX 경로 (UART RX → APB)
1. uart_rx가 rx 핀에서 데이터 수신 (START → 8 bits → STOP)
2. 수신 완료 시 RX FIFO에 push (rx_done=1)
3. CPU가 RDR(0x0C) 읽기 → RX FIFO pop

### 4.4 FIFO 설계 (4 바이트 깊이)
- **Write Pointer (wptr)**: 쓰기 위치
- **Read Pointer (rptr)**: 읽기 위치
- **Empty Flag**: wptr == rptr
- **Full Flag**: wptr + 1 == rptr
- **동시 읽기/쓰기 지원**

### 4.5 Baud Rate Generator
```systemverilog
// 9600 baud, 100MHz 클럭
BAUD_COUNT = 100_000_000 / (9600 * 16) = 651
// 16x 오버샘플링으로 정확한 비트 타이밍
```

---

## 5. RISC-V 통합

### 5.1 CPU_RV32I 구조
- **Control Unit**: FSM 기반 명령어 디코딩
- **Data Path**: ALU, 레지스터 파일, PC
- **버스 인터페이스**: APB Master와 연결

### 5.2 UART 통신 예제 (C 코드 개념)

#### 송신 예제
```c
// UART 상태 확인
while (!(*(volatile uint32_t*)0x10004000 & 0x2));  // TX FIFO Full 대기

// 데이터 전송
*(volatile uint32_t*)0x10004008 = 'H';  // TDR에 쓰기
```

#### 수신 예제
```c
// 데이터 수신 대기
while (!(*(volatile uint32_t*)0x10004000 & 0x1));  // RX Ready 대기

// 데이터 읽기
uint8_t data = *(volatile uint32_t*)0x1000400C;  // RDR 읽기
```

### 5.3 테스트 프로그램 동작
1. **초기화**: UART, FND 초기화
2. **수신 대기**: PC에서 문자 수신
3. **FND 표시**: 수신한 문자 코드를 FND에 표시
4. **상태 송신**: 주기적으로 FPGA 상태를 PC로 전송

---

## 6. Class 기반 Verification

### 6.1 검증 환경 구조 (tb_verification.sv)
```
┌──────────────────────────────────────────────┐
│          Environment (환경)                   │
│  ┌────────────┐      ┌──────────────┐       │
│  │ Generator  │─────►│   Driver     │       │
│  │ (자극생성)  │      │  (APB Write/ │       │
│  └────────────┘      │   UART RX)   │       │
│                      └──────┬───────┘       │
│                             │               │
│                      ┌──────▼───────┐       │
│                      │     DUT      │       │
│                      │ (UART_Periph)│       │
│                      └──────┬───────┘       │
│                             │               │
│  ┌────────────┐      ┌─────▼────────┐      │
│  │ Scoreboard │◄─────│   Monitor    │      │
│  │ (결과검증)  │      │  (UART TX/   │      │
│  └────────────┘      │   APB Read)  │      │
│                      └──────────────┘      │
└──────────────────────────────────────────────┘
```

### 6.2 주요 Class 설명

#### Transaction Class (tb_verification.sv:27-43)
```systemverilog
class transaction;
    rand bit [7:0] data;           // 전송 데이터
    rand bit is_tx;                // TX(1) / RX(0) 테스트 구분
    bit [7:0] received_data;       // UART로 수신한 데이터
    bit [7:0] read_data;           // APB로 읽은 데이터

    constraint data_range {
        data inside {[8'h20:8'h7E]};  // 출력 가능한 ASCII만
    }
endclass
```

#### Generator Class (tb_verification.sv:46-67)
- **역할**: 랜덤 트랜잭션 생성
- **기능**: Transaction 객체 생성 및 Driver로 전달

#### Driver Class (tb_verification.sv:70-169)
- **역할**: DUT에 자극 인가
- **TX 테스트**: APB Write로 TDR에 데이터 쓰기
- **RX 테스트**: UART RX 핀으로 데이터 전송

#### Monitor Class (tb_verification.sv:172-265)
- **역할**: DUT 출력 관찰
- **TX 테스트**: UART TX 핀에서 데이터 수신
- **RX 테스트**: APB Read로 RDR에서 데이터 읽기

#### Scoreboard Class (tb_verification.sv:268-315)
- **역할**: 결과 비교 및 검증
- **기능**: 송신 데이터 vs 수신 데이터 비교
- **통계**: PASS/FAIL 카운트

### 6.3 검증 시나리오

#### TX Path 검증
```
1. Generator: 랜덤 데이터 생성 (예: 0x48 'H')
2. Driver: APB Write 0x10004008 = 0x48
3. DUT: TX FIFO → uart_tx → tx 핀 전송
4. Monitor: tx 핀에서 START-8bits-STOP 수신
5. Scoreboard: 0x48 == 수신 데이터 비교
```

#### RX Path 검증
```
1. Generator: 랜덤 데이터 생성 (예: 0x4C 'L')
2. Driver: UART 프로토콜로 rx 핀에 0x4C 전송
3. DUT: uart_rx → RX FIFO 저장
4. Monitor: APB Read 0x1000400C → 데이터 읽기
5. Scoreboard: 0x4C == 읽은 데이터 비교
```

### 6.4 검증 결과 리포트
```
========================================
========== TEST REPORT =================
========================================
Total Tests : 50
Pass Tests  : 50
Fail Tests  : 0
----------------------------------------
TX Path Tests:
  TX Pass   : 25
  TX Fail   : 0
  TX Total  : 25
----------------------------------------
RX Path Tests:
  RX Pass   : 25
  RX Fail   : 0
  RX Total  : 25
========================================
```

---

## 7. 테스트 시나리오 (FPGA 보드)

### 7.1 하드웨어 구성
```
┌─────────────┐   UART    ┌──────────────────┐
│     PC      │◄─────────►│  Basys-3 FPGA    │
│  (Python/   │  9600bps  │  - RISC-V CPU    │
│   Terminal) │           │  - APB UART      │
└─────────────┘           │  - FND Display   │
                          └──────────────────┘
```

### 7.2 테스트 1: PC → FPGA (수신 표시)
1. **PC 동작**: 텍스트 데이터 전송 (예: "HELLO")
2. **FPGA 동작**:
   - uart_rx가 데이터 수신 → RX FIFO 저장
   - RISC-V CPU가 RDR 읽기
   - 수신 데이터를 FND에 표시 (ASCII 코드)
3. **결과 확인**: FND에 "0072" (H의 ASCII) 표시

### 7.3 테스트 2: FPGA → PC (상태 전송)
1. **FPGA 동작**:
   - 타이머 인터럽트 발생
   - CPU가 상태 데이터 준비 (예: 센서 값)
   - TDR에 데이터 쓰기 → TX FIFO → uart_tx 전송
2. **PC 동작**: 시리얼 터미널에서 수신 데이터 표시
3. **결과 확인**: PC 화면에 "STATUS: OK" 표시

### 7.4 양방향 통신 시나리오
```
Time | PC → FPGA        | FPGA → PC
-----|------------------|------------------
0s   | "START"          | -
1s   | -                | "ACK"
2s   | "READ_SENSOR"    | -
3s   | -                | "TEMP:25C"
4s   | "LED_ON"         | -
5s   | -                | "LED:ON"
```

---

## 8. 주요 설계 포인트

### 8.1 APB 프로토콜 준수
- **Setup 단계**: PSEL=1, PENABLE=0에서 주소/데이터 안정화
- **Access 단계**: PENABLE=1에서 트랜잭션 완료
- **Back-to-back 방지**: IDLE 상태로 복귀 후 다음 전송

### 8.2 FIFO 설계
- **버퍼링**: CPU와 UART 속도 차이 흡수
- **깊이 4**: 짧은 버스트 전송 지원
- **Full/Empty 플래그**: 오버플로우/언더플로우 방지

### 8.3 Baud Rate 정확도
- **100MHz 클럭**: 651 카운트로 9600 baud 생성
- **16x 오버샘플링**: 비트 중심에서 샘플링 (오류 최소화)

### 8.4 검증 커버리지
- **TX/RX 경로 분리 테스트**
- **랜덤 데이터 생성**: Corner case 커버
- **프로토콜 검증**: START/STOP 비트 확인

---

## 9. 발표 시 강조할 점

### 9.1 기술적 강점
1. **표준 프로토콜 사용**: AMBA APB 표준 준수
2. **모듈화 설계**: 재사용 가능한 UART IP
3. **FIFO 버퍼링**: 안정적인 데이터 전송
4. **Class 기반 검증**: 현대적인 검증 방법론

### 9.2 실제 응용
- **임베디드 시스템**: MCU-PC 통신
- **디버깅 인터페이스**: 로그 출력
- **센서 네트워크**: 데이터 수집

### 9.3 확장 가능성
- **다른 Baud Rate 지원**: 파라미터 변경만으로 가능
- **인터럽트 추가**: RX Ready, TX Empty 인터럽트
- **DMA 연동**: 대용량 데이터 전송

---

## 10. 시연 시나리오 (추천)

### 시연 1: 에코 백 (Echo Back)
```
1. PC에서 "TEST" 전송
2. FPGA가 수신 후 즉시 동일 데이터 재전송
3. PC에서 "TEST" 수신 확인
→ 양방향 통신 동작 증명
```

### 시연 2: 실시간 카운터
```
1. FPGA가 1초마다 카운터 값 전송 (0, 1, 2, ...)
2. PC 터미널에 실시간 출력
3. FND에도 동일 값 표시
→ 주기적 상태 전송 증명
```

### 시연 3: 명령어 제어
```
1. PC에서 "LED_ON" 전송 → GPO를 통해 LED 켜짐
2. PC에서 "LED_OFF" 전송 → LED 꺼짐
3. FPGA가 "OK" 응답
→ 제어 시스템 동작 증명
```

---

## 11. 질문 예상 & 답변 준비

### Q1: APB를 선택한 이유는?
**A**: 주변장치는 고속 전송이 불필요하고, APB는 인터페이스가 간단하여 면적/전력 효율이 높습니다. AXI는 고속 전송용이지만 UART는 9600bps로 충분히 느립니다.

### Q2: FIFO 깊이를 4로 선택한 이유는?
**A**: UART는 9600bps로 느리고, RISC-V는 100MHz로 빠르므로 버스트 전송이 짧습니다. 4 바이트면 충분하며, 면적 절약을 위해 최소화했습니다.

### Q3: Verification에서 랜덤 테스트의 장점은?
**A**: 설계자가 예상하지 못한 corner case를 발견할 수 있습니다. 예를 들어 연속된 0xFF, 0x00 같은 특수 패턴도 자동 생성됩니다.

### Q4: 실제 FPGA에서 발생한 문제는?
**A**:
- **클럭 도메인 이슈**: UART와 APB가 동일 클럭이므로 CDC 불필요
- **타이밍 위반**: 100MHz에서 합성 시 타이밍 만족
- **FIFO Full 처리**: USR 레지스터로 Full 확인 후 쓰기

### Q5: 9600 baud를 선택한 이유는?
**A**: 터미널 프로그램 기본값이며, 케이블 길이/노이즈에 강합니다. 115200도 가능하지만 안정성을 위해 9600 선택.

---

## 12. 코드 라인 참조 (발표 시 활용)

### APB Master 상태 전이 (APB_Master.sv:86-115)
```systemverilog
case (state)
    IDLE: if (transfer) state_next = SETUP;
    SETUP: begin
        decoder_en = 1'b1;
        PENABLE = 1'b0;
        state_next = ACCESS;
    end
    ACCESS: begin
        PENABLE = 1'b1;
        if (ready) state_next = IDLE;
    end
endcase
```

### UART TX 상태 머신 (UART_Periph.sv:222-263)
```systemverilog
case (state)
    IDLE: if (tx_start) next = SEND;
    SEND: if (tick) next = START;
    START: // START 비트 전송 (16 tick)
    DATA:  // 8 데이터 비트 전송
    STOP:  // STOP 비트 전송
endcase
```

### APB Slave 인터페이스 (UART_Periph.sv:480-523)
```systemverilog
if (PSEL && PENABLE) begin
    if (PWRITE) begin
        if (PADDR[3:2] == 2'd2) we_next = 1'b1;  // TDR Write
    end else begin
        if (PADDR[3:2] == 2'd3) begin
            PRDATA_next = {24'b0, URD};  // RDR Read
            re_next = 1'b1;              // FIFO Pop
        end
    end
end
```

### Verification Driver (tb_verification.sv:100-115)
```systemverilog
task apb_write(input [3:0] addr, input [31:0] data);
    @(posedge vif.PCLK);
    vif.PSEL = 1;
    vif.PADDR = addr;
    vif.PWDATA = data;
    vif.PWRITE = 1;
    vif.PENABLE = 0;
    @(posedge vif.PCLK);
    vif.PENABLE = 1;  // ACCESS phase
    wait(vif.PREADY == 1);
    @(posedge vif.PCLK);
    vif.PSEL = 0;     // IDLE
endtask
```

---

## 13. 결론

### 13.1 달성 목표
- APB 표준 프로토콜 기반 UART 설계 완료
- RISC-V 32I 프로세서와 성공적 통합
- Class 기반 검증으로 TX/RX 경로 검증 완료
- FPGA 보드에서 PC 통신 동작 확인

### 13.2 배운 점
- **버스 프로토콜**: APB 타이밍 및 디코딩 설계
- **UART 프로토콜**: START/STOP 비트, baud rate 생성
- **FIFO 설계**: 포인터 관리, Full/Empty 플래그
- **SystemVerilog**: Class, interface, randomization

### 13.3 향후 개선 방향
- **인터럽트 추가**: RX 수신 시 CPU에 알림
- **DMA 연동**: 대용량 데이터 자동 전송
- **패리티 비트**: 오류 검출 기능 추가
- **Higher Baud Rate**: 115200bps 지원

---

**END OF PRESENTATION**

---

## 부록: 파일 구조

```
프로젝트 루트/
├── RTL 디자인
│   ├── MCU.sv                  # 최상위 모듈
│   ├── CPU_RV32I.sv           # RISC-V CPU 래퍼
│   ├── ControlUnit.sv         # CPU 제어 유닛
│   ├── DataPath.sv            # CPU 데이터 패스
│   ├── APB_Master.sv          # APB 마스터 (Decoder, Mux)
│   ├── APB_Slave.sv           # APB 슬레이브 인터페이스
│   ├── UART_Periph.sv         # UART 주변장치 (핵심)
│   ├── FND_Periph.sv          # 7-Segment 주변장치
│   ├── GPI.sv / GPO.sv / GPIO.sv  # GPIO 주변장치
│   ├── RAM.sv / ROM.sv        # 메모리
│   └── defines.sv             # 상수 정의
├── 검증 환경
│   ├── tb_verification.sv     # Class 기반 검증 (핵심)
│   ├── tb_APB.sv              # APB 프로토콜 테스트
│   └── tb_test.sv             # 통합 테스트
├── 소프트웨어
│   ├── code.mem               # RISC-V 프로그램 (헥사)
│   └── code2.mem              # 테스트 프로그램 2
└── 제약 파일
    └── Basys-3-Master.xdc     # FPGA 핀 할당
```
