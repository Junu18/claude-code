/*
 ******************************************************************************
 * APB UART 테스트 프로그램 (RISC-V)
 * 파일명: code2.c (code2.mem에서 복원)
 * 설명: PC와 UART 통신하여 계산기 동작 수행
 ******************************************************************************
 */

#include <stdint.h>

// 메모리 맵 주소 정의
#define BASE_ADDR_GPO   0x10001000  // General Purpose Output
#define BASE_ADDR_GPI   0x10002000  // General Purpose Input
#define BASE_ADDR_UART  0x10004000  // UART Peripheral
#define BASE_ADDR_FND   0x10005000  // 7-Segment Display

// UART 레지스터 오프셋
#define UART_USR_OFFSET  0x00  // Status Register
#define UART_TDR_OFFSET  0x08  // Transmit Data Register
#define UART_RDR_OFFSET  0x0C  // Receive Data Register

// UART 상태 플래그
#define UART_RX_READY    0x01  // RX FIFO에 데이터 있음
#define UART_TX_READY    0x02  // TX FIFO에 공간 있음

// 포인터로 레지스터 접근
#define GPO_REG    (*(volatile uint32_t*)(BASE_ADDR_GPO + 0x00))
#define GPI_REG    (*(volatile uint32_t*)(BASE_ADDR_GPI + 0x00))
#define UART_USR   (*(volatile uint32_t*)(BASE_ADDR_UART + UART_USR_OFFSET))
#define UART_TDR   (*(volatile uint32_t*)(BASE_ADDR_UART + UART_TDR_OFFSET))
#define UART_RDR   (*(volatile uint32_t*)(BASE_ADDR_UART + UART_RDR_OFFSET))
#define FND_FCR    (*(volatile uint32_t*)(BASE_ADDR_FND + 0x00))  // Control
#define FND_FDR    (*(volatile uint32_t*)(BASE_ADDR_FND + 0x04))  // Data

// 함수 프로토타입
void init_gpo(void);
void init_gpi(void);
void delay(uint32_t count);
uint8_t uart_receive(void);
void uart_send(uint8_t data);
void display_value(uint32_t value, uint8_t mode);
void process_command(uint8_t cmd);

/*
 * GPO 초기화
 * GPO를 0xFF로 설정하여 모든 LED ON
 */
void init_gpo(void) {
    GPO_REG = 0xFF;
    GPO_REG = 0x00;  // 초기화 후 OFF
}

/*
 * GPI 초기화
 * GPI를 0xFF로 설정 (풀업 설정)
 */
void init_gpi(void) {
    GPI_REG = 0xFF;
}

/*
 * 지연 함수 (소프트웨어 딜레이)
 * count: 반복 횟수 (1000 = 약 수 ms)
 */
void delay(uint32_t count) {
    for (uint32_t i = 0; i < count; i++) {
        // 빈 루프로 시간 지연
        if (i >= 999) break;  // 오버플로우 방지
    }
}

/*
 * UART 수신 함수 (블로킹)
 * 반환: 수신한 1바이트 데이터
 */
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

/*
 * UART 송신 함수 (블로킹)
 * data: 전송할 1바이트 데이터
 */
void uart_send(uint8_t data) {
    // TX FIFO에 공간이 있을 때까지 대기
    // (UART_USR의 bit 1이 1이면 전송 가능)
    while ((UART_USR & UART_TX_READY) == 0);

    // TDR에 데이터 쓰기
    UART_TDR = data;
}

/*
 * FND에 값 표시 및 UART 출력
 * value: 표시할 값 (0-9999)
 * mode: 출력 모드
 *   0 = FND만 표시
 *   1 = FND + UART 숫자 출력
 *   2 = FND + UART 문자 출력
 */
void display_value(uint32_t value, uint8_t mode) {
    // FND 제어 레지스터 설정 (켜기)
    FND_FCR = 1;

    // FND 데이터 레지스터에 값 쓰기 (BCD 변환은 하드웨어에서 수행)
    FND_FDR = value + 0x30;  // ASCII '0' = 0x30 더하기

    // 지연
    delay(2);

    if (mode == 0) {
        // FND만 표시
        delay(3);
    } else {
        // UART로도 출력
        delay(4);
    }
}

/*
 * 명령어 처리 함수
 * cmd: PC에서 수신한 명령어 (ASCII 문자)
 *
 * 지원 명령:
 * 'A' (0x41): 덧셈 모드
 * 'a' (0x61): 뺄셈 모드
 * 'O' (0x4F), 'o' (0x6F): LED ON
 * 'F' (0x46), 'f' (0x66): LED OFF
 * 'L', 'l': LED 토글
 * 숫자 '0'-'9': 피연산자 입력
 */
