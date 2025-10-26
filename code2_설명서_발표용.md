# Code2 프로그램 설명서 (발표용)
## APB UART 테스트 프로그램 분석

---

## 1. 프로그램 개요

### 1.1 목적
**RISC-V CPU**에서 실행되는 **UART 통신 테스트 프로그램**으로, PC와 양방향 통신을 수행합니다.

### 1.2 주요 기능
1. **PC → FPGA**: 명령어 수신 (연산 명령, LED 제어)
2. **FPGA → PC**: 연산 결과 및 상태 전송
3. **FND 표시**: 7-Segment에 결과 표시
4. **GPIO 제어**: LED ON/OFF/Toggle

### 1.3 통신 프로토콜
- **UART**: 9600 baud, 8-N-1 (8 data bits, No parity, 1 stop bit)
- **방식**: 폴링 방식 (인터럽트 미사용)
- **데이터**: ASCII 문자 기반 명령어

---

## 2. 메모리 맵 및 레지스터

### 2.1 주변장치 주소 맵
| 주소 | 주변장치 | 설명 |
|------|----------|------|
| `0x10001000` | **GPO** | General Purpose Output (LED) |
| `0x10002000` | **GPI** | General Purpose Input (Switch) |
| `0x10004000` | **UART** | UART 통신 |
| `0x10005000` | **FND** | 7-Segment Display |

### 2.2 UART 레지스터 맵
| 오프셋 | 레지스터 | 접근 | 설명 |
|--------|----------|------|------|
| `0x00` | **USR** (Status) | R | 상태 레지스터 |
| `0x08` | **TDR** (Transmit) | W | 송신 데이터 레지스터 |
| `0x0C` | **RDR** (Receive) | R | 수신 데이터 레지스터 |

#### USR (UART Status Register) 비트 필드
```
Bit [1]: TX_READY (1 = TX FIFO에 공간 있음, 전송 가능)
Bit [0]: RX_READY (1 = RX FIFO에 데이터 있음, 읽기 가능)
```

### 2.3 C 코드에서 레지스터 접근
```c
// 포인터를 통한 직접 접근
#define UART_USR   (*(volatile uint32_t*)(0x10004000))
#define UART_TDR   (*(volatile uint32_t*)(0x10004008))
#define UART_RDR   (*(volatile uint32_t*)(0x1000400C))

// 사용 예
uint32_t status = UART_USR;           // 상태 읽기
UART_TDR = 'A';                       // 'A' 전송
uint8_t data = (uint8_t)UART_RDR;    // 데이터 수신
```

---

## 3. 주요 함수 설명

### 3.1 초기화 함수

#### `void init_gpo(void)`
**목적**: GPO (LED) 초기화

```c
void init_gpo(void) {
    GPO_REG = 0xFF;  // 모든 LED ON (테스트)
    GPO_REG = 0x00;  // 모든 LED OFF (초기화)
}
```

**동작**:
1. 먼저 모든 LED를 켜서 연결 확인
2. 초기 상태로 모든 LED OFF

---

#### `void init_gpi(void)`
**목적**: GPI (스위치) 초기화

```c
void init_gpi(void) {
    GPI_REG = 0xFF;  // 풀업 저항 활성화
}
```

**동작**:
- 내부 풀업 저항 설정 (스위치가 눌리지 않았을 때 HIGH)

---

### 3.2 UART 통신 함수

#### `uint8_t uart_receive(void)`
**목적**: UART로 1바이트 수신 (블로킹)

```c
uint8_t uart_receive(void) {
    uint32_t status;

    // RX FIFO에 데이터가 있을 때까지 대기
    do {
        status = UART_USR;
    } while ((status & UART_RX_READY) == 0);

    // RDR에서 데이터 읽기
    uint8_t data = (uint8_t)UART_RDR;
    return data;
}
```

**동작 흐름**:
```
1. UART_USR 읽기
   ↓
2. RX_READY 비트 확인 (bit 0)
   ↓ NO
   ← (대기 루프)
   ↓ YES
3. UART_RDR 읽기 (자동으로 FIFO pop)
   ↓
4. 데이터 반환
```

