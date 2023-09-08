const std = @import("std");

pub const cmark = @cImport({
    @cInclude("cmark.h");
});

const CMarkError = error{
    Failed,
    InvalidDocument,
};

pub const NodeType = enum(c_int) {
    none = cmark.CMARK_NODE_NONE,

    // Block
    document = cmark.CMARK_NODE_DOCUMENT,
    block_quote = cmark.CMARK_NODE_BLOCK_QUOTE,
    list = cmark.CMARK_NODE_LIST,
    item = cmark.CMARK_NODE_ITEM,
    code_block = cmark.CMARK_NODE_CODE_BLOCK,
    html_block = cmark.CMARK_NODE_HTML_BLOCK,
    custom_block = cmark.CMARK_NODE_CUSTOM_BLOCK,
    paragraph = cmark.CMARK_NODE_PARAGRAPH,
    heading = cmark.CMARK_NODE_HEADING,
    thematic_break = cmark.CMARK_NODE_THEMATIC_BREAK,

    // Inline
    text = cmark.CMARK_NODE_TEXT,
    softbreak = cmark.CMARK_NODE_SOFTBREAK,
    linebreak = cmark.CMARK_NODE_LINEBREAK,
    code = cmark.CMARK_NODE_CODE,
    html_inline = cmark.CMARK_NODE_HTML_INLINE,
    custom_inline = cmark.CMARK_NODE_CUSTOM_INLINE,
    emph = cmark.CMARK_NODE_EMPH,
    strong = cmark.CMARK_NODE_STRONG,
    link = cmark.CMARK_NODE_LINK,
    image = cmark.CMARK_NODE_IMAGE,
};

pub const ListType = enum(c_int) {
    no_list = cmark.CMARK_NO_LIST,
    bullet_list = cmark.CMARK_BULLET_LIST,
    ordered_list = cmark.CMARK_ORDERED_LIST,
};

// only for ordered lists
pub const DelimType = enum(c_int) {
    no_delim = cmark.CMARK_NO_DELIM,
    period_delim = cmark.CMARK_PERIOD_DELIM,
    paren_delim = cmark.CMARK_PAREN_DELIM,
};

pub const ParseOptions = packed struct(u32) {
    _skip_0: u8 = 0, // skip index 0-7

    _skip_normalize: bool = false, // index 8; deprecated, no effect,
    validate_utf8: bool = false, // index 9
    smart_quotes_and_dashes: bool = false, // index 10

    _padding: u21 = 0, // skip indices 11-31
};

pub const RenderFormat = enum { xml, html, man, commonmark, latex };

pub const RenderOptions = struct {
    flags: RenderFlags = .{},
    width: c_int = 0,
};

pub const RenderFlags = packed struct(u32) {
    _skip_0: bool = false, // for some reason 1 << 0 is skipped (oversight?)

    include_sourcepos: bool = false, // index 1
    softbreaks_as_hardbreaks: bool = false, // index 2

    _skip_safe: bool = false, // index 3; deprecated, no effect

    softbreaks_as_spaces: bool = false, // index 4

    _skip_1: u12 = 0, // skip index 5-16

    allow_unsafe_html: bool = false, // index 17

    _padding: u14 = 0, // no other options
};

comptime {
    std.debug.assert(@as(u32, @bitCast(RenderFlags{ .include_sourcepos = true })) == cmark.CMARK_OPT_SOURCEPOS);
    std.debug.assert(@as(u32, @bitCast(RenderFlags{ .softbreaks_as_hardbreaks = true })) == cmark.CMARK_OPT_HARDBREAKS);
    std.debug.assert(@as(u32, @bitCast(RenderFlags{ .softbreaks_as_spaces = true })) == cmark.CMARK_OPT_NOBREAKS);
    std.debug.assert(@as(u32, @bitCast(RenderFlags{ .allow_unsafe_html = true })) == cmark.CMARK_OPT_UNSAFE);
    std.debug.assert(@as(u32, @bitCast(ParseOptions{ .validate_utf8 = true })) == cmark.CMARK_OPT_VALIDATE_UTF8);
    std.debug.assert(@as(u32, @bitCast(ParseOptions{ .smart_quotes_and_dashes = true })) == cmark.CMARK_OPT_SMART);
}

