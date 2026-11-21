## How it works

A packet engine for Feetech STS serial-bus servos (the 14 STS3215 servos of an Open Duck Mini biped robot).
The host writes the packet body (ID, LEN, INSTR, parameters) byte by byte on `ui_in` with a rising edge on `WR` (up to 16 bytes).
On a rising edge of `GO` the chip sends `0xFF 0xFF`, the body and the checksum `~(sum of body) & 0xFF` over UART 8N1.
The baud divisor is loaded from `ui_in` with a rising edge on `BAUD` (clock cycles per bit = value + 1; default 25, i.e. 2 Mbaud at 50 MHz; use 49 for 1 Mbaud).
`TXEN` is high while transmitting, to drive the direction pin of a half-duplex transceiver. `BUSY`, `FULL`, the byte count and the low nibble of the last checksum are readable.

## How to test

1. Reset. Put 49 on `ui_in` and pulse `BAUD` (1 Mbaud at 50 MHz).
2. Write `0x01, 0x05, 0x03, 0x2A, 0x00, 0x08` with `WR` pulses (WRITE goal position 2048 to servo ID 1).
3. Pulse `GO`. `TX` sends `FF FF 01 05 03 2A 00 08 C4`.
The cocotb test checks this packet and 20 random packets of 1 to 16 bytes.

## External hardware

A half-duplex buffer (e.g. 74LVC1G126) between `TX`/`TXEN` and the servo data line, and Feetech STS servos.
