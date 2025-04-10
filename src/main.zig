// FIXME: I made initRlWindow take an allocator because I wanted it to allocate different buffers for
// Chip-8 (64*16) and Chip-8 Super (128*64) but unfortunately it doesn't work like that.
// maybe it is actually better to allocate here, to save some stack space
var PIXELS_STORAGE: [128 * 64]u8 = undefined;

pub fn main() !void {
    var args = std.process.args();
    _ = args.next();

    const file = args.next() orelse {
        std.debug.print("expected file\n", .{});
        return error.notEnoughArguments;
    };

    var instance = try lib.loadFile(file, .{});
    var fixedBufferAllocator = std.heap.FixedBufferAllocator.init(&PIXELS_STORAGE);

    var window = try lib.display.initRlWindow(&instance, fixedBufferAllocator.allocator());
    try window.run();
}

const std = @import("std");
const lib = @import("zhip8emu_lib");
