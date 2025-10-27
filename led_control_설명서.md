# LED 제어 프로그램 사용 설명서
## led_control.c

---

## 1. 기능 요약

### 1.1 숫자 입력 (0-9)
- **PC에서 입력**: 0~9 중 하나 입력
- **동작**: 해당 비트의 LED 토글 (켜짐 ↔ 꺼짐)
- **예시**:
  ```
  입력: '3'
  → LED[3] 토글
  → PC 콘솔: "Toggle LED 3"
  → PC 콘솔: "LED: 00001000 (0x08)"
  ```

### 1.2 보드 스위치
- **동작**: 보드의 스위치 토글 → 해당 LED 토글
- **PC 콘솔 출력**:
  ```
  "Switch 2 toggled"
  "LED: 00000100 (0x04)"
  ```

### 1.3 오른쪽 시프트 (R/r)
- **첫 번째 입력**: 시프트 시작
  ```
  입력: 'R' 또는 'r'
  → LED가 오른쪽으로 시프트하면서 꺼짐
  → PC 콘솔: "led shift right"
  ```
- **두 번째 입력**: 시프트 중지
  ```
  입력: 'R' 또는 'r'
  → 시프트 멈춤
  → PC 콘솔: "led shift right stop"
  ```

**시프트 예시**:
```
초기: 11111111 (0xFF)
↓ 시프트
Step 1: 01111111 (0x7F)
Step 2: 00111111 (0x3F)
Step 3: 00011111 (0x1F)
...
Step 8: 00000000 (0x00) → 다시 0xFF로 리셋
```

### 1.4 왼쪽 시프트 (L/l)
- **첫 번째 입력**: 시프트 시작
  ```
  입력: 'L' 또는 'l'
  → LED가 왼쪽으로 시프트하면서 켜짐
  → PC 콘솔: "led shift left"
  ```
- **두 번째 입력**: 시프트 중지
  ```
  입력: 'L' 또는 'l'
  → 시프트 멈춤
  → PC 콘솔: "led shift left stop"
  ```

**시프트 예시**:
```
초기: 00000000 (0x00)
↓ 시프트
Step 1: 00000001 (0x01)
Step 2: 00000011 (0x03)
Step 3: 00000111 (0x07)
...
Step 8: 11111111 (0xFF) → 다시 0x00으로 리셋
```

### 1.5 FND 표시
- **시프트 중**: FND에 "MOVE" 표시 (또는 1234)
- **시프트 중지**: FND OFF

---

## 2. 코드 구조

### 2.1 전역 변수
```c
uint8_t led_state = 0x00;           // 현재 LED 상태
uint8_t shift_right_mode = 0;       // 오른쪽 시프트 활성화 플래그
uint8_t shift_left_mode = 0;        // 왼쪽 시프트 활성화 플래그
uint8_t prev_switch_state = 0x00;   // 이전 스위치 상태 (변화 감지용)
```

### 2.2 주요 함수

#### init_system()
```c
void init_system(void);
```
- GPO (LED) 초기화: 모두 OFF
- GPI (스위치) 초기화: 풀업 설정
- FND 초기화: OFF
- UART로 시작 메시지 전송

#### uart_receive_nonblocking()
```c
uint8_t uart_receive_nonblocking(uint8_t *data);
```
- **Non-blocking 수신**: 데이터가 있으면 즉시 반환
- 반환값: 1=데이터 있음, 0=없음
- 기존 `uart_receive()`는 blocking 방식이었음

#### process_uart_command()
```c
void process_uart_command(uint8_t cmd);
```
- 수신한 명령어 처리
- '0'-'9': LED 토글
- 'R'/'r': 오른쪽 시프트 토글
- 'L'/'l': 왼쪽 시프트 토글

#### check_switches()
```c
void check_switches(void);
```
- GPI 레지스터 읽기
- 이전 상태와 XOR 연산으로 변화 감지
- 변화된 비트만 LED 토글

#### shift_leds_right()
```c
void shift_leds_right(void);
```
- `led_state = led_state >> 1`
- 오른쪽으로 1비트 시프트 (꺼지는 효과)

#### shift_leds_left()
```c
void shift_leds_left(void);
```
- `led_state = (led_state << 1) | 0x01`
- 왼쪽으로 1비트 시프트하고 최하위 비트 1 설정 (켜지는 효과)

#### update_fnd()
```c
void update_fnd(void);
```
- 시프트 모드 활성화 시: FND ON, "MOVE" 표시
- 시프트 모드 비활성화 시: FND OFF

---

## 3. 메인 루프 동작

```c
int main(void) {
    init_system();

    while (1) {
        // 1. UART 명령어 체크
        if (uart_receive_nonblocking(&received_data)) {
            process_uart_command(received_data);
        }

        // 2. 스위치 상태 체크
        check_switches();

        // 3. 자동 시프트 처리
        if (shift_right_mode || shift_left_mode) {
            shift_counter++;
            if (shift_counter >= SHIFT_DELAY) {
                // 시프트 실행
                // LED 상태 업데이트
            }
        }

        // 4. FND 업데이트
        update_fnd();

        delay(1);
    }
}
```

