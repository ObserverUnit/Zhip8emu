const std = @import("std");
pub const emu = @import("emu/root.zig");

pub fn loadBytes(bytes: []const u8, flags: emu.Chip8Flags) emu.State {
    return emu.State.load(bytes, flags);
}