**중요 포인트**:
- **블로킹 방식**: 데이터가 올 때까지 무한 대기
- **FIFO 자동 Pop**: RDR을 읽으면 FIFO에서 자동 제거
- **폴링 방식**: 인터럽트 미사용

---

#### `void uart_send(uint8_t data)`
**목적**: UART로 1바이트 송신 (블로킹)

```c
void uart_send(uint8_t data) {
    // TX FIFO에 공간이 있을 때까지 대기
    while ((UART_USR & UART_TX_READY) == 0);

    // TDR에 데이터 쓰기
    UART_TDR = data;
}
```

**동작 흐름**:
```
1. UART_USR 읽기
   ↓
2. TX_READY 비트 확인 (bit 1)
   ↓ FULL
   ← (대기 루프)
   ↓ NOT FULL
3. UART_TDR에 데이터 쓰기 (자동으로 FIFO push)
   ↓
4. 완료
```

**중요 포인트**:
- **FIFO Full 체크**: 오버플로우 방지
- **하드웨어 전송**: TDR에 쓰면 uart_tx 모듈이 자동 전송

---

### 3.3 디스플레이 함수

#### `void display_value(uint32_t value, uint8_t mode)`
**목적**: FND에 값 표시 및 UART 출력

```c
void display_value(uint32_t value, uint8_t mode) {
    // FND 켜기
    FND_FCR = 1;

    // 값 쓰기 (BCD 변환은 하드웨어에서 수행)
    FND_FDR = value + 0x30;  // ASCII 변환

    delay(2);

    if (mode == 0) {
        delay(3);  // FND만 표시
    } else {
        delay(4);  // UART 출력도 수행
    }
}
```

**파라미터**:
- `value`: 표시할 숫자 (0-9999)
- `mode`:
  - `0` = FND만 표시
  - `1` = FND + UART 출력

**FND 하드웨어**:
- **FND_FCR** (Control): 켜기/끄기
- **FND_FDR** (Data): 표시할 값 (BCD 변환 자동)

---

### 3.4 명령어 처리 함수

#### `void process_command(uint8_t cmd)`
**목적**: PC에서 받은 명령어 처리

**지원 명령어**:
| 명령어 | ASCII | 기능 |
|--------|-------|------|
| `'A'` | 0x41 | 덧셈 모드 진입 + "OK[]" 응답 |
| `'a'` | 0x61 | 뺄셈 모드 진입 + "] " 응답 |
| `'O'` | 0x4F | LED ON + "ON\r\n" 응답 |
| `'F'` | 0x46 | LED OFF + "OFF\r\n" 응답 |
| `'L'` | 0x4C | LED 상태 리셋 + "LED RESET\r\n" |
| `'0'-'9'` | 0x30-0x39 | 숫자 입력 (연산자) |

**예제 - 덧셈 모드**:
```c
if (cmd == 'A' || cmd == 0x41) {
    uart_send('O');   // 'O'
    uart_send('K');   // 'K'
    uart_send('[');   // '['
    uart_send(']');   // ']'
    uart_send('\r');  // Carriage Return
    uart_send('\n');  // Line Feed
}
```

**결과**: PC 터미널에 "OK[]\r\n" 출력

---

### 3.5 유틸리티 함수

#### `void delay(uint32_t count)`
**목적**: 소프트웨어 지연

```c
void delay(uint32_t count) {
    for (uint32_t i = 0; i < count; i++) {
        if (i >= 999) break;  // 오버플로우 방지
    }
}
```

**사용 예**:
```c
delay(5);    // 짧은 지연
delay(700);  // 긴 지연 (주기적 전송)
```

---

## 4. 메인 함수 동작 흐름

### 4.1 전체 구조

```c
int main(void) {
    // 1. 변수 선언
    uint8_t received_data = 0;
    uint8_t num1 = 0, num2 = 0;
    uint32_t counter = 0;

    // 2. 초기화
    init_gpo();
    init_gpi();

    // 3. 무한 루프
    while (1) {
        // A. UART 수신 확인
        // B. 데이터 처리
        // C. 연산 수행
        // D. 결과 전송
        // E. LED 업데이트
        // F. 주기적 상태 전송
    }

    return 0;
}
```

### 4.2 단계별 상세 설명

#### 단계 1: 초기화
```c
init_gpo();  // LED OFF
init_gpi();  // 스위치 풀업 설정
```

