package iodine8

import "core:fmt"
import "core:time"
import "core:math/rand"
import "core:os"
import "core:sys/linux"


TCGETS  :: 0x5401
TCSETSF :: 0x5404
ICANON  :: 0o000002
ECHO    :: 0o000010
VTIME   :: 5
VMIN    :: 6


FONTSET := [80]u8 {
    0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
    0x20, 0x60, 0x20, 0x20, 0x70, // 1
    0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
    0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
    0x90, 0x90, 0xF0, 0x10, 0x10, // 4
    0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
    0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
    0xF0, 0x10, 0x20, 0x40, 0x40, // 7
    0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
    0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
    0xF0, 0x90, 0xF0, 0x90, 0x90, // A
    0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
    0xF0, 0x80, 0x80, 0x80, 0xF0, // C
    0xE0, 0x90, 0x90, 0x90, 0xE0, // D
    0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
    0xF0, 0x80, 0xF0, 0x80, 0x80, // F
}

Termios :: struct {
    c_iflag:  u32,
    c_oflag:  u32,
    c_cflag:  u32,
    c_lflag:  u32,
    c_line:   u8,
    c_cc:     [32]u8,
    c_ispeed: u32,
    c_ospeed: u32,
}

original_termios: Termios


// structs
Console :: struct {
    memory : [4096]u8,
    V : [16]u8,
    I : u16,
    pc : u32,
    stack : [16]u16,
    display : [64*32]u8,
    stack_p : u8,
    delay_t : u8,
    sound_t : u8,

    keypad : [16]u8,
}


// functions
main :: proc() {
    c: Console
    if len(os.args) < 2 {
        fmt.println("Usage: iodine8 <path_to_rom>")
        return
    }
    ROM_name := os.args[1]
    start_time := time.now()
    last_time := start_time
    init(&c)

    if !insert_ROM(&c, ROM_name) {
        return
    }

    enable_raw_mode()
    defer disable_raw_mode()

    for {
        handle_input(&c)
        ops(&c)

        current_time := time.now()
        if (time.duration_nanoseconds(time.diff(last_time, current_time)) > 16666667) {
            update_timers(&c)
            last_time = time.now()
            c.keypad = {}

        }   
        time.sleep(time.Millisecond * 1)
    }
}


init :: proc(c: ^Console) {
    c.pc = 0x200
    for i in 0..<80 {
        c.memory[i] = FONTSET[i]
    }
    c.display = {}
}


update_timers :: proc (c: ^Console) {
    if (c.delay_t > 0){
        c.delay_t -= 1
    }
    if (c.sound_t > 0){
        c.sound_t -= 1
    }
}


cli_display :: proc (c: ^Console) {
    fmt.print("\033[H")

    for y in 0..<32 {
        for x in 0..<64 {
            pixel:= c.display[y * 64 + x]

            if pixel == 0 {
                fmt.print("  ")
            } else {
                fmt.print("██")
            }
        }
        fmt.print("\033[K\n")
    }
}


draw :: proc (X: u8, Y: u8, N: u8, c: ^Console) {
    c.V[0xF] = 0
    x_start := int(X) % 64
    y_start := int(Y) % 32

    for i in 0..<int(N) {
        //if c.I + u16(i) >= 4096 do break
        // fmt.printf("I: %v, i: %v\n", c.I, i)
        byte_d := c.memory[c.I + u16(i)]
        target_y := y_start + i
        if target_y >= 32 do continue

        for j in 0..<8 {
            target_x := x_start + j
            pixel_bit:= bool((byte_d >> u8(7-j)) & 0x1)
            if target_x >= 64 do continue

            if pixel_bit {
                idx := target_y * 64 + target_x
                if c.display[idx] ==1 {
                    c.V[0xF] = 1
                }
                c.display[idx] ~= u8(pixel_bit)
            }  
        }
    }
    cli_display(c)
}


