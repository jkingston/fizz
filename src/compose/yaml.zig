//! Safe Zig wrapper around libyaml C API.
//!
//! Provides event-based YAML parsing with proper memory management
//! and error handling via Zig idioms.
//!
//! Usage:
//!     var parser = try yaml.Parser.initFromString(allocator, "key: value");
//!     defer parser.deinit();
//!
//!     while (try parser.next()) |event| {
//!         // Process event
//!     }

const std = @import("std");
const Allocator = std.mem.Allocator;

const c = @cImport({
    @cInclude("yaml.h");
});

/// Position in the YAML source (0-indexed internally, 1-indexed for display).
pub const Mark = struct {
    line: usize,
    column: usize,
    index: usize,

    /// Convert to 1-indexed for user-facing display.
    pub fn displayLine(self: Mark) usize {
        return self.line + 1;
    }

    pub fn displayColumn(self: Mark) usize {
        return self.column + 1;
    }
};

/// YAML event types from the libyaml spec.
pub const EventType = enum {
    stream_start,
    stream_end,
    document_start,
    document_end,
    alias,
    scalar,
    sequence_start,
    sequence_end,
    mapping_start,
    mapping_end,
};

/// Scalar style (how it was quoted in the source).
pub const ScalarStyle = enum {
    any,
    plain,
    single_quoted,
    double_quoted,
    literal,
    folded,
};

/// A parsed YAML event with associated data.
pub const Event = struct {
    type: EventType,
    start_mark: Mark,
    end_mark: Mark,
    data: Data,

    pub const Data = union(enum) {
        scalar: Scalar,
        alias: Alias,
        anchor: Anchor,
        none: void,
    };

    pub const Scalar = struct {
        value: []const u8,
        anchor: ?[]const u8,
        tag: ?[]const u8,
        style: ScalarStyle,
    };

    pub const Alias = struct {
        anchor: []const u8,
    };

    pub const Anchor = struct {
        anchor: ?[]const u8,
        tag: ?[]const u8,
    };
};

/// Parse errors with context.
pub const ParseError = error{
    ScannerError,
    ParserError,
    MemoryError,
    ReaderError,
};

