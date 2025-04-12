# max7split-NodeMCU

**max7split** is a Lua module for **NodeMCU (ESP8266/ESP32)** used to control an 8-digit 7-segment LED display with the MAX7219 driver chip.  
It supports BCD decoding, decimal points, right-aligned rendering, and dual-segment display output (4+4 digits).

## Features

- Display text and numbers on two 4-digit segments (split left/right)
- Right-aligned output for numeric formatting
- Adjustable brightness (0x00–0x0F)
- Clear entire display or only one segment
- Shutdown and resume display operation
- Decimal point support (e.g., `1.2`, `12.`)

## Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/Raadgie/max7split-NodeMCU.git