const AllocHeader = extern struct {
    size: usize,
    tip: u8,

    inline fn fromAllocatedSlice(slice: []u8) *AllocHeader {
        return @ptrFromInt(@intFromPtr(slice.ptr));
    }

    inline fn fromTipPointer(tip: *u8) *AllocHeader {
        return @fieldParentPtr(AllocHeader, "tip", tip);
    }

    inline fn fullAllocFromTip(tip: *anyopaque) align(@alignOf(AllocHeader)) []u8 {
        const hdr = fromTipPointer(@ptrCast(tip));
        const mem: [*]u8 = @ptrFromInt(@intFromPtr(hdr));
        return mem[0..(@sizeOf(usize) + hdr.size)];
    }
};

fn cmarkCalloc(ctx: ?*anyopaque, size: usize, count: usize) callconv(.C) ?*anyopaque {
    const allocator: *const std.mem.Allocator = @ptrCast(@alignCast(ctx orelse return null));
    const mem_size = size * count;
    const raw_mem = allocator.alignedAlloc(
        u8,
        @alignOf(AllocHeader),
        @sizeOf(usize) + mem_size,
    ) catch return null;

    // cmark does rely on the allocated memory being zeroed, unfortunately. The Zig
    // allocator interface always fills with undefined, and this is not configurable.
    @memset(raw_mem, 0);

    const header = AllocHeader.fromAllocatedSlice(raw_mem);
    header.size = mem_size;
    return &header.tip;
}

fn cmarkRealloc(ctx: ?*anyopaque, mem: ?*anyopaque, new_size: usize) callconv(.C) ?*anyopaque {
    const allocator: *const std.mem.Allocator = @ptrCast(@alignCast(ctx orelse return null));
    if (mem == null) {
        return cmarkCalloc(ctx, 1, new_size);
    }

    const raw_mem = allocator.realloc(AllocHeader.fullAllocFromTip(mem.?), new_size) catch
        return null;

    const header = AllocHeader.fromAllocatedSlice(raw_mem);
    header.size = raw_mem.len;
    return &header.tip;
}

fn cmarkFree(ctx: ?*anyopaque, mem: ?*anyopaque) callconv(.C) void {
    const allocator: *const std.mem.Allocator = @ptrCast(@alignCast(ctx orelse return));
    if (mem == null) return;

    const raw_mem = AllocHeader.fullAllocFromTip(mem.?);
    allocator.free(raw_mem);
}

pub fn wrapCmarkAllocator(allocator: *const std.mem.Allocator) cmark.cmark_mem {
    return .{
        .ctx = @constCast(allocator),
        .calloc = cmarkCalloc,
        .realloc = cmarkRealloc,
        .free = cmarkFree,
    };
}