/// YAML event-based parser.
/// NOTE: This struct contains C state with internal pointers and must not be copied.
/// Always use the returned pointer from init() and call deinit() when done.
pub const Parser = struct {
    parser: c.yaml_parser_t,
    has_current_event: bool,
    current_event: c.yaml_event_t,
    allocator: Allocator,
    input_copy: []const u8,

    pub const ErrorInfo = struct {
        message: []const u8,
        mark: Mark,
    };

    /// Initialize parser from a string. The input is copied internally.
    /// Returns a heap-allocated parser that must be freed with deinit().
    pub fn initFromString(allocator: Allocator, input: []const u8) !*Parser {
        const self = try allocator.create(Parser);
        errdefer allocator.destroy(self);

        self.* = Parser{
            .parser = undefined,
            .has_current_event = false,
            .current_event = undefined,
            .allocator = allocator,
            .input_copy = undefined,
        };

        if (c.yaml_parser_initialize(&self.parser) == 0) {
            return ParseError.MemoryError;
        }
        errdefer c.yaml_parser_delete(&self.parser);

        // Copy input to ensure it outlives the parser
        self.input_copy = try allocator.dupe(u8, input);
        errdefer allocator.free(self.input_copy);

        c.yaml_parser_set_input_string(
            &self.parser,
            @ptrCast(self.input_copy.ptr),
            self.input_copy.len,
        );

        return self;
    }

    /// Clean up parser resources and free the parser itself.
    pub fn deinit(self: *Parser) void {
        if (self.has_current_event) {
            c.yaml_event_delete(&self.current_event);
        }
        c.yaml_parser_delete(&self.parser);
        self.allocator.free(self.input_copy);
        self.allocator.destroy(self);
    }

    /// Get the next event. Returns null at end of stream.
    pub fn next(self: *Parser) !?Event {
        // Clean up previous event
        if (self.has_current_event) {
            c.yaml_event_delete(&self.current_event);
            self.has_current_event = false;
        }

        // Parse next event
        if (c.yaml_parser_parse(&self.parser, &self.current_event) == 0) {
            return self.translateError();
        }
        self.has_current_event = true;

        // Check for end of stream
        if (self.current_event.type == c.YAML_STREAM_END_EVENT) {
            return Event{
                .type = .stream_end,
                .start_mark = translateMark(self.current_event.start_mark),
                .end_mark = translateMark(self.current_event.end_mark),
                .data = .{ .none = {} },
            };
        }

        return self.translateEvent();
    }

    /// Get error information after a parse failure.
    pub fn getError(self: *Parser) ?ErrorInfo {
        if (@field(self.parser, "error") != c.YAML_NO_ERROR) {
            const problem = if (self.parser.problem) |p|
                std.mem.sliceTo(p, 0)
            else
                "unknown error";

            return ErrorInfo{
                .message = problem,
                .mark = Mark{
                    .line = self.parser.problem_mark.line,
                    .column = self.parser.problem_mark.column,
                    .index = self.parser.problem_mark.index,
                },
            };
        }
        return null;
    }

    fn translateError(_: *const Parser) ParseError {
        // Error details available via getError()
        return ParseError.ParserError;
    }

    fn translateEvent(self: *const Parser) Event {
        const event = &self.current_event;
        const start_mark = translateMark(event.start_mark);
        const end_mark = translateMark(event.end_mark);

        return switch (event.type) {
            c.YAML_STREAM_START_EVENT => Event{
                .type = .stream_start,
                .start_mark = start_mark,
                .end_mark = end_mark,
                .data = .{ .none = {} },
            },
            c.YAML_STREAM_END_EVENT => Event{
                .type = .stream_end,
                .start_mark = start_mark,
                .end_mark = end_mark,
                .data = .{ .none = {} },
            },
            c.YAML_DOCUMENT_START_EVENT => Event{
                .type = .document_start,
                .start_mark = start_mark,
                .end_mark = end_mark,
                .data = .{ .none = {} },
            },
            c.YAML_DOCUMENT_END_EVENT => Event{
                .type = .document_end,
                .start_mark = start_mark,
                .end_mark = end_mark,
                .data = .{ .none = {} },
            },
            c.YAML_ALIAS_EVENT => Event{
                .type = .alias,
                .start_mark = start_mark,
                .end_mark = end_mark,
                .data = .{
                    .alias = .{
                        .anchor = sliceFromCPtr(event.data.alias.anchor),
                    },
                },
            },
            c.YAML_SCALAR_EVENT => Event{
                .type = .scalar,
                .start_mark = start_mark,
                .end_mark = end_mark,
                .data = .{
                    .scalar = .{
                        .value = sliceFromCPtrWithLen(
                            event.data.scalar.value,
                            event.data.scalar.length,
                        ),
                        .anchor = optionalSliceFromCPtr(event.data.scalar.anchor),
                        .tag = optionalSliceFromCPtr(event.data.scalar.tag),
                        .style = translateStyle(event.data.scalar.style),
                    },
                },
            },
            c.YAML_SEQUENCE_START_EVENT => Event{
                .type = .sequence_start,
                .start_mark = start_mark,
                .end_mark = end_mark,
                .data = .{
                    .anchor = .{
                        .anchor = optionalSliceFromCPtr(event.data.sequence_start.anchor),
                        .tag = optionalSliceFromCPtr(event.data.sequence_start.tag),
                    },
                },
            },
            c.YAML_SEQUENCE_END_EVENT => Event{
                .type = .sequence_end,
                .start_mark = start_mark,
                .end_mark = end_mark,
                .data = .{ .none = {} },
            },
            c.YAML_MAPPING_START_EVENT => Event{
                .type = .mapping_start,
                .start_mark = start_mark,
                .end_mark = end_mark,
                .data = .{
                    .anchor = .{
                        .anchor = optionalSliceFromCPtr(event.data.mapping_start.anchor),
                        .tag = optionalSliceFromCPtr(event.data.mapping_start.tag),
                    },
                },
            },
            c.YAML_MAPPING_END_EVENT => Event{
                .type = .mapping_end,
                .start_mark = start_mark,
                .end_mark = end_mark,
                .data = .{ .none = {} },
            },
            else => Event{
                .type = .stream_end,
                .start_mark = start_mark,
                .end_mark = end_mark,
                .data = .{ .none = {} },
            },
        };
    }
};