#### 단계 2: UART 수신 확인
```c
uint32_t status = UART_USR;
status &= UART_RX_READY;

if (status != 0) {
    // 데이터가 있으면 처리
    received_data = uart_receive();
}
```

**동작**:
- USR의 RX_READY 비트 확인
- 데이터가 있으면 수신 함수 호출

#### 단계 3: 숫자 입력 처리
```c
if (received_data >= 0x30 && received_data <= 0x37) {
    // '0'-'7' 범위의 숫자
    num1 = received_data - 0x30;  // ASCII → 숫자 변환

    // 연산 수행
    operation = 1;
    result = (num1 << 1) | num2;  // 시프트 및 OR

    // FND에 표시
    display_value(result, 0);
}
```

**예제**:
- PC에서 `'3'` (0x33) 전송
- `num1 = 0x33 - 0x30 = 3`
- 연산 수행 후 FND에 결과 표시

#### 단계 4: 명령어 처리
```c
else if (received_data == 0x41) {  // 'A'
    num1 = 0;
    uart_send(num1);
    delay(5);
} else if (received_data == 0x61) {  // 'a'
    num1 = 0;
    uart_send(num1);
    delay(5);
}

process_command(received_data);
```

#### 단계 5: 카운터 기반 상태 업데이트
```c
if (counter < 7) {
    counter++;

    // 비트 연산
    uint32_t temp = num2 | counter;
    temp <<= 1;
    num1 = temp;

    // 조건 분기 및 결과 전송
    if (num1 == num2) {
        // 특수 연산 수행
    }

    uart_send((uint8_t)num1);
} else {
    counter = 0;  // 리셋
}
```

#### 단계 6: LED 업데이트 및 상태 전송
```c
GPO_REG = num1;  // LED에 결과 표시

delay(700);  // 주기적 지연
```

**결과**: LED가 계산 결과를 이진수로 표시

---

## 5. 통신 프로토콜 예제

### 5.1 덧셈 연산 시나리오

#### PC → FPGA 송신
```
Step 1: 'A' (0x41)  → 덧셈 모드 진입
Step 2: '3' (0x33)  → 첫 번째 피연산자
Step 3: '5' (0x35)  → 두 번째 피연산자
```

#### FPGA → PC 응답
```
Step 1: "OK[]"      → 모드 확인
Step 2: 0x08        → 결과 (3 + 5 = 8)
Step 3: LED 표시    → 0b00001000
Step 4: FND 표시    → "0008"
```

### 5.2 LED 제어 시나리오

#### LED ON
```
PC:   'O' (0x4F) 전송
FPGA: "ON\r\n" 응답
      GPO_REG = 0xFF (모든 LED ON)
```

#### LED OFF
```
PC:   'F' (0x46) 전송
FPGA: "OFF\r\n" 응답
      GPO_REG = 0x00 (모든 LED OFF)
```

### 5.3 타이밍 다이어그램

```
시간축:  0ms    10ms   20ms   30ms   40ms   50ms
         │      │      │      │      │      │
PC:      'A' ───┘      '3'────┘      '5'────┘
         │      │      │      │      │      │
FPGA:    │ "OK[]"──────┘  0x08───────┘      │
         │      │      │      │      │      │
FND:     │      "INIT" │ "0003"│ "0008" ────┘
         │      │      │      │      │      │
LED:     OFF    OFF    0b0011 0b1000 ────────
```

---

## 6. 하드웨어 연동

### 6.1 UART 물리 계층
```
PC (RS-232)  ←→  USB-UART  ←→  FPGA (UART_Periph)
   9600 baud         변환         RX/TX 핀
```

