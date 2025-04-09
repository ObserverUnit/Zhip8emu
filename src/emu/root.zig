const std = @import("std");

pub const OpCode = enum(u4) {
    Clear = 0,
    Set = 6,
    Add = 7,
    RegsOp = 8,
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
    pub fn instr(self: Self) OpCode {
        return @enumFromInt(self.higher.instr);
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

        return (X << 8) & nn;
    }
};

pub const Chip8Flags = packed struct {
    /// Configures if wether or not we are emulating
    /// Chip8-Super
    super: bool = true,
};

pub const ExecutionError = error{
    InvaildInstruction,
};

pub const State = struct {
    // memory
    stack: [32]u16 = undefined,
    heap: [4096 + 0x200]u8 = undefined,
    // registers
    stackPointer: usize = 0,
    indexReg: u16 = 0x200,
    register: [16]u8 = .{0} ** 16,
    // timers
    delayTimer: u8 = 0xFF,
    soundTimer: u8 = 0xFF,

    flags: Chip8Flags,
    pub const Self = @This();

    /// Loads a Chip8 program from `bytes` and returns the program state
    pub fn load(bytes: []const u8, flags: Chip8Flags) Self {
        var self: Self = .{ .flags = flags };
        @memcpy(self.heap[0x200 .. 0x200 + bytes.len], bytes);
        return self;
    }

    fn nextInstr(self: *Self) Instruction {
        const b0 = self.heap[self.indexReg];
        const b1 = self.heap[self.indexReg + 1];
        return Instruction.from_bytes(b0, b1);
    }

    /// Sets the flag register (VF) to `v`
    inline fn setFlagReg(self: *Self, v: u8) void {
        self.register[0xF] = v;
    }

    /// Executes the next instruction
    pub fn executeNext(self: *Self) ExecutionError!void {
        const instr = self.nextInstr();
        defer self.indexReg += 2;
        switch (instr.instr()) {
            .Clear => {
                std.debug.assert(instr.NNN() == 0E0);
                std.debug.print("Clear screen!\n", .{});
            },
            .Set => {
                const reg = instr.x();
                self.register[reg] = instr.NN();
            },
            .RegsOp => {
                const reg1_num = instr.x();
                const reg2_num = instr.y();

                const reg1 = &self.register[reg1_num];
                const reg2 = self.register[reg2_num];

                const op = instr.nibble();
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
                    5 => reg1.* -= reg2,
                    7 => reg1.* = reg2 - reg1.*,
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
                    else => return ExecutionError.InvaildInstruction,
                }
            },
            .Add => {
                const reg = instr.x();
                self.register[reg] += instr.NN();
            },
        }
    }
};