ops :: proc (c: ^Console) {
    op : u16 = u16((u16(c.memory[c.pc]) << 8) | u16(c.memory[c.pc+1]))
    c.pc += 2
    op_type: u16 = u16(op & 0xF000) >> 12
    
    NNN : u16 = u16(op & 0x0FFF)
    NN : u8 = u8(op & 0x00FF)
    N : u8 = u8(op & 0x000F)

    X : u8 = u8((op & 0x0F00) >> 8)
    Y : u8 = u8((op & 0x00F0) >> 4)

    if c.I > 4000 {
    //fmt.printf("CRITICAL: I is %v at PC %x. Opcode: %x\n", c.I, c.pc - 2, op)
    }

    switch (op_type) {
        case 0x0:
            if (NN == 0xE0) {
                c.display = {}
            } else if (NN == 0xEE) {
                c.stack_p -= 1
                c.pc = u32(c.stack [c.stack_p])
            }
        case 0x1:
            c.pc = u32(NNN)
        case 0x2:
            c.stack[c.stack_p] = u16(c.pc)
            c.stack_p += 1
            c.pc = u32(NNN)
        case 0x3:
            if (c.V[X] == NN) {
                c.pc += 2
            }
        case 0x4:
            if (c.V[X] != NN) {
                c.pc += 2
            }
        case 0x5:
            if (c.V[X] == c.V[Y]) {
                c.pc += 2
            }
        case 0x6:
            c.V[X] = NN
        case 0x7:
            c.V[X] += NN
        case 0x8:
            switch (N) {
                case 0x0:
                    c.V[X] = c.V[Y]
                case 0x1:
                    c.V[X] |= c.V[Y]
                case 0x2:
                    c.V[X] &= c.V[Y]
                case 0x3:
                    c.V[X] ~= c.V[Y]
                case 0x4:
                    if int(c.V[X])+int(c.V[Y])>255 {
                        c.V[0xF] = 1
                    } else {
                        c.V[0xF] = 0
                    }
                    c.V[X] = c.V[X] + c.V[Y]

                case 0x5:
                    if c.V[X] < c.V[Y] {
                        c.V[0xF] = 0
                    } else {
                        c.V[0xF] = 1
                    }
                    c.V[X] = c.V[X] - c.V[Y]
                case 0x6:
                    c.V[0xF] = c.V[X] & 0x01
                    c.V[X] >>= 1
                case 0x7:
                    if c.V[Y] < c.V[X] {
                        c.V[0xF] = 0
                    } else {
                        c.V[0xF] = 1
                    }
                    c.V[X] = c.V[Y] - c.V[X]
                case 0xE:
                    c.V[0xF] = u8((c.V[X] & 0x80) >> 7)
                    c.V[X] <<= 1
            }
        case 0x9:
            if (c.V[X] != c.V[Y]) {
                c.pc += 2
            }
        case 0xA:
            c.I = NNN
        case 0xB:
            c.pc = u32(u16(c.V[0]) + NNN)
        case 0xC:
            c.V[X] = u8(rand.uint32()) & NN
        case 0xD:
            draw(c.V[X], c.V[Y], N, c)
        case 0xE:
                switch (NN) {
                    case 0x9E:
                        if c.keypad[c.V[X]] != 0 {
                            c.pc += 2
                        }
                    case 0xA1:
                        if c.keypad[c.V[X]] == 0 {
                            c.pc += 2
                        }
                }
        case 0xF:
            switch (NN)
            {
                case 0x07:
                    c.V[X] = c.delay_t
                case 0x0A:
                    key_pressed: u8
                    for i in 0..<16 {
                        if bool(c.keypad[i]) {
                            c.V[X] = u8(i)
                            key_pressed = 1
                        }
                    }
                    if key_pressed == 0 {
                        c.pc -=2
                    }
                case 0x15:
                    c.delay_t = c.V[X]
                case 0x18:
                    c.sound_t = c.V[X]
                case 0x1E:
                    c.I = (c.I + u16(c.V[X])) & 0x0FFF
                case 0x29:
                    c.I = u16(c.V[X]) * 5 //5 byte per font character
                case 0x33:
                    c.memory[c.I]   = (c.V[X] / 100) % 10
                    c.memory[c.I+1] = (c.V[X] / 10) % 10
                    c.memory[c.I+2] = (c.V[X]) % 10
                case 0x55:
                    for i in 0..=X {
                        c.memory[c.I+u16(i)] = c.V[0+i]
                    }
                case 0x65:
                    for i in 0..=X {
                        c.V[0+i] = c.memory[c.I+u16(i)]
                    }
            }
    }
}

insert_ROM :: proc (c: ^Console, ROM_name: string) -> bool {
    ROM, success:= os.read_entire_file(ROM_name)
    if !success || len(ROM) > (4096-0x200) {
        defer delete (ROM)
        return false
    } else {
        for i in 0..<len(ROM) {
            c.memory[0x200+i] = ROM[i]
        }
        defer delete (ROM)
        return true
    }
}


handle_input :: proc (c: ^Console) {
    buf: [1]u8
    n, _ := linux.read(linux.STDIN_FILENO, buf[:])

    if n > 0 {
        key := buf[0]
        
        // CHIP-8:          Tastatur Mapping:
        // 1 2 3 C          1 2 3 4
        // 4 5 6 D          Q W E R
        // 7 8 9 E          A S D F
        // A 0 B F          Z X C V
        
        switch key {
            case '1': c.keypad[0x1] = 1
            case '2': c.keypad[0x2] = 1
            case '3': c.keypad[0x3] = 1
            case '4': c.keypad[0xC] = 1

            case 'q': c.keypad[0x4] = 1
            case 'w': c.keypad[0x5] = 1
            case 'e': c.keypad[0x6] = 1
            case 'r': c.keypad[0xD] = 1

            case 'a': c.keypad[0x7] = 1
            case 's': c.keypad[0x8] = 1
            case 'd': c.keypad[0x9] = 1
            case 'f': c.keypad[0xE] = 1

            case 'y': fallthrough
            case 'z': c.keypad[0xA] = 1
            case 'x': c.keypad[0x0] = 1
            case 'c': c.keypad[0xB] = 1
            case 'v': c.keypad[0xF] = 1
            
            case 0x1B: 
                disable_raw_mode()
                os.exit(0)
        }
    }
}

enable_raw_mode :: proc () {
    linux.ioctl(linux.Fd(os.stdin), TCGETS, uintptr(&original_termios))
    raw := original_termios

    raw.c_lflag &= ~(u32(ICANON | ECHO))

    raw.c_cc[VMIN] = 0
    raw.c_cc[VTIME] = 0

    linux.ioctl(linux.Fd(os.stdin), TCSETSF, uintptr(&raw))
    fmt.print("\033[?25l")
}

disable_raw_mode :: proc () {
    linux.ioctl(linux.Fd(os.stdin), TCSETSF, uintptr(&original_termios))
    fmt.print("\033[?25h")
}