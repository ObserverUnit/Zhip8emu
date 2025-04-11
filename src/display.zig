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

    fn flip(self: Color) Color {
        return switch (self) {
            .background => .foreground,
            .foreground => .background,
        };
    }
};

pub const KeyCode = enum(u4) {
    Key0 = 0,
    Key1 = 1,
    Key2 = 2,
    Key3 = 3,
    Key4 = 4,
    Key5 = 5,
    Key6 = 6,
    Key7 = 7,
    Key8 = 8,
    Key9 = 9,
    KeyA = 0xA,
    KeyB = 0xB,
    KeyC = 0xC,
    KeyD = 0xD,
    KeyE = 0xE,
    KeyF = 0xF,

    pub inline fn fromInt(i: u4) KeyCode {
        return @enumFromInt(i);
    }

    pub inline fn fromChar(char: u8) ?KeyCode {
        return switch (char) {
            '0'...'9' => KeyCode.fromInt(@truncate(char - '0')),
            'A'...'F' => KeyCode.fromInt(@truncate(char - 'A' + 0xA)),
            'a'...'f' => KeyCode.fromInt(@truncate(char - 'a' + 0xA)),
            else => null,
        };
    }

    pub inline fn intoChar(self: KeyCode) u8 {
        const int: u4 = @intFromEnum(self);

        return switch (int) {
            0...9 => @as(u8, int) + '0',
            0xA...0xF => @as(u8, int) - 0xA + 'A',
        };
    }
    pub inline fn intoRlKey(self: KeyCode) rl.KeyboardKey {
        const char = self.intoChar();
        // TODO: make a configurable keymap
        return @enumFromInt(char);
    }
};

pub const Window = struct {
    allocator: std.mem.Allocator,
    state: *emu.State,
    loop: *const fn (
        self: *Window,
    ) emu.ExecutionError!void,
    is_keypressed: *const fn (code: KeyCode) bool,
    get_keypressed: *const fn () ?KeyCode,
    pixels: *[64][128]Color,

    const Self = @This();
    const pixelScale = 16;

    pub fn fill(self: *Self, color: Color) void {
        for (self.pixels) |*row| {
            for (row) |*pixel| {
                pixel.* = color;
            }
        }
    }

    /// Toggles a pixel from On to Off and from Off to On
    /// returns true if a pixel was turned to Off
    pub fn togglePixel(self: *Self, x: u8, y: u8) bool {
        const pixel = &self.pixels[y][x];
        pixel.* = pixel.flip();
        return if (pixel.* == .background) true else false;
    }

    pub fn run(self: *Window) emu.ExecutionError!void {
        return self.loop(self);
    }

    pub fn getKeyPressed(self: *const Self) ?KeyCode {
        return self.get_keypressed();
    }

    pub fn isKeyPressed(self: *const Self, code: KeyCode) bool {
        return self.is_keypressed(code);
    }

    pub fn init(allocator: std.mem.Allocator, state: *emu.State, loop: *const fn (
        self: *Window,
    ) emu.ExecutionError!void, get_keypressed: *const fn () ?KeyCode, is_keypressed: *const fn (code: KeyCode) bool) !Window {
        const pixels = try allocator.create([64][128]Color);
        return .{
            .allocator = allocator,
            .state = state,
            .loop = loop,
            .get_keypressed = get_keypressed,
            .is_keypressed = is_keypressed,
            .pixels = pixels,
        };
    }

    fn deinit(self: *Window) void {
        self.allocator.destroy(self.pixels);
    }
};

fn raylib_is_keypressed(code: KeyCode) bool {
    return rl.isKeyDown(code.intoRlKey());
}

fn raylib_keypressed() ?KeyCode {
    const got: u32 = @bitCast(rl.getCharPressed());
    if (got == 0) return null;
    const c: u8 = @truncate(got);

    return KeyCode.fromChar(c);
}

fn raylib_loop(self: *Window) emu.ExecutionError!void {
    const pixel_scale = Window.pixelScale;
    self.state.setDisplay(self);

    rl.initWindow(1024, 512, "Zhip8emu");
    defer rl.closeWindow();

    rl.setTargetFPS(60);
    while (!rl.windowShouldClose()) {
        try self.state.oneCycle();

        rl.beginDrawing();
        defer rl.endDrawing();

        for (self.pixels, 0..) |row, y| {
            for (row, 0..) |color, x| {
                rl.drawRectangle(@intCast(x * pixel_scale), @intCast(y * pixel_scale), pixel_scale, pixel_scale, color.toRlColor());
            }
        }
    }
}

/// Gives `state` a window which uses raylib internally.
/// The `allocator` is used to allocate memory for storing the pixels there are maximum 128*64 pixels.
pub fn initRlWindow(state: *emu.State, allocator: std.mem.Allocator) !Window {
    return Window.init(allocator, state, raylib_loop, raylib_keypressed, raylib_is_keypressed);
}
