const rl = @import("raylib");
const emu = @import("emu/root.zig");

pub const Color = enum {
    background,
    foreground,
};

pub const Window = struct {
    state: *emu.State,
    width: u16,
    height: u16,
    fillBackground: *const fn (
        win: *Window,
        color: Color,
    ) void,

    loop: *const fn (
        self: *Window,
    ) emu.ExecutionError!void,

    pub fn run(self: *Window) emu.ExecutionError!void {
        return self.loop(self);
    }
};

fn raylib_loop(self: *Window) emu.ExecutionError!void {
    self.state.setDisplay(self);

    rl.initWindow(self.width, self.height, "Zhip8 Emulator");
    defer rl.closeWindow();

    rl.setTargetFPS(60);
    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();

        try self.state.executeNext();
    }
}

fn raylib_fillBackground(
    self: *Window,
    color: Color,
) void {
    _ = self;

    const rl_color: rl.Color = switch (color) {
        .background => .white,
        .foreground => .black,
    };

    rl.clearBackground(rl_color);
}

/// Gives `state` a window which uses raylib internally.
pub fn RlWindow(state: *emu.State) Window {
    return .{
        .state = state,
        .width = 800,
        .height = 450,
        .fillBackground = raylib_fillBackground,
        .loop = raylib_loop,
    };
}
