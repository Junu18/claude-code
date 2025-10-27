/*
 ******************************************************************************
 * APB UART LED 제어 프로그램 (RISC-V)
 * 파일명: led_control.c
 * 설명: UART와 스위치를 통한 LED 제어 및 시프트 동작
 ******************************************************************************
 */

#include <stdint.h>

// 메모리 맵 주소 정의
#define BASE_ADDR_GPO   0x10001000  // LED Output
#define BASE_ADDR_GPI   0x10002000  // Switch Input
#define BASE_ADDR_UART  0x10004000  // UART
#define BASE_ADDR_FND   0x10005000  // 7-Segment Display

// UART 레지스터 오프셋
#define UART_USR_OFFSET  0x00  // Status Register
#define UART_TDR_OFFSET  0x08  // Transmit Data Register
#define UART_RDR_OFFSET  0x0C  // Receive Data Register

// UART 상태 플래그
#define UART_RX_READY    0x01
#define UART_TX_READY    0x02

// 레지스터 접근 매크로
#define GPO_REG    (*(volatile uint32_t*)(BASE_ADDR_GPO + 0x00))
#define GPI_REG    (*(volatile uint32_t*)(BASE_ADDR_GPI + 0x00))
#define UART_USR   (*(volatile uint32_t*)(BASE_ADDR_UART + UART_USR_OFFSET))
#define UART_TDR   (*(volatile uint32_t*)(BASE_ADDR_UART + UART_TDR_OFFSET))
#define UART_RDR   (*(volatile uint32_t*)(BASE_ADDR_UART + UART_RDR_OFFSET))
#define FND_FCR    (*(volatile uint32_t*)(BASE_ADDR_FND + 0x00))  // Control
#define FND_FDR    (*(volatile uint32_t*)(BASE_ADDR_FND + 0x04))  // Data

// 전역 변수
uint8_t led_state = 0x00;           // 현재 LED 상태
uint8_t shift_right_mode = 0;       // 오른쪽 시프트 모드 (0=off, 1=on)
uint8_t shift_left_mode = 0;        // 왼쪽 시프트 모드 (0=off, 1=on)
uint8_t prev_switch_state = 0x00;   // 이전 스위치 상태

// 함수 프로토타입
void init_system(void);
void delay(uint32_t count);
uint8_t uart_receive_nonblocking(uint8_t *data);
void uart_send(uint8_t data);
void uart_send_string(const char *str);
void update_leds(uint8_t value);
void shift_leds_right(void);
void shift_leds_left(void);
void update_fnd(void);
void send_led_status(void);
void process_uart_command(uint8_t cmd);
void check_switches(void);

/*
 * 시스템 초기화
 */
void init_system(void) {
    // GPO 초기화 (LED 모두 OFF)
    GPO_REG = 0x00;
    led_state = 0x00;

    // GPI 초기화 (풀업)
    GPI_REG = 0xFF;
    prev_switch_state = GPI_REG & 0xFF;

    // FND 초기화
    FND_FCR = 0;  // OFF
    FND_FDR = 0;

    // 시작 메시지
    uart_send_string("=================================\r\n");
    uart_send_string("LED Control System Ready\r\n");
    uart_send_string("Commands:\r\n");
    uart_send_string("  0-9: Toggle LED\r\n");
    uart_send_string("  R/r: Shift Right Toggle\r\n");
    uart_send_string("  L/l: Shift Left Toggle\r\n");
    uart_send_string("=================================\r\n");
}

/*
 * 지연 함수
 */
void delay(uint32_t count) {
    for (uint32_t i = 0; i < count; i++) {
        for (uint32_t j = 0; j < 100; j++) {
            __asm__ volatile("nop");
        }
    }
}

/*
 * UART 수신 (Non-blocking)
 * 반환: 1=데이터 있음, 0=데이터 없음
 */
uint8_t uart_receive_nonblocking(uint8_t *data) {
    if (UART_USR & UART_RX_READY) {
        *data = (uint8_t)UART_RDR;
        return 1;
    }
    return 0;
}

/*
 * UART 송신
 */
void uart_send(uint8_t data) {
    while ((UART_USR & UART_TX_READY) == 0);
    UART_TDR = data;
}

/*
 * UART 문자열 송신
 */
void uart_send_string(const char *str) {
    while (*str) {
        uart_send(*str++);
    }
}

/*
 * LED 업데이트
 */
void update_leds(uint8_t value) {
    led_state = value;
    GPO_REG = led_state;
}

/*
 * LED 상태를 PC로 전송
 */
