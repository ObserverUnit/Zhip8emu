const std = @import("std");
const display = @import("../display.zig");

const Font = [_]u8{
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
};

pub const OpCode = enum(u4) {
    Special = 0,
    Jump = 1,
    JumpOff = 0xB,
    Call = 2,
    /// Skip 1 instruction If Equal
    SkipE = 3,
    /// Skip 1 instruction If Not Equal
    SkipNE = 4,
    /// Skip 1 instruction If 2 Registers Equal
    SkipRE = 5,
    /// Skip 1 instruction If 2 Registers Not Equal
    SkipRNE = 9,
    Set = 6,
    Add = 7,
    RegsOp = 8,
    SetMemIndex = 0xA,
    SpecialRegisters = 0xF,
    GenRandom = 0xC,
    Display = 0xD,

    pub fn fromInt(value: u4) ?OpCode {
        return std.meta.intToEnum(@This(), value) catch null;
    }
};

const InstrHigher = packed struct(u8) {
    x: u4,
    instr: u4,
};

const InstrLower = packed struct(u8) {
    nibble: u4,
    y: u4,
};

pub const Instruction = packed struct(u16) {
    higher: InstrHigher,
    lower: InstrLower,
    pub const Self = @This();

    pub fn from_bytes(b0: u8, b1: u8) Self {
        const higher: InstrHigher = @bitCast(b0);
        const lower: InstrLower = @bitCast(b1);

        return .{ .higher = higher, .lower = lower };
    }
    pub fn instr(self: Self) !OpCode {
        return OpCode.fromInt(self.higher.instr) orelse {
            std.debug.print("[ERROR]: Invaild Instruction OpCode: 0x{X}\n", .{self.higher.instr});
            return error.InvaildInstruction;
        };
    }

    pub fn x(self: Self) u4 {
        return self.higher.x;
    }

    pub fn y(self: Self) u4 {
        return self.lower.y;
    }

    pub fn nibble(self: Self) u4 {
        return self.lower.nibble;
    }

    pub fn NN(self: Self) u8 {
        return @bitCast(self.lower);
    }

    pub fn NNN(self: Self) u12 {
        const nn: u12 = self.NN();
        const X: u12 = self.x();

        return (X << 8) | nn;
    }
};

pub const Chip8Flags = packed struct {
    /// Configures if wether or not we are emulating
    /// Chip8-Super
    super: bool = true,
};

pub const ExecutionError = error{
    InvaildInstruction,
    InvaildOPCode,
};

