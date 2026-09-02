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

---