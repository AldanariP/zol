const std = @import("std");
const mibu = @import("mibu");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    var stdout_buf: [1024]u8 = undefined;
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

    const term_size = try mibu.term.getSize(stdin_file.handle);

    const width: usize = term_size.width;
    const height: usize = term_size.height;

    const world = try alloc.alloc(u1, width * height);
    defer alloc.free(world);

    @memset(world, 0);
    const next_world = try alloc.dupe(u1, world);
    defer alloc.free(next_world);

    var prng: std.Random.DefaultPrng = .init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    }); 
    const rand = prng.random();
    for (world) |*cell| cell.* = rand.int(u1); 
 
    try init_screen(stdout);
    defer deinit_screen(stdout) catch {};

    try render_screen(stdout, world);

    var paused = true;
    var timeout: i32 = 50;

    main: while(true) {
        const next = if (paused) 
            try mibu.events.next(stdin_file)
         else 
            try mibu.events.nextWithTimeout(stdin_file, timeout);

        switch (next) {
            .key => |k| switch (k.code) {
                .char => |char| {
                    switch(char) {
                        'q' => break: main,
                        
                        'p' => paused = !paused,

                        '+' => timeout -= 10,
                        '-' => timeout += 10,

                        'n' => {},
                        else => continue
                    }
                },
                else => continue
            },
            else => {}
        }

        {   // render world pipline
            update_world(world, next_world, width);
            try render_screen(stdout, next_world);
            @memcpy(world, next_world);
            @memset(next_world, 0);
        }
    }
}

fn update_world(old_world: []const u1, new_world: []u1, width: usize) void {
    var mask: u8 = 0b111_11_111; // Center
    var i: usize = width + 1;
    while (i < old_world.len - width - 1): (i += 1) {
        if (i % width == 0) i += 1; // skip left border

        update_at(old_world, new_world, width, mask, i);

        if (i % width == width - 1) i += 1; // skip right border
    }

    mask = 0b000_11_111; // Top Border
    i = 1;
    while (i < width - 1): (i += 1) update_at(old_world, new_world, width, mask, i);

    mask = 0b111_11_000; // Bottom Border
    i = old_world.len - width + 1;
    while (i < old_world.len - 1): (i += 1) update_at(old_world, new_world, width, mask, i);

    mask = 0b011_01_011; // Left Border
    i = width;
    while (i < old_world.len - width): (i += width) update_at(old_world, new_world, width, mask, i);

    mask = 0b110_10_110; // Right Border
    i = width + width - 1;
    while (i < old_world.len - 1): (i += width) update_at(old_world, new_world, width, mask, i);
    
    mask = 0b000_01_011; // Top Left Corner
    update_at(old_world, new_world, width, mask, 0);

    mask = 0b000_10_110; // Top Right Corner
    update_at(old_world, new_world, width, mask, width - 1);

    mask = 0b011_01_000; // Bottom Left Corner
    update_at(old_world, new_world, width, mask, old_world.len - width);

    mask = 0b110_10_000; // Bottom Right Corner
    update_at(old_world, new_world, width, mask, old_world.len - 1);
}

fn update_at(old_world: []const u1, new_world: []u1, width: usize, mask: u8, i: usize) void {
    var count: u4 = 0;
    if (mask & 128 > 0) count += old_world[i - width - 1];
    if (mask & 64  > 0) count += old_world[i - width];
    if (mask & 32  > 0) count += old_world[i - width + 1];
    if (mask & 16  > 0) count += old_world[i - 1];
    if (mask & 8   > 0) count += old_world[i + 1];
    if (mask & 4   > 0) count += old_world[i + width - 1];
    if (mask & 2   > 0) count += old_world[i + width];
    if (mask & 1   > 0) count += old_world[i + width + 1];

    new_world[i] = switch(count) {
        0...1 => 0,
        2     => old_world[i],
        3     => 1,
        4...8 => 0,
        else => unreachable
    };
}

/////////////// SCREEN FUNCTIONS \\\\\\\\\\\\\\\
fn init_screen(writer: *std.Io.Writer) !void {
    try mibu.term.enterAlternateScreen(writer);
    try mibu.cursor.hide(writer);
    try mibu.cursor.goTo(writer, 0, 0);
    try writer.flush();
}

fn deinit_screen(writer: *std.Io.Writer) !void {
    try mibu.term.exitAlternateScreen(writer);
    try mibu.cursor.show(writer);
    try writer.flush();
}


fn render_screen(writer: *std.Io.Writer, world: []const u1) !void {
    for (world) |cell| {
        try mibu.color.bg256(writer, if (cell == 1) .white else .black);
        try writer.writeByte(' ');
    }
    try mibu.cursor.goTo(writer, 0, 0);
    try writer.flush();
}
