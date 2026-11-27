#define UART (*(volatile unsigned int *)0x1fcu)

void uart_start(void)
{
    while (!(UART & 1u)) {}
    UART = 'O';
    while (!(UART & 1u)) {}
    UART = 'K';
    while (!(UART & 1u)) {}
    UART = '\n';
    for (;;) {}
}