const CmarkNode = union(enum) {
    document: *CmarkOpaqueNode,
    heading: *CmarkHeadingNode,
    block_quote: *CmarkOpaqueNode,

    bullet_list: *CmarkOpaqueNode,
    ordered_list: *CmarkOrderedListNode,
    item: *CmarkOpaqueNode,

    code_block: *CmarkOpaqueNode,
    html_block: *CmarkOpaqueNode,
    custom_block: *CmarkOpaqueNode,
    thematic_break: *CmarkOpaqueNode,

    paragraph: *CmarkOpaqueNode,
    text: *CmarkOpaqueNode,
    softbreak: *CmarkOpaqueNode,
    linebreak: *CmarkOpaqueNode,

    html_inline: *CmarkOpaqueNode,
    custom_inline: *CmarkOpaqueNode,

    code: *CmarkOpaqueNode,
    emph: *CmarkOpaqueNode,
    strong: *CmarkOpaqueNode,

    link: *CmarkOpaqueNode,
    image: *CmarkOpaqueNode,

    fn fromCNode(c_node: ?*cmark.cmark_node) !CmarkNode {
        const node = c_node orelse return error.Failed;

        switch (@as(NodeType, @enumFromInt(cmark.cmark_node_get_type(@ptrCast(node))))) {
            .none => @panic("none? none??????"),
            .heading => return .{ .heading = @ptrCast(node) },
            .document => return .{ .document = @ptrCast(node) },
            .block_quote => return .{ .block_quote = @ptrCast(node) },
            .list => {
                if (cmark.cmark_node_get_list_type(node) == cmark.CMARK_BULLET_LIST)
                    return .{ .bullet_list = @ptrCast(node) }
                else
                    return .{ .ordered_list = @ptrCast(node) };
            },
            .item => return .{ .item = @ptrCast(node) },
            .code_block => return .{ .code_block = @ptrCast(node) },
            .html_block => return .{ .html_block = @ptrCast(node) },
            .custom_block => return .{ .custom_block = @ptrCast(node) },
            .paragraph => return .{ .paragraph = @ptrCast(node) },
            .thematic_break => return .{ .thematic_break = @ptrCast(node) },
            .text => return .{ .text = @ptrCast(node) },
            .softbreak => return .{ .softbreak = @ptrCast(node) },
            .linebreak => return .{ .linebreak = @ptrCast(node) },
            .code => return .{ .code = @ptrCast(node) },
            .html_inline => return .{ .html_inline = @ptrCast(node) },
            .custom_inline => return .{ .custom_inline = @ptrCast(node) },
            .emph => return .{ .emph = @ptrCast(node) },
            .strong => return .{ .strong = @ptrCast(node) },
            .link => return .{ .link = @ptrCast(node) },
            .image => return .{ .image = @ptrCast(node) },
        }
    }

    pub fn deinit(self: CmarkNode) void {
        switch (self) {
            inline else => |node| {
                cmark.cmark_node_free(@ptrCast(node));
            },
        }
    }

    pub fn render(self: CmarkNode, format: RenderFormat, options: RenderOptions) ![:0]const u8 {
        const unwrapped: *cmark.cmark_node = switch (self) {
            inline else => |node| @ptrCast(node),
        };
        const flags: c_int = @bitCast(options.flags);

        const result: [*:0]const u8 = switch (format) {
            .xml => cmark.cmark_render_xml(unwrapped, flags) orelse return error.Failed,
            .html => cmark.cmark_render_html(unwrapped, flags) orelse return error.Failed,
            .man => cmark.cmark_render_man(unwrapped, flags, options.width) orelse return error.Failed,
            .commonmark => cmark.cmark_render_commonmark(unwrapped, flags, options.width) orelse return error.Failed,
            .latex => cmark.cmark_render_latex(unwrapped, flags, options.width) orelse return error.Failed,
        };

        return std.mem.sliceTo(result, 0);
    }

    pub fn unlink(self: CmarkNode) void {
        switch (self) {
            inline else => |node| {
                cmark.cmark_unlink_node(@ptrCast(node));
            },
        }
    }

    // inserts self before sibling
    pub fn insertBefore(self: CmarkNode, sibling: CmarkNode) !void {
        switch (self) {
            inline else => |node| switch (sibling) {
                inline else => |sib_node| {
                    // C API has the operands swapped
                    if (cmark.cmark_node_insert_before(@ptrCast(sib_node), @ptrCast(node)) != 1)
                        return error.Failed;
                },
            },
        }
    }

    // inserts self after sibling
    pub fn insertAfter(self: CmarkNode, sibling: CmarkNode) !void {
        switch (self) {
            inline else => |node| switch (sibling) {
                inline else => |sib_node| {
                    // C API has the operands swapped
                    if (cmark.cmark_node_insert_after(@ptrCast(sib_node), @ptrCast(node)) != 1)
                        return error.Failed;
                },
            },
        }
    }

    // replace self with new. Does not free self.
    pub fn replaceWith(self: CmarkNode, new: CmarkNode) !void {
        switch (self) {
            inline else => |node| switch (new) {
                inline else => |new_node| {
                    if (cmark.cmark_node_replace(@ptrCast(node), @ptrCast(new_node)) != 1)
                        return error.Failed;
                },
            },
        }
    }

    pub fn prependChild(self: CmarkNode, child: CmarkNode) !void {
        switch (self) {
            inline else => |node| switch (child) {
                inline else => |child_node| {
                    if (cmark.cmark_node_prepend_child(@ptrCast(node), @ptrCast(child_node)) != 1)
                        return error.Failed;
                },
            },
        }
    }

    pub fn appendChild(self: CmarkNode, child: CmarkNode) !void {
        switch (self) {
            inline else => |node| switch (child) {
                inline else => |child_node| {
                    if (cmark.cmark_node_append_child(@ptrCast(node), @ptrCast(child_node)) != 1)
                        return error.Failed;
                },
            },
        }
    }

    pub const NodeIterator = opaque {
        pub const Event = enum(c_int) {
            none = cmark.CMARK_EVENT_NONE,
            done = cmark.CMARK_EVENT_DONE,
            enter = cmark.CMARK_EVENT_ENTER,
            exit = cmark.CMARK_EVENT_EXIT,
            visit, // a new event we introduce for nodes that will never have `exit` called on them to simplify consumer logic
        };

        pub const NodeVisit = struct {
            event: Event,
            node: CmarkNode,
        };

        pub fn deinit(self: *NodeIterator) void {
            cmark.cmark_iter_free(@ptrCast(self));
        }

        pub fn next(self: *NodeIterator) ?NodeVisit {
            const event: Event = @enumFromInt(cmark.cmark_iter_next(@ptrCast(self)));
            switch (event) {
                .done => return null,
                .enter, .exit => |evt| {
                    const node = CmarkNode.fromCNode(cmark.cmark_iter_get_node(@ptrCast(self))) catch unreachable;
                    const entex: Event = switch (node) {
                        .html_block,
                        .thematic_break,
                        .code_block,
                        .text,
                        .softbreak,
                        .linebreak,
                        .code,
                        .html_inline,
                        => .visit,
                        else => evt,
                    };
                    return .{ .event = entex, .node = node };
                },
                .none, .visit => unreachable,
            }
        }

        pub fn resetTo(self: *NodeIterator, target: NodeVisit) void {
            switch (target.node) {
                inline else => |node| {
                    cmark.cmark_iter_reset(
                        @ptrCast(self),
                        @ptrCast(node),
                        @intFromEnum(target.event),
                    );
                },
            }
        }

        pub fn root(self: *NodeIterator) CmarkNode {
            return CmarkNode.fromCNode(cmark.cmark_iter_get_root(@ptrCast(self))) catch unreachable;
        }
    };

    pub fn iterator(self: CmarkNode) !*NodeIterator {
        switch (self) {
            inline else => |node| {
                const iter: *cmark.cmark_iter = cmark.cmark_iter_new(@ptrCast(node)) orelse
                    return error.Failed;
                return @ptrCast(iter);
            },
        }
    }
};