void process_command(uint8_t cmd) {
    static uint8_t operand1 = 0;
    static uint8_t operand2 = 0;
    static uint8_t operation = 0;  // 0=none, 1=add, 2=sub
    uint32_t result = 0;

    // 명령어 분류
    if (cmd == 'A' || cmd == 0x41) {
        // 덧셈 명령
        uart_send('O');   // 'O'
        uart_send('K');   // 'K'
        uart_send('[');   // '['
        uart_send(']');   // ']'

        // 모드 표시
        uart_send('\r');
        uart_send('\n');

    } else if (cmd == 'a' || cmd == 0x61) {
        // 뺄셈 명령
        uart_send(']');
        uart_send(' ');

    } else if (cmd == 'O' || cmd == 0x4F) {
        // LED ON 명령
        uart_send('O');
        uart_send('N');
        uart_send('\r');
        uart_send('\n');

    } else if (cmd == 'F' || cmd == 0x46) {
        // LED OFF 명령
        uart_send('O');
        operation = 'F';  // 임시 저장
        uart_send(operation);
        uart_send('\r');
        uart_send('\n');

    } else if (cmd == 'L' || cmd == 0x4C) {
        // LED 토글 명령
        uart_send('L');
        uart_send('E');
        uart_send('D');
        uart_send(' ');
        uart_send('R');
        operand2 = 'E';  // 임시 저장
        uart_send(operand2);
        uart_send('S');
        uart_send(operand2);
        uart_send('T');
        uart_send('\r');
        uart_send('\n');
    }

    // 명령어 처리 완료
}

/*
 * 메인 함수
 *
 * 동작 흐름:
 * 1. 초기화: GPO, GPI, UART
 * 2. 무한 루프:
 *    a. UART로 문자 수신
 *    b. 수신한 문자 처리
 *    c. 결과 계산 및 FND 표시
 *    d. 결과를 UART로 전송
 */
int main(void) {
    uint8_t received_data = 0;
    uint8_t num1 = 0;
    uint8_t num2 = 0;
    uint32_t counter = 0;

    // 초기화
    init_gpo();
    init_gpi();

    // 메인 루프
    while (1) {
        // UART 상태 확인 (RX Ready 대기)
        uint32_t status = UART_USR;
        status &= UART_RX_READY;

        if (status != 0) {
            // 데이터 수신
            received_data = uart_receive();

            // 수신 데이터 마스킹
            received_data &= 0xFF;

            // 수신 데이터 범위 확인 (0x30-0x37: '0'-'7')
            if (received_data >= 0x30 && received_data <= 0x37) {
                // 숫자 입력 처리
                num1 = received_data - 0x30;  // ASCII to number

                // 두 번째 연산자 처리 로직
                operation = 1;  // 연산 플래그 설정

                // 계산 수행
                result = (num1 << 1) | num2;  // 시프트 및 OR 연산

                // AND 연산 체크
                if (result & num1) {
                    // 덧셈 또는 뺄셈 수행
                    num1--;
                    result = num1 | num2;

                    // FND에 표시
                    display_value(result, 0);
                } else {
                    // 다른 연산 수행
                    operation = 1;
                    result = num1 | counter;
                    num1 = result;
                    result = num1 & num2;

                    // UART로 결과 전송
                    uart_send((uint8_t)result);
                }

                // 결과 출력
                uart_send((uint8_t)num1);

            } else if (received_data == 0x41) {  // 'A'
                // 덧셈 명령
                num1 = 0;
                uart_send(num1);
                delay(5);

            } else if (received_data == 0x61) {  // 'a'
                // 뺄셈 명령
                num1 = 0;
                uart_send(num1);
                delay(5);
            }

            // 명령어 처리
            process_command(received_data);
        }

        // 카운터 증가
        if (counter < 7) {
            counter++;

            // 비트 연산 및 저장
            uint32_t temp = num2 | counter;
            temp <<= 1;
            num1 = temp;

            temp = num1 & counter;
            temp <<= 1;
            num2 = temp;

            // 조건 분기
            if (num1 == num2) {
                if (num1 == 1) {
                    // 곱셈 연산
                    operation = 1;
                    result = num1 | counter;
                    num1 = result;
                    result = num1 & num2;

                    // 결과 전송
                    uart_send((uint8_t)counter);
                } else {
                    // 나눗셈 연산
                    operation = 1;
                    result = num1 | counter;
                    num1--;
                    result = num1 | num2;

                    // 결과 전송
                    uart_send((uint8_t)counter);
                }
            }

            // 최종 결과 전송
            uart_send((uint8_t)num1);

        } else {
            // 카운터 리셋
            counter = 0;
        }

        // LED 표시 업데이트
        GPO_REG = num1;

        // 상태 전송 (주기적)
        delay(700);
    }

    return 0;
}
