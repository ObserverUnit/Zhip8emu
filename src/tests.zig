const std = @import("std");
const lib = @import("root.zig");
const emu = lib.emu;

const expect = std.testing.expect;

const Test = struct {
    prog: emu.State,
    instrs_count: usize,
    expected_registers: []const struct { u4, u8 },

    fn init(prog: []const u8, expected_registers: []const struct { u4, u8 }, flags: emu.Chip8Flags) Test {
        return Test{
            .prog = lib.loadBytes(prog, flags),
            .instrs_count = prog.len / 2,
            .expected_registers = expected_registers,
        };
    }

    fn executeCount(self: *Test, count: usize, expected_regs: []const struct { u4, u8 }) !void {
        for (0..count) |_| {
            try self.prog.executeNext();
        }

        defer self.instrs_count -= count;

        for (expected_regs) |e| {
            const reg = e.@"0";
            const v = e.@"1";

            expect(self.prog.register[reg] == v) catch |err| {
                std.debug.print("reg V{x} unexpected value {x} expected {x}\n", .{ reg, self.prog.register[reg], v });
                return err;
            };
        }
    }

    fn executeOnce(self: *Test, expected_regs: []const struct { u4, u8 }) !void {
        return self.executeCount(1, expected_regs);
    }

    fn executeAll(self: *Test) !void {
        return self.executeCount(self.instrs_count, self.expected_registers);
    }
};

test "Clear Screen" {
    const prog = .{ 0x00, 0xE0 };
    var instance = Test.init(&prog, &.{}, .{});
    try instance.executeAll();
}

test "Registers" {
    const prog = .{
        // set V0 to 40
        0x60,
        40,
        // set V1 to V0
        0x81,
        0x00,
        // add 2 to V0
        0x70,
        2,
    };

    var instance = Test.init(&prog, &.{
        .{ 1, 40 },
        .{ 0, 42 },
    }, .{});

    try instance.executeAll();
}

test "Multiple Registers Operations" {
    const initial_prog = .{
        // set V0 to 6
        0x60,
        5,
        // set V1 to 0
        0x61,
        0,
        // set V2 to 5
        0x62,
        5,
    };

    const initial_registers = .{
        .{ 0, 5 },
        .{ 1, 0 },
        .{ 2, 5 },
    };

    // TODO: more tests
    // each one of these is a program additional to `initial_prog` which tests something
    const additional_progs = .{
        // set V0 to V1
        .{
            // instructions
            .{
                0x80,
                0x10,
            },
            // expections
            .{
                .{ 0, 0 },
            },
        },
        // make V0 equal to 254
        // then add V0 and V2 to V0 (254 + 5)
        .{
            // instructions
            .{
                0x60,
                254,
                0x80,
                0x24,
            },
            // expections
            // carry should be 1
            // and V0 should overflow (259) - 1 bit
            .{ .{ 0xF, 0x1 }, .{ 0, 0b0000011 } },
        },
    };

    comptime var current = 0;

    inline for (additional_progs) |ap| {
        current += 1;
        errdefer std.debug.print("test: 'Multiple Registers Operations', operation {} failed\n", .{current});

        const instrs = ap.@"0";
        const expected = ap.@"1";

        const final = initial_prog ++ instrs;
        var instance = Test.init(&final, &expected, .{});

        try instance.executeCount(3, &initial_registers);
        try instance.executeAll();
    }
}

test "Ambigous Instructions" {
    const prog = .{
        // set V0 to 0b10000010
        0x60,
        0b10000010,
        // set V1 to 4
        0x61,
        1,
        // shift V0 to the left (or set V0 to V1 and shift to the right)
        0x80,
        0x1E,
        // shift V0 to the right (or set V0 to V1 and shift to the right)
        0x80,
        0x16,
    };

    var chip8_super_instance = Test.init(&prog, &.{}, .{ .super = true });
    var chip8_instance = Test.init(&prog, &.{}, .{ .super = false });

    const initial_registers = .{
        .{ 0, 0b10000010 },
        .{ 1, 1 },
    };

    try chip8_super_instance.executeCount(2, &initial_registers);
    try chip8_instance.executeCount(2, &initial_registers);

    // the Chip8 would set V0 to V1 before shifting while the Chip8-Super wouldn't do the same

    // shift left test
    try chip8_super_instance.executeOnce(&.{
        .{ 0, 4 },
        .{ 0xF, 1 },
    });
    try chip8_instance.executeOnce(&.{
        .{ 0, 2 },
        .{ 0xF, 0 },
    });

    // shift right test
    try chip8_super_instance.executeOnce(&.{
        .{ 0, 2 },
        .{ 0xF, 0 },
    });
    try chip8_instance.executeOnce(&.{
        .{ 0, 0 },
        .{ 0xF, 1 },
    });
}
