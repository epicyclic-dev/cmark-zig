const std = @import("std");

const cmark = @import("cmark");

pub fn main() !void {
    const a = std.heap.page_allocator;
    const parser = try cmark.Parser.init(&a, .{});
    defer parser.deinit();

    parser.feed(
        \\##### Test
        \\
        \\This is a test of *commonmark* **parsing**
        \\
        \\-----
        \\
        \\ * `good`
        \\   * [bye][@@@]
        \\
        \\```
        \\farewell
        \\```
        \\
        \\[@@@]: greetings (
        \\    this is a long url title where I can put whatever I want on and on
        \\    even over many lines
        \\)
        \\
    );

    const node = try parser.finish();
    defer node.deinit();

    const iterator = try node.iterator();
    defer iterator.deinit();

    while (iterator.next()) |visit| {
        std.debug.print("{s} {s}\n", .{ @tagName(visit.event), @tagName(visit.node) });
    }

    std.debug.print("{s}\n", .{try node.render(.html, .{})});
}
