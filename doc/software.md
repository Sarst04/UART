# UART Software Integration Guide

This document describes how to integrate the UART IP into a bare-metal C application. It provides register definitions, initialization sequences, and code examples for polled and interrupt-driven operation.


## 1. Overview

The UART provides a simple 32-bit memory-mapped interface with three registers:

| Offset | Register | Access | Description |
|--------|----------|--------|-------------|
| `0x00` | `DATA`   | R/W | Write: push byte to TX FIFO.<br>Read: pop byte from RX FIFO. |
| `0x04` | `STATUS` | R/W | Status and error flags. Bits [1:0] read-only, bits [3:2] writable to clear. |
| `0x08` | `CONTROL`| R/W | Interrupt enable bits. |

All registers are 32‑bit wide. Only the lower 8 bits of `DATA` are used; the upper 24 bits read as zero.

## 2. Register Definitions

### `DATA` (offset `0x00`)

| Bits | Field | Access | Description |
|------|-------|--------|-------------|
| 7:0  | `DATA` | R/W | Transmit/Receive byte. Write pushes to TX FIFO, read pops from RX FIFO. |
| 31:8 | —      | —      | Reserved, read as zero. |

### `STATUS` (offset `0x04`)

| Bit | Name         | Access | Description |
|----|--------------|--------|-------------|
| 0  | `RX_AVAIL`   | RO     | `1` when RX FIFO is not empty. |
| 1  | `TX_AVAIL`   | RO     | `1` when TX FIFO is not full. |
| 2  | `OVERRUN`    | RW     | `1` indicates overrun error (RX FIFO full when data arrived). Write `0` to clear. |
| 3  | `PARITY_ERR` | RW     | `1` indicates parity error on received frame. Write `0` to clear. |
| 31:4 | —          | —      | Reserved. |

> **Note:** To clear an error flag, write `0` to the corresponding bit. The hardware will set the bit when an error occurs. Bits [1:0] cannot be written.

### `CONTROL` (offset `0x08`)

| Bit | Name             | Access | Description |
|----|------------------|--------|-------------|
| 0  | `RX_IRQ_EN`      | RW     | Enable interrupt on RX data available. |
| 1  | `TX_IRQ_EN`      | RW     | Enable interrupt on TX space available. |
| 2  | `OVERRUN_IRQ_EN` | RW     | Enable interrupt on overrun error. |
| 3  | `PARITY_IRQ_EN`  | RW     | Enable interrupt on parity error. |
| 31:4 | —              | —      | Reserved. |


## 3. C Driver

```c
#ifndef UART_DRIVER_H
#define UART_DRIVER_H

#include <stdint.h>

// UART Base Address
#define UART_BASE_ADDR   0x10000000UL   // Example

// Register Offsets
#define UART_DATA_OFFSET      0x0
#define UART_STATUS_OFFSET    0x4
#define UART_CONTROL_OFFSET   0x8

// Register Addresses (volatile access)
#define UART_DATA_REG    (*(volatile uint32_t *)(UART_BASE_ADDR + UART_DATA_OFFSET))
#define UART_STATUS_REG  (*(volatile uint32_t *)(UART_BASE_ADDR + UART_STATUS_OFFSET))
#define UART_CONTROL_REG (*(volatile uint32_t *)(UART_BASE_ADDR + UART_CONTROL_OFFSET))

// STATUS Register Bits
#define UART_STATUS_RX_AVAIL    (1u << 0)
#define UART_STATUS_TX_AVAIL    (1u << 1)
#define UART_STATUS_OVERRUN     (1u << 2)
#define UART_STATUS_PARITY_ERR  (1u << 3)

// CONTROL Register Bits
#define UART_CONTROL_RX_IRQ_EN      (1u << 0)
#define UART_CONTROL_TX_IRQ_EN      (1u << 1)
#define UART_CONTROL_OVERRUN_IRQ_EN (1u << 2)
#define UART_CONTROL_PARITY_IRQ_EN  (1u << 3)

// API Functions
void uart_init(void);
void uart_send_byte(uint8_t data);
uint8_t uart_receive_byte(void);
int  uart_send_string(const char *str);
int  uart_receive_available(void);
void uart_enable_interrupts(uint32_t mask);
void uart_disable_interrupts(uint32_t mask);
void uart_clear_errors(void);

#endif // UART_DRIVER_H

#include "uart_driver.h"

// Initialize UART
void uart_init(void) {
    // Disable all interrupts
    UART_CONTROL_REG = 0x0;

    // Clear error flags (write 0 to bits [3:2])
    uint32_t status = UART_STATUS_REG;
    status &= ~(UART_STATUS_OVERRUN | UART_STATUS_PARITY_ERR);
    UART_STATUS_REG = status;
}

// Transmit a single byte (blocking)
void uart_send_byte(uint8_t data) {
    // Wait until TX FIFO is not full
    while ((UART_STATUS_REG & UART_STATUS_TX_AVAIL) == 0) {
        // Optionally use pause instruction to reduce Power
    }
    UART_DATA_REG = (uint32_t)data;
}

// Receive a single byte (blocking)
uint8_t uart_receive_byte(void) {
    // Wait until RX FIFO is not empty
    while ((UART_STATUS_REG & UART_STATUS_RX_AVAIL) == 0) {
        // Optionally use pause instruction to reduce Power
    }
    return (uint8_t)(UART_DATA_REG & 0xFF);
}

// Check if receive data is available
int uart_receive_available(void) {
    return (UART_STATUS_REG & UART_STATUS_RX_AVAIL) != 0;
}

// Send a null-terminated string (blocking)
int uart_send_string(const char *str) {
    int count = 0;
    while (*str != '\0') {
        uart_send_byte((uint8_t)*str);
        str++;
        count++;
    }
    return count;
}

// Enable specific interrupt sources
void uart_enable_interrupts(uint32_t mask) {
    UART_CONTROL_REG |= mask;
}

// Disable specific interrupt sources
void uart_disable_interrupts(uint32_t mask) {
    UART_CONTROL_REG &= ~mask;
}

// Clear error flags (overrun and parity)
void uart_clear_errors(void) {
    uint32_t status = UART_STATUS_REG;
    status &= ~(UART_STATUS_OVERRUN | UART_STATUS_PARITY_ERR);
    UART_STATUS_REG = status;
}

```