pub const State = struct {
    // memory
    stack: [32]u16 = undefined,
    heap: [4096 + 0x200]u8 = undefined,
    // registers
    sp: usize = 0,
    heapIndexReg: u16 = 0x0,
    pc: u16 = 0x200,
    register: [16]u8 = .{0} ** 16,
    // timers
    delayTimer: u8 = 0xFF,
    soundTimer: u8 = 0xFF,

    flags: Chip8Flags,
    random: std.Random.DefaultPrng,
    window: ?*display.Window = null,

    const memFontStart = 0x50;
    pub const Self = @This();

    /// Loads a Chip8 program from `bytes` and returns the program state
    pub fn load(bytes: []const u8, flags: Chip8Flags) Self {
        var self: Self = .{ .flags = flags, .random = undefined };

        @memcpy(self.heap[Self.memFontStart .. Self.memFontStart + Font.len], &Font);
        @memcpy(self.heap[0x200 .. 0x200 + bytes.len], bytes);

        var seed: u64 = undefined;
        std.posix.getrandom(std.mem.asBytes(&seed)) catch |err|
            std.debug.panic("failed to get a random seed: {}", .{err});

        const rand = std.Random.DefaultPrng.init(seed);
        self.random = rand;
        return self;
    }

    pub fn setDisplay(self: *Self, window: *display.Window) void {
        self.window = window;
    }

    fn nextInstr(self: *Self) Instruction {
        const b0 = self.heap[self.pc];
        const b1 = self.heap[self.pc + 1];
        return Instruction.from_bytes(b0, b1);
    }

    /// Sets the flag register (VF) to `v`
    inline fn setFlagReg(self: *Self, v: u8) void {
        self.register[0xF] = v;
    }

    inline fn jump(self: *Self, addr: u16) void {
        self.pc = addr;
    }

    inline fn jumpOff(self: *Self, instr: Instruction) void {
        self.pc = if (!self.flags.super)
            instr.NNN() + self.register[0]
        else
            instr.NNN() + self.register[instr.x()];
    }

    /// Returns from a subroutine
    inline fn ret(self: *Self) void {
        self.sp -= 1;
        self.jump(self.stack[self.sp]);
    }

    /// Calls the subroutine at the address NNN
    inline fn call(self: *Self, addr: u12) void {
        self.stack[self.sp] = self.pc + 2;
        self.sp += 1;
        self.jump(addr);
    }

    inline fn handle2RegistersOp(self: *Self, reg1_num: u4, reg2_num: u4, op: u4) !void {
        const reg1 = &self.register[reg1_num];
        const reg2 = self.register[reg2_num];

        switch (op) {
            0 => reg1.* = reg2,
            1 => reg1.* |= reg2,
            2 => reg1.* &= reg2,
            3 => reg1.* ^= reg2,
            4 => {
                const total = @addWithOverflow(reg1.*, reg2);
                const carry = total[1];
                const sum = total[0];
                reg1.* = sum;
                self.setFlagReg(carry);
            },
            // substraction instructions
            5 => {
                const results = @subWithOverflow(reg1.*, reg2);
                reg1.* = results[0];
                self.setFlagReg(~results[1]);
            },
            7 => {
                const results = @subWithOverflow(reg2, reg1.*);
                reg1.* = results[0];
                self.setFlagReg(~results[1]);
            },
            // shift instructions
            6 => {
                if (!self.flags.super) reg1.* = reg2;

                const first_bit: u8 = reg1.* & 0x1;
                self.setFlagReg(first_bit);

                reg1.* >>= 1;
            },
            0xE => {
                if (!self.flags.super) reg1.* = reg2;

                const last_bit: u8 = (reg1.* & 0b10000000) >> 7;
                self.setFlagReg(last_bit);

                reg1.* <<= 1;
            },
            else => |nibble| {
                std.debug.print("[ERROR]: Invaild nibble 0x{X} for OpCode 0x{X}\n", .{ nibble, @intFromEnum(OpCode.RegsOp) });
                return ExecutionError.InvaildInstruction;
            },
        }
    }

    inline fn handleSpecialRegisters(self: *Self, reg_op: u4, op: u8) !void {
        const reg = &self.register[reg_op];

        switch (op) {
            0x1E => {
                self.heapIndexReg += reg.*;
                if (self.heapIndexReg >= 0x1000) self.setFlagReg(1);
            },
            0x07 => reg.* = self.delayTimer,
            0x15 => self.delayTimer = reg.*,
            0x18 => self.soundTimer = reg.*,
            // Load registers to memory
            0x55 => {
                var i: usize = 0;
                while (i <= reg_op) : (i += 1)
                    self.heap[self.heapIndexReg + i] = self.register[i];

                if (!self.flags.super) self.heapIndexReg += reg_op;
            },
            // Load memory to registers
            0x65 => {
                var i: usize = 0;
                while (i <= reg_op) : (i += 1)
                    self.register[i] = self.heap[self.heapIndexReg + i];

                if (!self.flags.super) self.heapIndexReg += reg_op;
            },
            // Point Index register to Font character
            0x29 => {
                // Each character is 5 pixels wide
                self.heapIndexReg = Self.memFontStart + (reg.* & 0xFF) * 5;
            },
            // Binary Coded Decimal conversion
            0x33 => {
                const num = reg.*;
                self.heap[self.heapIndexReg + 2] = num % 10;
                self.heap[self.heapIndexReg + 1] = num % 10 % 10;
                self.heap[self.heapIndexReg] = num % 10 % 10 % 10;
            },
            else => |NN| {
                std.debug.print("[ERROR]: Invaild NN 0x{X} for OpCode 0x{X}\n", .{ NN, @intFromEnum(OpCode.SpecialRegisters) });
                return ExecutionError.InvaildInstruction;
            },
        }
    }

    fn clearScreen(self: *Self) void {
        std.debug.print("Clear Screen!\n", .{});
        if (self.window) |window| window.fill(.background);
    }

    inline fn setPixel(self: *Self, x: u8, y: u8, color: display.Color) void {
        if (self.window) |window| window.setPixel(x, y, color);
    }

    inline fn handleDisplayInstr(self: *Self, reg_x: u4, reg_y: u4, amount: u4) void {
        const x = self.register[reg_x] & 127;
        const y = self.register[reg_y] & 63;

        self.setFlagReg(0);
        for (0..amount) |row_index_raw| {
            // SHADOWING PLEASE
            const row_index: u8 = @truncate(row_index_raw);
            const row = self.heap[self.heapIndexReg + row_index];

            for (0..8) |col_raw| {
                const col: u3 = @truncate(col_raw);
                const bit = ((row << col) & 0b10000000) >> 7;

                const color: display.Color = if (bit == 1) .foreground else blk: {
                    self.setFlagReg(1);
                    break :blk .background;
                };
                self.setPixel(x + col, y + row_index, color);
            }
        }
    }

    inline fn skip_if(self: *Self, condition: bool) void {
        if (condition) {
            self.pc += 2;
        }
    }

    /// Executes the next instruction
    pub fn executeNext(self: *Self) ExecutionError!void {
        const instr = self.nextInstr();
        const op = try instr.instr();

        switch (op) {
            // Really weird OPCode i couldn't come up with
            // a better name
            .Special => switch (instr.NNN()) {
                0x0E0 => self.clearScreen(),
                0x0EE => return self.ret(),
                else => return ExecutionError.InvaildInstruction,
            },
            // PC manipulation instructions
            // returns so it doesn't skip an instruction
            .Jump => return self.jump(instr.NNN()),
            .JumpOff => return self.jumpOff(instr),
            .Call => return self.call(instr.NNN()),
            // PC manipulation condition instructions
            .SkipE => self.skip_if(self.register[instr.x()] == instr.NN()),
            .SkipNE => self.skip_if(self.register[instr.x()] != instr.NN()),
            .SkipRE => self.skip_if(self.register[instr.x()] == self.register[instr.y()]),
            .SkipRNE => self.skip_if(self.register[instr.x()] != self.register[instr.y()]),
            // Register manipulation instructions
            .Set => self.register[instr.x()] = instr.NN(),
            .RegsOp => try self.handle2RegistersOp(instr.x(), instr.y(), instr.nibble()),
            .Add => {
                const reg = &self.register[instr.x()];
                const value = instr.NN();

                reg.* = @addWithOverflow(reg.*, value)[0];
            },
            .SetMemIndex => self.heapIndexReg = instr.NNN(),
            .SpecialRegisters => try self.handleSpecialRegisters(instr.x(), instr.NN()),
            .GenRandom => {
                const reg = &self.register[instr.x()];
                const mask = instr.NN();
                // TODO: this looks slow
                const generator = self.random.random();
                const rand = generator.int(u8) & mask;
                reg.* = rand;
            },
            .Display => self.handleDisplayInstr(instr.x(), instr.y(), instr.nibble()),
        }

        self.pc += 2;
    }
};