**특징**:
- **Non-blocking**: UART 대기 없이 계속 루프 실행
- **멀티태스킹**: UART, 스위치, 시프트를 동시에 처리
- **주기적 시프트**: `shift_counter`로 시프트 속도 제어

---

## 4. 사용 시나리오

### 시나리오 1: LED 개별 제어
```
[PC] → '0' 입력
[FPGA] → LED[0] 켜짐 (0x01)
[PC 콘솔] ← "Toggle LED 0"
[PC 콘솔] ← "LED: 00000001 (0x01)"

[PC] → '3' 입력
[FPGA] → LED[3] 켜짐 (0x09)
[PC 콘솔] ← "Toggle LED 3"
[PC 콘솔] ← "LED: 00001001 (0x09)"
```

### 시나리오 2: 오른쪽 시프트
```
초기 상태: LED = 11111111 (0xFF)

[PC] → 'R' 입력
[PC 콘솔] ← "led shift right"
[FND] → "MOVE" 표시

[자동 시프트 시작]
[PC 콘솔] ← "LED: 01111111 (0x7F)"
... (0.5초 간격)
[PC 콘솔] ← "LED: 00111111 (0x3F)"
... (계속)

[PC] → 'R' 입력 (다시)
[PC 콘솔] ← "led shift right stop"
[FND] → OFF
[시프트 멈춤]
```

### 시나리오 3: 왼쪽 시프트
```
초기 상태: LED = 00000000 (0x00)

[PC] → 'l' 입력 (소문자)
[PC 콘솔] ← "led shift left"
[FND] → "MOVE" 표시

[자동 시프트 시작]
[PC 콘솔] ← "LED: 00000001 (0x01)"
... (0.5초 간격)
[PC 콘솔] ← "LED: 00000011 (0x03)"
... (계속)

[PC] → 'L' 입력 (대문자 - 대소문자 무관)
[PC 콘솔] ← "led shift left stop"
[FND] → OFF
[시프트 멈춤]
```

### 시나리오 4: 스위치 제어
```
[보드] → 스위치 2번 토글 (ON)
[FPGA] → LED[2] 켜짐
[PC 콘솔] ← "Switch 2 toggled"
[PC 콘솔] ← "LED: 00000100 (0x04)"

[보드] → 스위치 2번 토글 (OFF)
[FPGA] → LED[2] 꺼짐
[PC 콘솔] ← "Switch 2 toggled"
[PC 콘솔] ← "LED: 00000000 (0x00)"
```

### 시나리오 5: 복합 제어
```
[PC] → '7' 입력
[FPGA] → LED[7] 켜짐 (0x80)

[PC] → 'R' 입력
[FPGA] → 오른쪽 시프트 시작
[자동] → 0x80 → 0x40 → 0x20 → ...

[보드] → 스위치 0번 토글
[FPGA] → LED[0] 켜짐 (시프트 중에도 동작)
[PC 콘솔] ← "Switch 0 toggled"

[PC] → 'R' 입력 (중지)
[FPGA] → 시프트 멈춤
```

---

## 5. 코드 세부 동작

### 5.1 LED 토글 (숫자 입력)

```c
if (cmd >= '0' && cmd <= '9') {
    uint8_t bit_pos = cmd - '0';  // ASCII → 숫자 변환

    if (bit_pos < 8) {
        // XOR로 토글
        led_state ^= (1 << bit_pos);
        update_leds(led_state);

        uart_send_string("Toggle LED ");
        uart_send(cmd);
        uart_send_string("\r\n");
        send_led_status();
    }
}
```

**동작**:
- `'3'` → `bit_pos = 3`
- `1 << 3` = `0b00001000`
- `led_state ^= 0b00001000` → 3번 비트 반전

### 5.2 시프트 토글 (R/r)

```c
else if (cmd == 'R' || cmd == 'r') {
    shift_right_mode = !shift_right_mode;  // 토글

    if (shift_right_mode) {
        shift_left_mode = 0;  // 왼쪽 시프트 중지
        uart_send_string("led shift right\r\n");
    } else {
        uart_send_string("led shift right stop\r\n");
    }

    update_fnd();
}
```

**특징**:
- **토글 방식**: 한 번 누르면 ON, 다시 누르면 OFF
- **상호 배타적**: 오른쪽 시프트 시작 시 왼쪽 시프트 자동 중지

### 5.3 스위치 변화 감지

```c
void check_switches(void) {
    uint8_t current_switch = GPI_REG & 0xFF;

    // XOR로 변화 감지
    uint8_t changed = current_switch ^ prev_switch_state;

    if (changed) {
        for (int i = 0; i < 8; i++) {
            if (changed & (1 << i)) {
                // 변화된 비트만 LED 토글
                led_state ^= (1 << i);

                uart_send_string("Switch ");
                uart_send('0' + i);
                uart_send_string(" toggled\r\n");
            }
        }

        update_leds(led_state);
        send_led_status();
        prev_switch_state = current_switch;
    }
}
```

