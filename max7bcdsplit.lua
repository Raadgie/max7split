--- @module max7split
-- Driver for MAX7219 LED display over SPI.
-- Supports displaying two 4-digit segments (e.g. "HELP", "1234"),
-- setting display intensity, clearing segments, and toggling shutdown mode.
-- Automatically aligns text to the right and supports decimal point notation.
--
-- @author Raadgie
-- @release 1.0
-- @license MIT
--
-- @see MAX7219 datasheet
--
-- @usage
-- ```lua
-- local max7 = require ("max7split").create (8)
-- max7.write       ("HELP", "1234")       -- Display text on both 4-digit halves
-- max7.intensity   (0x0A)                 -- Set brightness level (0x00–0x0F)
-- max7.clear       ()                     -- Clear entire display
-- max7.shutdown    (1)                    -- 1 = normal operation, 0 = shutdown
-- ```

local modname = ...
local M = {}

local BUS_SPEED = 10 -- SPI frequency in MHz

-- MAX7219 register addresses
local DECODE_MODE = 0x09
local DECODE_MODE_FULL = 0xFF -- enable BCD decoding on all digits
local INTENSITY = 0x0A -- brightness control register
local SCAN_LIMIT = 0x0B -- limits the number of active digits (0–7)
local SHUTDOWN_MODE = 0x0C
local SHUTDOWN_MODE_OFF = 0x00 -- shutdown mode (display off)
local SHUTDOWN_MODE_NORMAL = 0x01 -- normal operation
local DISPLAY_TEST = 0x0F
local DISPLAY_TEST_OFF = 0x00 -- disable test mode

-- Calculate SPI clock divider to set desired SPI speed
local clock_division = node.getcpufreq () / BUS_SPEED

local cs -- Chip Select (Load) pin variable

-- Mapping ASCII characters to BCD representations supported by MAX7219
local bcd_char = {
    [45] = 0x0A, -- "-"
    [69] = 0x0B, -- "E"
    [72] = 0x0C, -- "H"
    [76] = 0x0D, -- "L"
    [80] = 0x0E, -- "P"
    [32] = 0x0F  -- space
}

-- Last known buffer state to retain unchanged digits during partial updates
local last_buff = {}

--- Sends data to the MAX7219 via SPI.
-- Accepts either a table of 8 digits or a 16-bit command (register << 8 | value).
local function max7send (data)
    spi.set_clock_div (1, clock_division)

    if type (data) == "table" then
        local digit 
        -- Sending digit-by-digit
        for i = 1, 8 do
            digit = data [i] or 0x0F -- default to blank if not set
            last_buff [i] = data [i] -- update backup buffer
            gpio.write (cs, 0)
            spi.send (1, i, digit)
            gpio.write (cs, 1)
        end
    else
        -- Sending 16-bit command: MSB = register, LSB = data
        gpio.write (cs, 0)
        spi.send (1, bit.rshift (data, 8), data)
        gpio.write (cs, 1)
    end
end

--- Clears the specified zone of the display or the entire display.
-- @param zone 1 = digits 1-4, 2 = digits 5-8, nil = all digits
function M.clear (zone)
    local buff = {}
    for i = 1, 8 do buff [i] = last_buff [i] end

    -- Define range based on zone
    local first_digit, last_digit = 1, 8
    if zone == 1 then last_digit = 4 end
    if zone == 2 then first_digit = 5 end

    -- Replace specified digits with "-"
    for i = first_digit, last_digit do
        buff [i] = 0x0A
        last_buff [i] = nil -- remove from memory buffer
    end

    max7send (buff)
end

--- Sets the chip to shutdown or normal mode.
-- @param shutdown 0 = shutdown, 1 = normal operation (default)
function M.shutdown (shutdown)
    shutdown = shutdown or SHUTDOWN_MODE_NORMAL
    max7send (bit.bor (bit.lshift (SHUTDOWN_MODE, 8), shutdown))
end

--- Sets the display brightness.
-- @param intensity brightness level 0x00 - 0x0F (default 0x07)
function M.intensity (intensity)
    intensity = intensity and math.min (intensity, 0x0F) or 0x07
    max7send (bit.bor (bit.lshift (INTENSITY, 8), intensity))
end

