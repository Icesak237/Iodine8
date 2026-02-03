# Iodine8
A simple CLI CHIP-8 emulator written in Odin, designed to run directly in the terminal. Developed as a programming exercise and the first program written in Odin.

## How to use
Once compiled provide a ROM file as an argument: 
`./iodine8 ROMS/Space_Invaders.ch8`

The left side of the keyboard is used as inputs according to the following mapping:

| Keyboard | CHIP-8 |
| :--- | :--- |
| 1 2 3 4 | 1 2 3 C |
| Q W E R | 4 5 6 D |
| A S D F | 7 8 9 E |
| Z X C V | A 0 B F |

Note: Z and Y are interchangeable to allow for the use of both QWERTY and QWERTZ keyboard layout.
Pressing ESC will exit the emulator.