pub fn CmarkNodeCommon(comptime Self: type) type {
    return struct {
        pub fn getUserData(self: *Self) ?*anyopaque {
            return @ptrCast(cmark.cmark_node_get_user_data(@ptrCast(self)));
        }

        pub fn setUserData(self: *Self, user_data: ?*anyopaque) bool {
            return cmark.cmark_node_set_user_data(@ptrCast(self), user_data) == 1;
        }
    };
}

pub fn CmarkBlockNodeContents(comptime Self: type) type {
    return struct {
        pub fn getContent(self: *Self) [:0]const u8 {
            return cmark.cmark_node_get_literal(@ptrCast(self));
        }

        pub fn setContent(self: *Self, new: [:0]const u8) bool {
            return cmark.cmark_node_set_literal(@ptrCast(self), new.ptr);
        }
    };
}

pub const CmarkOpaqueNode = opaque {
    pub usingnamespace CmarkNodeCommon(@This());
};

pub const CmarkHeadingNode = opaque {
    pub fn getLevel(self: *CmarkHeadingNode) i3 {
        return @intCast(cmark.cmark_node_get_heading_level(@ptrCast(self)));
    }

    pub fn setLevel(self: *CmarkHeadingNode, level: i3) !void {
        if (cmark.cmark_node_set_heading_level(@ptrCast(self), level) != 1)
            return error.Failed;
    }

    pub usingnamespace CmarkNodeCommon(@This());
};