--- Displays two segments of text input on the display.
-- @param input1 first 4 characters (right side, 16-bit MSB)
-- @param input2 second 4 characters (left side, 16-bit LSB)
function M.write (input1, input2)
    local buff = {}

    -- Converts string into digit buffer starting from left
    local function stringProcessing (input)
        local values = {}
        local digit = 1
        local data = tostring (input)
        local is_dot
        local next_is_dot
        local is_digit_value
        local is_space
        local char = 1
        local byte = string.byte (data, char) -- Read the first character before entering the loop
        local value

        while byte and digit < 5 do
            -- Check if the next character is a dot (.)
            next_is_dot = string.byte (data, char + 1) == 46

            -- Determine if current byte is a digit (0–9), and convert to numeric BCD value
            is_digit_value = (byte >= 48 and byte <= 57) and (byte - 48)

            -- Check if current character is a dot (.)
            is_dot = byte == 46

            -- Check if current character is a space
            is_space = byte == 32

            -- Resolve the final display value:
            -- Prefer digit, fallback to mapped BCD character or space if unknown
            value = is_digit_value or bcd_char [byte] or bcd_char [32]

            -- Case: decimal dot follows a digit (e.g. "1.2")
            -- Set bit 7 to activate the decimal point and skip the dot in the next loop
            if next_is_dot and not is_dot and not is_space then
                value = bit.set (value, 7)
                char = char + 1

            -- Case: current character is a standalone dot (e.g. ".")
            elseif is_dot then
                value = bit.set (bcd_char [32], 7) -- Show just a dot
            end

            -- Store value into current digit slot (1 to 4)
            values [digit] = value

            -- Advance to the next digit and character
            digit = digit + 1
            char = char + 1
            byte = string.byte (data, char)
        end

        return values
    end

    -- Process first segment (digits 1 to 4 of the display)
    if input1 then
        -- Convert the input string into a table of up to 4 BCD digit values
        local values = stringProcessing (input1)

        -- Reverse the order of digits to achieve right-alignment on the display
        -- Example: input "12" → values = {1, 2} → reversed = {2, 1}
        local j = #values
        for i = 1, 4 do
            if j > 0 then
                -- Fill buff[i] with values from the end of the input
                -- Ensures digits are placed on the right side of the 4-digit segment
                buff [i] = values [j]
                j = j - 1
            else
                -- If fewer than 4 digits were given, fill the rest with nil (blank)
                buff [i] = nil
            end
        end
    else
        -- If no new input was given for this segment,
        -- keep the previous display state by copying from last_buff
        for i = 1, 4 do
            buff [i] = last_buff [i]
        end
    end
    -- Process second segment (digits 5 to 8)
    if input2 then
        local values = stringProcessing (input2)
        -- Digit order
        local j = #values
        for i = 1, 4 do
            if j > 0 then
                buff [i + 4] = values [j]
                j = j - 1
            else
                buff [i + 4] = nil
            end
        end
    else
        for i = 5, 8 do buff [i] = last_buff [i] end
    end
    max7send (buff)
end

--- Initializes the MAX7219 display with default configuration.
-- @param cs_pin number of the Chip Select pin
-- @return M module function table
function M.create (cs_pin)
    assert (cs_pin, "No CS pin has been set!")
    cs = cs_pin

    gpio.mode (cs, gpio.OUTPUT) -- Configure pin as output

    -- Setup display: turn off, set scan limit, disable test mode, enable BCD decode
    max7send (bit.bor (bit.lshift (SHUTDOWN_MODE, 8), SHUTDOWN_MODE_OFF))
    max7send (bit.bor (bit.lshift (SCAN_LIMIT, 8), 0x07))
    max7send (bit.bor (bit.lshift (DISPLAY_TEST, 8), DISPLAY_TEST_OFF))
    max7send (bit.bor (bit.lshift (DECODE_MODE, 8), DECODE_MODE_FULL))

    M.clear () -- Clear screen initially
    M.intensity (0x07) -- Set medium brightness
    max7send (bit.bor (bit.lshift (SHUTDOWN_MODE, 8), SHUTDOWN_MODE_NORMAL)) -- Enable display

    package.loaded [modname] = nil -- Unload module after init
    M.create = nil -- Free up memory

    return M
end

return M
