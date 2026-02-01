const std = @import("std");

const Self = @This();

prev: []u1,
next: []u1,
width: usize,
height: usize,

fn init(alloc: std.mem.Allocator, width: usize, height: usize) !Self {
    const world = try alloc.alloc(u1, width * height);
    const next = try alloc.alloc(u1, width * height);

    return .{
        .prev = world,
        .next = next,
        .width = width,
        .height = height
    };
}

pub fn initEmpty(alloc: std.mem.Allocator, width: usize, height: usize) !Self {
    const self = try Self.init(alloc, width, height);
    @memset(self.next, 0);
    return self;
}

pub fn initRandom(alloc: std.mem.Allocator, width: usize, height: usize, seed: u64) !Self {
    var self = try Self.init(alloc, width, height);
    self.fillRandom(seed);
    return self;
}

pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    alloc.free(self.prev);
    alloc.free(self.next);
}

pub fn update(self: *Self) void {
    @memcpy(self.prev, self.next);

    var mask: u8 = 0b111_11_111; // Center
    var i: usize = self.width + 1;
    while (i < self.prev.len - self.width - 1): (i += 1) {
        if (i % self.width == 0) i += 1; // skip left border

        self.update_at(mask, i);

        if (i % self.width == self.width - 1) i += 1; // skip right border
    }

    mask = 0b000_11_111; // Top Border
    i = 1;
    while (i < self.width - 1): (i += 1) self.update_at(mask, i);

    mask = 0b111_11_000; // Bottom Border
    i = self.prev.len - self.width + 1;
    while (i < self.prev.len - 1): (i += 1) self.update_at(mask, i);

    mask = 0b011_01_011; // Left Border
    i = self.width;
    while (i < self.prev.len - self.width): (i += self.width) self.update_at(mask, i);

    mask = 0b110_10_110; // Right Border
    i = self.width + self.width - 1;
    while (i < self.prev.len - 1): (i += self.width) self.update_at(mask, i);

    mask = 0b000_01_011; // Top Left Corner
    self.update_at(mask, 0);

    mask = 0b000_10_110; // Top Right Corner
    self.update_at(mask, self.width - 1);

    mask = 0b011_01_000; // Bottom Left Corner
    self.update_at(mask, self.prev.len - self.width);

    mask = 0b110_10_000; // Bottom Right Corner
    self.update_at(mask, self.prev.len - 1);
}

fn update_at(self: *Self, mask: u8, cell_idx: usize) void {
    var count: u4 = 0;
    if (mask & 128 > 0) count += self.prev[cell_idx - self.width - 1];
    if (mask & 64  > 0) count += self.prev[cell_idx - self.width];
    if (mask & 32  > 0) count += self.prev[cell_idx - self.width + 1];
    if (mask & 16  > 0) count += self.prev[cell_idx - 1];
    if (mask & 8   > 0) count += self.prev[cell_idx + 1];
    if (mask & 4   > 0) count += self.prev[cell_idx + self.width - 1];
    if (mask & 2   > 0) count += self.prev[cell_idx + self.width];
    if (mask & 1   > 0) count += self.prev[cell_idx + self.width + 1];

    self.next[cell_idx] = switch(count) {
        0...1 => 0,
        2     => self.prev[cell_idx],
        3     => 1,
        4...8 => 0,
        else => unreachable
    };
}

pub fn resize(self: *Self, new_width: usize, new_height: usize) void {
    // TODO
    _ = self;
    _ = new_width;
    _ = new_height;
    return;
}

pub fn fillRandom(self: *Self, seed: u64) void {
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();
    for (self.next) |*cell| cell.* = rand.int(u1);
}