void send_led_status(void) {
    uart_send_string("LED: ");

    // 8비트 이진수 출력
    for (int i = 7; i >= 0; i--) {
        if (led_state & (1 << i)) {
            uart_send('1');
        } else {
            uart_send('0');
        }
    }

    uart_send_string(" (0x");

    // 16진수 출력
    uint8_t high = (led_state >> 4) & 0x0F;
    uint8_t low = led_state & 0x0F;

    uart_send(high < 10 ? '0' + high : 'A' + high - 10);
    uart_send(low < 10 ? '0' + low : 'A' + low - 10);

    uart_send_string(")\r\n");
}

/*
 * LED 오른쪽 시프트 (꺼지면서)
 */
void shift_leds_right(void) {
    led_state = led_state >> 1;
    update_leds(led_state);
}

/*
 * LED 왼쪽 시프트 (켜지면서)
 */
void shift_leds_left(void) {
    led_state = (led_state << 1) | 0x01;
    if (led_state == 0) {
        led_state = 0x01;  // 모두 꺼지면 최하위 비트부터 시작
    }
    update_leds(led_state);
}

/*
 * FND 업데이트
 */
void update_fnd(void) {
    if (shift_right_mode || shift_left_mode) {
        // 시프트 중일 때 "MOVE" 표시
        // FND에 "MOVE"를 표시하려면 각 자리에 문자 코드 설정
        // M=77, O=79, V=86, E=69 (ASCII)
        FND_FCR = 1;  // FND ON
        // FND_FDR에 "MOVE"를 표시하기 위한 값 설정
        // 실제 하드웨어에 따라 다를 수 있음
        // 여기서는 간단히 1234로 표시 (MOVE 대신 숫자로)
        FND_FDR = 1234;  // 하드웨어가 BCD 변환 수행
    } else {
        // 시프트 안 할 때 FND OFF
        FND_FCR = 0;
        FND_FDR = 0;
    }
}

/*
 * UART 명령어 처리
 */
void process_uart_command(uint8_t cmd) {
    // 숫자 0-9 입력 처리
    if (cmd >= '0' && cmd <= '9') {
        uint8_t bit_pos = cmd - '0';

        if (bit_pos < 8) {
            // 해당 LED 토글
            led_state ^= (1 << bit_pos);
            update_leds(led_state);

            uart_send_string("Toggle LED ");
            uart_send(cmd);
            uart_send_string("\r\n");
            send_led_status();
        }
    }
    // R/r 명령어: 오른쪽 시프트 토글
    else if (cmd == 'R' || cmd == 'r') {
        shift_right_mode = !shift_right_mode;

        if (shift_right_mode) {
            // 시프트 시작
            shift_left_mode = 0;  // 왼쪽 시프트 중지
            uart_send_string("led shift right\r\n");
        } else {
            // 시프트 중지
            uart_send_string("led shift right stop\r\n");
        }

        update_fnd();
    }
    // L/l 명령어: 왼쪽 시프트 토글
    else if (cmd == 'L' || cmd == 'l') {
        shift_left_mode = !shift_left_mode;

        if (shift_left_mode) {
            // 시프트 시작
            shift_right_mode = 0;  // 오른쪽 시프트 중지
            uart_send_string("led shift left\r\n");
        } else {
            // 시프트 중지
            uart_send_string("led shift left stop\r\n");
        }

        update_fnd();
    }
}

/*
 * 스위치 상태 체크 (GPI)
 */
void check_switches(void) {
    uint8_t current_switch = GPI_REG & 0xFF;

    // 변화 감지 (XOR)
    uint8_t changed = current_switch ^ prev_switch_state;

    if (changed) {
        // 변화된 비트만 LED 토글
        for (int i = 0; i < 8; i++) {
            if (changed & (1 << i)) {
                // 스위치가 눌림 (0) 또는 놓임 (1)
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

/*
 * 메인 함수
 */
int main(void) {
    uint8_t received_data;
    uint32_t shift_counter = 0;
    const uint32_t SHIFT_DELAY = 5000;  // 시프트 속도 조절

    // 시스템 초기화
    init_system();

    // 메인 루프
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
                shift_counter = 0;

                if (shift_right_mode) {
                    shift_leds_right();

                    // LED가 모두 꺼지면 다시 시작
                    if (led_state == 0) {
                        led_state = 0xFF;
                        update_leds(led_state);
                    }

                    send_led_status();
                }

                if (shift_left_mode) {
                    shift_leds_left();

                    // LED가 모두 켜지면 다시 시작
                    if (led_state == 0xFF) {
                        led_state = 0x00;
                        update_leds(led_state);
                    }

                    send_led_status();
                }
            }
        }

        // 4. FND 업데이트 (시프트 중일 때만)
        update_fnd();

        // 짧은 딜레이 (CPU 부하 감소)
        delay(1);
    }

    return 0;
}