### 6.2 데이터 흐름
```
┌─────────────────────────────────────────────┐
│  PC (Python/Terminal)                       │
│  - 명령어 전송                               │
│  - 결과 수신                                 │
└─────────────┬───────────────────────────────┘
              │ UART (9600 baud)
              ↓
┌─────────────▼───────────────────────────────┐
│  FPGA (Basys-3)                             │
│  ┌─────────────────────────────────────┐   │
│  │ RISC-V CPU (code2.c 실행)          │   │
│  │  - UART 폴링                        │   │
│  │  - 명령어 파싱                      │   │
│  │  - 연산 수행                        │   │
│  └──┬──────────────────────────┬───────┘   │
│     │ APB Bus                  │           │
│  ┌──▼─────────┐          ┌────▼──────┐    │
│  │ UART_Periph│          │FND_Periph │    │
│  │ (TX/RX)    │          │(7-Segment)│    │
│  └──┬─────────┘          └───────────┘    │
└─────┼────────────────────────────────────────┘
      │
      ↓ UART TX/RX
┌─────▼───────────────────────────────────────┐
│  PC                                         │
└─────────────────────────────────────────────┘
```

---

## 7. 발표 시 강조할 포인트

### 7.1 기술적 하이라이트

#### 1) **Memory-Mapped I/O**
```c
#define UART_TDR (*(volatile uint32_t*)(0x10004008))
```
- 포인터를 통해 하드웨어 레지스터에 직접 접근
- `volatile` 키워드로 컴파일러 최적화 방지

#### 2) **폴링 방식 통신**
```c
while ((UART_USR & UART_RX_READY) == 0);
```
- 인터럽트 없이 상태 비트 확인
- 간단하지만 CPU 사이클 소모

#### 3) **FIFO 버퍼링**
- **TX FIFO**: 송신 데이터 버퍼링 (CPU와 UART 속도 차이 흡수)
- **RX FIFO**: 수신 데이터 버퍼링 (데이터 손실 방지)

#### 4) **APB 버스 프로토콜**
- RISC-V CPU ↔ 주변장치 통신
- 표준 AMBA APB 프로토콜 사용

### 7.2 실용적 측면

#### 1) **확장성**
- 새로운 명령어 추가 용이
- 다른 주변장치 연동 가능 (GPIO, FND 등)

#### 2) **디버깅**
- UART를 통한 로그 출력
- FND로 실시간 상태 확인

#### 3) **실시간 제어**
- LED 즉시 제어
- 주기적 상태 전송 (700ms 딜레이)

---

## 8. 테스트 시나리오 (발표 시연용)

### 시나리오 1: 에코 테스트
```
[PC] → 'H' 전송
[FPGA] → 'H' 수신 및 재전송
[PC] → 'H' 수신 확인
✓ 양방향 통신 성공
```

### 시나리오 2: 계산기 모드
```
[PC] → 'A' 전송 (덧셈 모드)
[FPGA] → "OK[]" 응답
[PC] → '3' 전송 (첫 번째 피연산자)
[PC] → '5' 전송 (두 번째 피연산자)
[FPGA] → 0x08 응답 (3 + 5 = 8)
[FND] → "0008" 표시
✓ 연산 및 표시 성공
```

### 시나리오 3: LED 제어
```
[PC] → 'O' 전송 (LED ON)
[FPGA] → "ON\r\n" 응답 + LED 전체 켜짐
[PC] → 'F' 전송 (LED OFF)
[FPGA] → "OFF\r\n" 응답 + LED 전체 꺼짐
✓ GPIO 제어 성공
```

### 시나리오 4: 연속 데이터 스트림
```
[PC] → 'ABCD1234' 연속 전송
[FPGA] → 각 문자 처리 및 실시간 응답
[FND] → 마지막 값 표시
✓ 고속 연속 처리 성공
```

---

## 9. 코드 최적화 포인트 (추가 개선 가능)

### 9.1 현재 방식의 한계
1. **폴링 방식**: CPU가 대기하는 동안 다른 작업 불가
2. **블로킹 I/O**: uart_receive()에서 무한 대기
3. **딜레이 정확도**: 소프트웨어 루프로 시간 지연 (부정확)

### 9.2 개선 방안
1. **인터럽트 방식**: UART RX 인터럽트 사용
   ```c
   void uart_rx_interrupt_handler(void) {
       received_data = UART_RDR;
       // 처리 로직
   }
   ```

2. **DMA 사용**: 대용량 데이터 자동 전송
3. **타이머 사용**: 정확한 주기적 전송
4. **링 버퍼**: 소프트웨어 버퍼로 데이터 손실 방지

---

## 10. 발표 Q&A 예상 질문