**원리**:
```
이전: 00000000
현재: 00000100  (스위치 2번 토글)
XOR:  00000100  ← 변화된 비트만 1

→ 2번 비트만 처리
```

### 5.4 자동 시프트

```c
if (shift_right_mode || shift_left_mode) {
    shift_counter++;

    if (shift_counter >= SHIFT_DELAY) {
        shift_counter = 0;

        if (shift_right_mode) {
            shift_leds_right();

            // 모두 꺼지면 다시 0xFF
            if (led_state == 0) {
                led_state = 0xFF;
                update_leds(led_state);
            }

            send_led_status();
        }

        if (shift_left_mode) {
            shift_leds_left();

            // 모두 켜지면 다시 0x00
            if (led_state == 0xFF) {
                led_state = 0x00;
                update_leds(led_state);
            }

            send_led_status();
        }
    }
}
```

**속도 제어**:
- `SHIFT_DELAY = 5000` (반복 횟수)
- 실제 시간: 약 0.5초 (CPU 속도에 따라 다름)

---

## 6. PC 콘솔 출력 예시

### 시작 시
```
=================================
LED Control System Ready
Commands:
  0-9: Toggle LED
  R/r: Shift Right Toggle
  L/l: Shift Left Toggle
=================================
```

### LED 제어
```
Toggle LED 3
LED: 00001000 (0x08)
```

### 시프트 시작
```
led shift right
LED: 01111111 (0x7F)
LED: 00111111 (0x3F)
LED: 00011111 (0x1F)
...
```

### 시프트 중지
```
led shift right stop
```

### 스위치 토글
```
Switch 5 toggled
LED: 00100000 (0x20)
```

---

## 7. 컴파일 및 실행

### 7.1 RISC-V GCC 컴파일
```bash
riscv32-unknown-elf-gcc -march=rv32i -mabi=ilp32 \
    -O2 -nostdlib -nostartfiles \
    -T linker.ld \
    -o led_control.elf led_control.c startup.s

riscv32-unknown-elf-objcopy -O binary led_control.elf led_control.bin

# 기계어 변환
xxd -p -c 4 led_control.bin > led_control.mem
```

### 7.2 ROM에 로드
```systemverilog
// ROM.sv 수정
initial begin
    $readmemh("led_control.mem", mem);
end
```

### 7.3 Vivado 합성 및 구현
```tcl
# Vivado에서
synth_design -top MCU -part xc7a35tcpg236-1
opt_design
place_design
route_design
write_bitstream -force led_control.bit
```

### 7.4 FPGA 프로그래밍
```bash
# Basys-3 보드에 비트스트림 다운로드
program_fpga led_control.bit
```

### 7.5 PC 통신 (Python)
```python
import serial

ser = serial.Serial('COM3', 9600)

# LED 토글
ser.write(b'3')

# 오른쪽 시프트 시작
ser.write(b'R')

# 실시간 수신
while True:
    if ser.in_waiting:
        data = ser.read(ser.in_waiting)
        print(data.decode('ascii', errors='ignore'), end='')
```

---

## 8. 주요 개선 사항 (기존 code2.c 대비)

### 8.1 Non-blocking UART
**기존 (code2.c)**:
```c
// Blocking - 데이터 올 때까지 대기
while ((UART_USR & RX_READY) == 0);
data = UART_RDR;
```

**개선 (led_control.c)**:
```c
// Non-blocking - 데이터 없으면 바로 반환
if (uart_receive_nonblocking(&data)) {
    process_command(data);
}
// 계속 다른 작업 수행
```

### 8.2 멀티태스킹
- UART 수신
- 스위치 감지
- 자동 시프트
- FND 업데이트

**모두 동시에 처리!**

### 8.3 사용자 친화적
- 시작 메시지
- 실시간 LED 상태 출력
- 16진수/이진수 표시

---

## 9. 디버깅 팁

### 9.1 LED가 안 켜질 때
```c
// GPO 레지스터 확인
uart_send_string("GPO_REG = ");
// GPO_REG 값 출력
```

### 9.2 스위치가 안 될 때
```c
// GPI 레지스터 확인
uint8_t sw = GPI_REG;
uart_send_string("GPI = ");
// 값 출력
```

### 9.3 시프트 속도 조절
```c
// 빠르게
const uint32_t SHIFT_DELAY = 1000;

// 느리게
const uint32_t SHIFT_DELAY = 10000;
```

---

## 10. 결론

이 프로그램은 다음을 구현합니다:
- ✅ 숫자 입력으로 LED 토글
- ✅ 스위치로 LED 토글
- ✅ 오른쪽 시프트 (R/r 토글)
- ✅ 왼쪽 시프트 (L/l 토글)
- ✅ FND에 "MOVE" 표시
- ✅ PC 콘솔 실시간 출력

**발표 시연용으로 완벽합니다!**