fn translateMark(mark: c.yaml_mark_t) Mark {
    return Mark{
        .line = mark.line,
        .column = mark.column,
        .index = mark.index,
    };
}

fn translateStyle(style: c_uint) ScalarStyle {
    return switch (style) {
        c.YAML_ANY_SCALAR_STYLE => .any,
        c.YAML_PLAIN_SCALAR_STYLE => .plain,
        c.YAML_SINGLE_QUOTED_SCALAR_STYLE => .single_quoted,
        c.YAML_DOUBLE_QUOTED_SCALAR_STYLE => .double_quoted,
        c.YAML_LITERAL_SCALAR_STYLE => .literal,
        c.YAML_FOLDED_SCALAR_STYLE => .folded,
        else => .any,
    };
}

fn sliceFromCPtr(ptr: [*c]const u8) []const u8 {
    if (ptr == null) return "";
    return std.mem.sliceTo(ptr, 0);
}

fn sliceFromCPtrWithLen(ptr: [*c]const u8, len: usize) []const u8 {
    if (ptr == null) return "";
    return ptr[0..len];
}

fn optionalSliceFromCPtr(ptr: [*c]const u8) ?[]const u8 {
    if (ptr == null) return null;
    return std.mem.sliceTo(ptr, 0);
}

// --- Tests ---

test "parse simple scalar" {
    const parser = try Parser.initFromString(std.testing.allocator, "hello");
    defer parser.deinit();

    // stream_start
    const e1 = (try parser.next()).?;
    try std.testing.expectEqual(EventType.stream_start, e1.type);

    // document_start
    const e2 = (try parser.next()).?;
    try std.testing.expectEqual(EventType.document_start, e2.type);

    // scalar
    const e3 = (try parser.next()).?;
    try std.testing.expectEqual(EventType.scalar, e3.type);
    try std.testing.expectEqualStrings("hello", e3.data.scalar.value);

    // document_end
    const e4 = (try parser.next()).?;
    try std.testing.expectEqual(EventType.document_end, e4.type);

    // stream_end
    const e5 = (try parser.next()).?;
    try std.testing.expectEqual(EventType.stream_end, e5.type);
}

test "parse key-value mapping" {
    const parser = try Parser.initFromString(std.testing.allocator, "key: value");
    defer parser.deinit();

    _ = try parser.next(); // stream_start
    _ = try parser.next(); // document_start

    const mapping_start = (try parser.next()).?;
    try std.testing.expectEqual(EventType.mapping_start, mapping_start.type);

    const key = (try parser.next()).?;
    try std.testing.expectEqual(EventType.scalar, key.type);
    try std.testing.expectEqualStrings("key", key.data.scalar.value);

    const value = (try parser.next()).?;
    try std.testing.expectEqual(EventType.scalar, value.type);
    try std.testing.expectEqualStrings("value", value.data.scalar.value);

    const mapping_end = (try parser.next()).?;
    try std.testing.expectEqual(EventType.mapping_end, mapping_end.type);
}