pub const CmarkOrderedListNode = opaque {
    pub fn getDelimeter(self: *CmarkOrderedListNode) DelimType {
        return @enumFromInt(cmark.cmark_node_get_list_delim(@ptrCast(self)));
    }

    pub fn setDelimiter(self: *CmarkOrderedListNode, new: DelimType) !void {
        if (cmark.cmark_node_set_list_delim(@ptrCast(self), @intFromEnum(new)) != 1)
            return error.Failed;
    }

    pub fn getStart(self: *CmarkOrderedListNode) i32 {
        return @intCast(cmark.cmark_node_get_list_start(@ptrCast(self)));
    }

    pub fn setStart(self: *CmarkOrderedListNode, start: i32) !void {
        if (cmark.cmark_node_get_list_start(@ptrCast(self), @intCast(start)) != 1)
            return error.Failed;
    }

    pub fn getTight(self: *CmarkOrderedListNode) bool {
        return cmark.cmark_node_get_list_start(@ptrCast(self)) == 1;
    }

    pub fn setTight(self: *CmarkOrderedListNode, tight: bool) !void {
        if (cmark.cmark_node_get_list_start(@ptrCast(self), @intFromBool(tight)) != 1)
            return error.Failed;
    }

    pub usingnamespace CmarkNodeCommon(@This());
};

pub const CmarkCodeBlockNode = opaque {
    pub fn getFenceInfo(self: *CmarkHeadingNode) [:0]const u8 {
        const str: [*:0]const u8 = cmark.cmark_node_get_fence_info(@ptrCast(self)) orelse
            return error.Failed;

        return std.mem.sliceTo(str, 0);
    }

    pub fn setFenceInfo(self: *CmarkHeadingNode, info: [:0]const u8) !void {
        if (cmark.cmark_node_set_fence_info(@ptrCast(self), info.ptr) != 1)
            return error.Failed;
    }

    pub usingnamespace CmarkNodeCommon(@This());
};

pub const Parser = struct {
    allocator: *const std.mem.Allocator,
    _cmark_mem: *cmark.cmark_mem,
    _parser: *cmark.cmark_parser,

    pub fn init(allocator: *const std.mem.Allocator, options: ParseOptions) !Parser {
        // we need a pointer to an allocator because the C api wrapper needs a pointer
        // and it also has to escape the stack life of this function.
        var self: Parser = .{
            .allocator = allocator,
            ._cmark_mem = undefined,
            ._parser = undefined,
        };

        // this has to be heap allocated because otherwise the cmark internal object
        // ends up holding a reference to a stack copy that dies with this function.
        self._cmark_mem = try allocator.create(cmark.cmark_mem);
        self._cmark_mem.* = wrapCmarkAllocator(self.allocator);

        self._parser = cmark.cmark_parser_new_with_mem(
            @bitCast(options),
            self._cmark_mem,
        ) orelse return error.OutOfMemory;

        return self;
    }

    pub fn initWithWrappedAllocator(mem: *cmark.cmark_mem, options: ParseOptions) !Parser {
        return cmark.cmark_parser_new_with_mem(
            @bitCast(options),
            mem,
        ) orelse error.OutOfMemory;
    }

    pub fn feed(self: Parser, buffer: []const u8) void {
        cmark.cmark_parser_feed(self._parser, buffer.ptr, buffer.len);
    }

    pub fn finish(self: Parser) !CmarkNode {
        return CmarkNode.fromCNode(
            cmark.cmark_parser_finish(self._parser) orelse
                return error.InvalidDocument,
        );
    }

    pub fn deinit(self: Parser) void {
        self.deinitParser();
        self.allocator.destroy(self._cmark_mem);
    }

    pub fn deinitParser(self: Parser) void {
        cmark.cmark_parser_free(self._parser);
    }
};

// the nodes hang on to a reference to the allocator, which does not play nicely at all
// with our allocator wrapping strategy. Basically, the parser has to live through
// node rendering. Due to this, it probably makes sense to keep a hard association
// between the parser and the node tree.
pub fn parse(allocator: *std.mem.Allocator, buffer: []const u8, options: ParseOptions) !CmarkNode {
    const parser = try Parser.init(allocator, options);
    defer parser.deinitParser();

    parser.feed(buffer);

    return try parser.finish();
}

// pub fn parseFile(allocator: std.mem.Allocator, path: []const u8, options: ParseOptions) !CmarkNode

pub fn main() !void {
    const a = std.heap.page_allocator;
    const parser = try Parser.init(&a, .{});
    defer parser.deinit();

    parser.feed(
        \\###### Test
        \\
        \\This is a test of *commonmark* **parsing**
        \\
        \\---
        \\
        \\ * `good`
        \\ * [bye](bye)
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
