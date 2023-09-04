const std = @import("std");

pub const cmark = @cImport({
    @cInclude("cmark.h");
});

const Failed = error.Failed;

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

pub const NodeIteratorEvent = enum(c_int) {
    none = cmark.CMARK_EVENT_NONE,
    done = cmark.CMARK_EVENT_DONE,
    enter = cmark.CMARK_EVENT_ENTER,
    exit = cmark.CMARK_EVENT_EXIT,
};

pub const CmarkOptions = packed struct(u32) {
    _skip_0: bool = false, // for some reason 1 << 0 is skipped (oversight?)

    include_sourcepos: bool = false, // index 1
    softbreaks_as_hardbreaks: bool = false, // index 2

    _skip_safe: bool = false, // index 3; deprecated, no effect

    softbreaks_as_spaces: bool = false, // index 4

    _skip_1: u3 = 0, // skip indices 5, 6 and 7
    _skip_normalize: bool = false, // index 8; deprecated, no effect,

    validate_utf8: bool = false, // index 9
    smart_quotes_and_dashes: bool = false, // index 10

    _skip_2: u6 = 0, // skip indices 11, 12, 13, 14, 15, 16

    allow_unsafe_html: bool = false, // index 17

    _padding: u14 = 0, // no other options
};

comptime {
    std.debug.assert(@as(u32, @bitCast(CmarkOptions{ .include_sourcepos = true })) == cmark.CMARK_OPT_SOURCEPOS);
    std.debug.assert(@as(u32, @bitCast(CmarkOptions{ .softbreaks_as_hardbreaks = true })) == cmark.CMARK_OPT_HARDBREAKS);
    std.debug.assert(@as(u32, @bitCast(CmarkOptions{ .softbreaks_as_spaces = true })) == cmark.CMARK_OPT_NOBREAKS);
    std.debug.assert(@as(u32, @bitCast(CmarkOptions{ .validate_utf8 = true })) == cmark.CMARK_OPT_VALIDATE_UTF8);
    std.debug.assert(@as(u32, @bitCast(CmarkOptions{ .smart_quotes_and_dashes = true })) == cmark.CMARK_OPT_SMART);
    std.debug.assert(@as(u32, @bitCast(CmarkOptions{ .allow_unsafe_html = true })) == cmark.CMARK_OPT_UNSAFE);
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

fn wrapCmarkAllocator(allocator: *const std.mem.Allocator) cmark.cmark_mem {
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

    pub fn new(allocator: *const std.mem.Allocator, options: CmarkOptions) !Parser {
        var self: Parser = .{
            .allocator = allocator,
            ._cmark_mem = undefined,
            ._parser = undefined,
        };

        self._cmark_mem = try allocator.create(cmark.cmark_mem);
        self._cmark_mem.* = wrapCmarkAllocator(self.allocator);

        self._parser = cmark.cmark_parser_new_with_mem(
            @bitCast(options),
            self._cmark_mem,
        ) orelse return error.OutOfMemory;

        return self;
    }

    pub fn feed(self: Parser, buffer: []const u8) void {
        cmark.cmark_parser_feed(self._parser, buffer.ptr, buffer.len);
    }

    pub fn finish(self: Parser) CmarkNode {
        return CmarkNode.fromCNode(cmark.cmark_parser_finish(self._parser));
    }

    pub fn deinit(self: Parser) void {
        cmark.cmark_parser_free(self._parser);
        self.allocator.destroy(self._cmark_mem);
    }
};

// pub fn parse(buffer: []const u8, options: CmarkOptions) !CmarkNode
// pub fn parseFile(path: []const u8, options: CmarkOptions) !CmarkNode

pub fn main() void {
    const a = std.heap.page_allocator;
    const parser = Parser.new(&a, .{}) catch @panic("noop");
    defer parser.deinit();
}