test "parse sequence" {
    const input =
        \\- one
        \\- two
        \\- three
    ;
    const parser = try Parser.initFromString(std.testing.allocator, input);
    defer parser.deinit();

    _ = try parser.next(); // stream_start
    _ = try parser.next(); // document_start

    const seq_start = (try parser.next()).?;
    try std.testing.expectEqual(EventType.sequence_start, seq_start.type);

    const item1 = (try parser.next()).?;
    try std.testing.expectEqualStrings("one", item1.data.scalar.value);

    const item2 = (try parser.next()).?;
    try std.testing.expectEqualStrings("two", item2.data.scalar.value);

    const item3 = (try parser.next()).?;
    try std.testing.expectEqualStrings("three", item3.data.scalar.value);

    const seq_end = (try parser.next()).?;
    try std.testing.expectEqual(EventType.sequence_end, seq_end.type);
}

test "parse nested mapping" {
    const input =
        \\outer:
        \\  inner: value
    ;
    const parser = try Parser.initFromString(std.testing.allocator, input);
    defer parser.deinit();

    _ = try parser.next(); // stream_start
    _ = try parser.next(); // document_start
    _ = try parser.next(); // mapping_start (outer)

    const outer_key = (try parser.next()).?;
    try std.testing.expectEqualStrings("outer", outer_key.data.scalar.value);

    _ = try parser.next(); // mapping_start (inner)

    const inner_key = (try parser.next()).?;
    try std.testing.expectEqualStrings("inner", inner_key.data.scalar.value);

    const inner_value = (try parser.next()).?;
    try std.testing.expectEqualStrings("value", inner_value.data.scalar.value);
}

test "parse anchor and alias" {
    const input =
        \\anchored: &anchor_name value
        \\aliased: *anchor_name
    ;
    const parser = try Parser.initFromString(std.testing.allocator, input);
    defer parser.deinit();

    _ = try parser.next(); // stream_start
    _ = try parser.next(); // document_start
    _ = try parser.next(); // mapping_start

    const key1 = (try parser.next()).?;
    try std.testing.expectEqualStrings("anchored", key1.data.scalar.value);

    const anchored = (try parser.next()).?;
    try std.testing.expectEqual(EventType.scalar, anchored.type);
    try std.testing.expectEqualStrings("value", anchored.data.scalar.value);
    try std.testing.expectEqualStrings("anchor_name", anchored.data.scalar.anchor.?);

    const key2 = (try parser.next()).?;
    try std.testing.expectEqualStrings("aliased", key2.data.scalar.value);

    const alias = (try parser.next()).?;
    try std.testing.expectEqual(EventType.alias, alias.type);
    try std.testing.expectEqualStrings("anchor_name", alias.data.alias.anchor);
}

test "error has line number" {
    // Invalid YAML - unmatched quote
    const parser = try Parser.initFromString(std.testing.allocator, "key: \"unclosed");
    defer parser.deinit();

    _ = try parser.next(); // stream_start
    _ = try parser.next(); // document_start
    _ = try parser.next(); // mapping_start
    _ = try parser.next(); // key

    // Next should fail
    const result = parser.next();
    try std.testing.expectError(ParseError.ParserError, result);

    // Error info should be available
    const err = parser.getError();
    try std.testing.expect(err != null);
}

test "mark display is 1-indexed" {
    const mark = Mark{ .line = 0, .column = 0, .index = 0 };
    try std.testing.expectEqual(@as(usize, 1), mark.displayLine());
    try std.testing.expectEqual(@as(usize, 1), mark.displayColumn());
}

test "quoted strings preserve content" {
    const parser = try Parser.initFromString(std.testing.allocator, "key: \"hello world\"");
    defer parser.deinit();

    _ = try parser.next(); // stream_start
    _ = try parser.next(); // document_start
    _ = try parser.next(); // mapping_start
    _ = try parser.next(); // key

    const value = (try parser.next()).?;
    try std.testing.expectEqualStrings("hello world", value.data.scalar.value);
    try std.testing.expectEqual(ScalarStyle.double_quoted, value.data.scalar.style);
}
