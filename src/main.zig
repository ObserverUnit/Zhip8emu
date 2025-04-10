pub fn main() !void {
    var args = std.process.args();
    _ = args.next();

    const file = args.next() orelse {
        std.debug.print("expected file\n", .{});
        return error.notEnoughArguments;
    };

    var instance = try lib.loadFile(file, .{});
    var window = lib.display.RlWindow(&instance);
    try window.run();
}

const std = @import("std");
const lib = @import("zhip8emu_lib");
