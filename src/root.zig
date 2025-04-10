const std = @import("std");
pub const emu = @import("emu/root.zig");
pub const display = @import("display.zig");

pub fn loadBytes(bytes: []const u8, flags: emu.Chip8Flags) emu.State {
    return emu.State.load(bytes, flags);
}

pub fn loadFile(path: []const u8, flags: emu.Chip8Flags) !emu.State {
    const file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
    defer file.close();

    const bytes = try file.readToEndAlloc(std.heap.page_allocator, std.math.maxInt(usize));
    return loadBytes(bytes, flags);
}
