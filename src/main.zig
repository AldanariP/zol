const std = @import("std");
const mibu = @import("mibu");

const World = @import("World.zig");

const SimState = struct {
    timeout: i32,
    paused: bool,
    last_event: mibu.events.Event,

    ui_done: bool,
    ui_fade: u8,
    event_last_ui_draw: u21,
};

const UI_TEXT_MAX_SIZE = 10;
const UI_FADE_FACTOR = 20;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    var stdout_buf: [4096]u8 = undefined;
    const stdout_file = std.fs.File.stdout();
    var stdout_writer = stdout_file.writer(&stdout_buf);
    const stdout = &stdout_writer.interface;

    const stdin_file = std.fs.File.stdin();

    if (!std.posix.isatty(stdin_file.handle)) {
        try stdout.print("The current file descriptor is not referring to a terminal\n", .{});
        return;
    }

    var raw_term = try mibu.term.enableRawMode(stdin_file.handle);
    defer raw_term.disableRawMode() catch {};

    var term_size = try mibu.term.getSize(stdin_file.handle);

    var seed: u64 = undefined;
    try std.posix.getrandom(std.mem.asBytes(&seed));
    var world = try World.initRandom(alloc, term_size.width, term_size.height, seed);
    defer world.deinit(alloc);

    try init_screen(stdout);
    defer deinit_screen(stdout) catch {};

    try render_world(stdout, world);

    var state: SimState = .{
        .paused = true,
        .timeout = 50,
        .last_event = undefined,

        .ui_done = false,
        .ui_fade = 255,
        .event_last_ui_draw = undefined,
    };

    main: while(true) {
        state.last_event = try mibu.events.nextWithTimeout(stdin_file, state.timeout);

        // controls
        switch (state.last_event) {
            .key => |k| switch (k.code) {
                .char => |char| {
                    switch(char) {
                        'q' => break: main,

                        'p' => state.paused = !state.paused,

                        '+' => state.timeout -= 10,
                        '-' => state.timeout += 10,

                        'n' => {
                            if (state.paused) {
                                world.update();
                                try render_world(stdout, world);
                            }
                        },
                        else => continue
                    }
                    state.ui_done = false;
                },
                else => continue
            },
            .resize => {
                term_size = try mibu.term.getSize(stdin_file.handle);
                world.resize(term_size.width, term_size.height); // not implemented
            },
            else => {}
        }

        if (!state.paused) {
            world.update();
            try render_world(stdout, world);
        }
        if (!state.ui_done) {
            state.ui_done = try render_ui(stdout, &state);
        }

        try stdout.flush();
    }
}


/////////////// SCREEN FUNCTIONS \\\\\\\\\\\\\\\
fn init_screen(writer: *std.Io.Writer) !void {
    try mibu.term.enterAlternateScreen(writer);
    try mibu.cursor.hide(writer);
    try mibu.cursor.goTo(writer, 0, 1);
    try writer.flush();
}

fn deinit_screen(writer: *std.Io.Writer) !void {
    try mibu.term.exitAlternateScreen(writer);
    try mibu.cursor.show(writer);
    try writer.flush();
}


fn render_world(writer: *std.Io.Writer, world: World) !void {
    for (world.next, 0..) |cell, i| {
        if (world.prev[i] != cell) {
            try mibu.cursor.goTo(writer, i % world.width, i / world.width);
            const taint = 255 * @as(u8, cell);
            try mibu.color.bgRGB(writer, taint, taint, taint);
            try writer.writeByte(' ');
        }
    }
    try mibu.cursor.goTo(writer, 0, 1);
}

fn render_ui(writer: *std.Io.Writer, state: *SimState) !bool {
    const key = blk: {
        if (state.last_event == .key) {
            state.event_last_ui_draw = state.last_event.key.code.char;
            state.ui_fade = 255;
            break :blk state.last_event.key.code.char;
        } else {
            state.ui_fade -|= UI_FADE_FACTOR;
            break :blk state.event_last_ui_draw;
        }
    };

    const text: ?[:0]const u8 = switch (key) {
        'p' => if (state.paused) "Paused" else "Resume",

        '+' => "Speed +",
        '-' => "Speed -",

        'n' => if (state.paused) "Next" else null,
        else => null,
    };

    if (text) |t| {
        try mibu.color.bgRGB(writer, 0, 0, 0);
        try mibu.color.fgRGB(writer, state.ui_fade, state.ui_fade, state.ui_fade);

        try mibu.cursor.goTo(writer, 0, 1);
        try writer.printUnicodeCodepoint('╭');
        inline for (0..UI_TEXT_MAX_SIZE) |_| try writer.printUnicodeCodepoint('─');
        try writer.printUnicodeCodepoint('╮');

        try mibu.cursor.goTo(writer, 0, 2);
        try writer.print(std.fmt.comptimePrint("│{{s: ^{d}.}}│", .{UI_TEXT_MAX_SIZE}), .{t});

        try mibu.cursor.goTo(writer, 0, 3);
        try writer.printUnicodeCodepoint('╰');
        inline for (0..UI_TEXT_MAX_SIZE) |_| try writer.printUnicodeCodepoint('─');
        try writer.printUnicodeCodepoint('╯');

        try mibu.cursor.goTo(writer , 0, 1);
    }

    return state.ui_fade == 0;
}