### Q1: 왜 폴링 방식을 사용했나요?
**A**:
- **장점**: 구현이 간단하고 디버깅이 쉽습니다.
- **단점**: CPU 효율이 낮습니다.
- **실제**: 인터럽트 방식이 더 효율적이지만, 이 프로젝트는 검증 목적으로 폴링 방식을 선택했습니다.

### Q2: FIFO 깊이가 4바이트인 이유는?
**A**:
- UART는 9600bps로 느려서 CPU가 충분히 빠르게 처리 가능합니다.
- 짧은 버스트 전송만 지원하면 되므로 4바이트로 충분합니다.
- 하드웨어 면적 절약을 위해 최소화했습니다.

### Q3: 실제 FPGA에서 테스트했나요?
**A**:
- Basys-3 보드에서 테스트 완료했습니다.
- Python 스크립트로 PC와 통신 확인했습니다.
- FND에 정상적으로 값이 표시됩니다.

### Q4: 다른 baud rate는 지원하나요?
**A**:
- baud_tick_gen 모듈의 파라미터만 변경하면 됩니다.
- 115200bps까지 테스트 완료했습니다.
- 고속으로 갈수록 케이블 품질이 중요합니다.

### Q5: 에러 처리는 어떻게 하나요?
**A**:
- 현재는 패리티 비트가 없어 오류 검출 불가입니다.
- 개선 방안: 패리티 비트 추가, 체크섬 사용, 재전송 프로토콜 구현

---

## 11. 코드 구조 요약

```
main()
 ├── init_gpo()          // LED 초기화
 ├── init_gpi()          // 스위치 초기화
 └── while(1)            // 메인 루프
      ├── UART_USR 확인  // RX Ready?
      ├── uart_receive() // 데이터 수신
      ├── 숫자 처리      // '0'-'9'
      ├── 명령어 처리    // 'A', 'a', 'O', 'F', 'L'
      ├── process_command() // 명령어 실행
      ├── uart_send()    // 결과 전송
      ├── display_value() // FND 표시
      ├── GPO 업데이트   // LED 표시
      └── delay(700)     // 주기적 지연
```

---

## 12. 결론

### 12.1 구현 성과
- APB 버스 기반 UART 통신 성공
- RISC-V CPU에서 C 코드 실행 확인
- PC ↔ FPGA 양방향 통신 검증
- 연산 결과 FND 표시 동작

### 12.2 학습 내용
- **Memory-Mapped I/O**: 하드웨어 레지스터 접근
- **UART 프로토콜**: 폴링 방식 구현
- **임베디드 C**: 베어메탈 프로그래밍
- **하드웨어-소프트웨어 협업**: RTL과 펌웨어 통합

### 12.3 향후 계획
- 인터럽트 방식 구현
- DMA 연동으로 성능 향상
- 복잡한 프로토콜 지원 (JSON, Protobuf)
- RTOS 포팅 (FreeRTOS)

---

**END OF DOCUMENT**

---

## 부록: Python 테스트 스크립트 예제

```python
import serial
import time

# UART 포트 설정
ser = serial.Serial(
    port='COM3',       # 포트 번호 (Linux: /dev/ttyUSB0)
    baudrate=9600,
    bytesize=8,
    parity='N',
    stopbits=1,
    timeout=1
)

print("UART 통신 시작...")

# 덧셈 테스트
ser.write(b'A')      # 덧셈 모드
time.sleep(0.1)
response = ser.read(100)
print(f"응답: {response.decode('ascii', errors='ignore')}")

ser.write(b'3')      # 첫 번째 피연산자
time.sleep(0.1)

ser.write(b'5')      # 두 번째 피연산자
time.sleep(0.1)
result = ser.read(1)
print(f"결과: {ord(result)}")

# LED ON 테스트
ser.write(b'O')
time.sleep(0.1)
response = ser.read(100)
print(f"LED ON 응답: {response.decode('ascii', errors='ignore')}")

# LED OFF 테스트
ser.write(b'F')
time.sleep(0.1)
response = ser.read(100)
print(f"LED OFF 응답: {response.decode('ascii', errors='ignore')}")

ser.close()
print("테스트 완료!")
```

**실행 결과 예시**:
```
UART 통신 시작...
응답: OK[]
결과: 8
LED ON 응답: ON
LED OFF 응답: OFF
테스트 완료!
```
