const rl = @import("raylib");
const emu = @import("emu/root.zig");
const std = @import("std");

pub const Color = enum {
    background,
    foreground,

    /// Converts the color to a Raylib color.
    fn toRlColor(self: Color) rl.Color {
        return switch (self) {
            .background => .black,
            .foreground => .white,
        };
    }
};

pub const Window = struct {
    allocator: std.mem.Allocator,
    state: *emu.State,
    loop: *const fn (
        self: *Window,
    ) emu.ExecutionError!void,
    pixels: *[128][64]Color,

    const Self = @This();
    const pixelScale = 16;

    pub fn fill(self: *Self, color: Color) void {
        for (self.pixels) |*row| {
            for (row) |*pixel| {
                pixel.* = color;
            }
        }
    }

    pub fn setPixel(self: *Self, x: u8, y: u8, color: Color) void {
        self.pixels[y][x] = color;
    }

    pub fn run(self: *Window) emu.ExecutionError!void {
        return self.loop(self);
    }

    pub fn init(allocator: std.mem.Allocator, state: *emu.State, loop: *const fn (
        self: *Window,
    ) emu.ExecutionError!void) !Window {
        const pixels = try allocator.create([128][64]Color);
        return .{
            .allocator = allocator,
            .state = state,
            .loop = loop,
            .pixels = pixels,
        };
    }

    fn deinit(self: *Window) void {
        self.allocator.destroy(self.pixels);
    }
};

fn raylib_loop(self: *Window) emu.ExecutionError!void {
    const pixel_scale = Window.pixelScale;
    self.state.setDisplay(self);

    rl.initWindow(1024, 512, "Zhip8emu");
    defer rl.closeWindow();

    rl.setTargetFPS(60);
    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();

        try self.state.executeNext();

        for (self.pixels, 0..) |row, y| {
            for (row, 0..) |color, x| {
                if (color != .background)
                    rl.drawRectangle(@intCast(x * pixel_scale), @intCast(y * pixel_scale), pixel_scale, pixel_scale, color.toRlColor());
            }
        }
    }
}

/// Gives `state` a window which uses raylib internally.
/// The `allocator` is used to allocate memory for storing the pixels there are maximum 128*64 pixels.
pub fn initRlWindow(state: *emu.State, allocator: std.mem.Allocator) !Window {
    return Window.init(allocator, state, raylib_loop);
}
