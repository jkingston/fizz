//! Diagnostic types for reporting parse errors and warnings with source locations.

const std = @import("std");
const Allocator = std.mem.Allocator;
const yaml = @import("yaml.zig");

/// A diagnostic message with optional source location.
pub const Diagnostic = struct {
    severity: Severity,
    message: []const u8,
    line: ?usize = null,
    column: ?usize = null,

    pub const Severity = enum {
        err,
        warn,
        hint,

        pub fn toString(self: Severity) []const u8 {
            return switch (self) {
                .err => "error",
                .warn => "warning",
                .hint => "hint",
            };
        }
    };

    /// Format the diagnostic for display.
    /// Output: "filename:line:column: severity: message" or "filename: severity: message"
    pub fn format(
        self: Diagnostic,
        filename: []const u8,
        writer: anytype,
    ) !void {
        try writer.writeAll(filename);
        if (self.line) |line| {
            try writer.print(":{d}", .{line});
            if (self.column) |col| {
                try writer.print(":{d}", .{col});
            }
        }
        try writer.print(": {s}: {s}\n", .{ self.severity.toString(), self.message });
    }
};

/// A list of diagnostics collected during parsing.
pub const DiagnosticList = struct {
    items: std.ArrayList(Diagnostic),
    allocator: Allocator,
    /// Count of diagnostics that were dropped due to allocation failure.
    dropped_count: usize = 0,

    pub fn init(allocator: Allocator) DiagnosticList {
        return .{
            .items = .{},
            .allocator = allocator,
            .dropped_count = 0,
        };
    }

    pub fn deinit(self: *DiagnosticList) void {
        for (self.items.items) |diag| {
            self.allocator.free(diag.message);
        }
        self.items.deinit(self.allocator);
    }

    /// Add an error diagnostic.
    pub fn addError(
        self: *DiagnosticList,
        mark: ?yaml.Mark,
        comptime fmt: []const u8,
        args: anytype,
    ) void {
        self.add(.err, mark, fmt, args);
    }

    /// Add a warning diagnostic.
    pub fn addWarning(
        self: *DiagnosticList,
        mark: ?yaml.Mark,
        comptime fmt: []const u8,
        args: anytype,
    ) void {
        self.add(.warn, mark, fmt, args);
    }

    /// Add a diagnostic with the given severity.
    pub fn add(
        self: *DiagnosticList,
        severity: Diagnostic.Severity,
        mark: ?yaml.Mark,
        comptime fmt: []const u8,
        args: anytype,
    ) void {
        const message = std.fmt.allocPrint(self.allocator, fmt, args) catch return;

        const diag = Diagnostic{
            .severity = severity,
            .message = message,
            .line = if (mark) |m| m.displayLine() else null,
            .column = if (mark) |m| m.displayColumn() else null,
        };

        self.items.append(self.allocator, diag) catch {
            self.allocator.free(message);
            self.dropped_count += 1;
        };
    }

    /// Check if there are any error-level diagnostics.
    pub fn hasErrors(self: DiagnosticList) bool {
        for (self.items.items) |diag| {
            if (diag.severity == .err) return true;
        }
        return false;
    }

    /// Get the count of diagnostics.
    pub fn count(self: DiagnosticList) usize {
        return self.items.items.len;
    }

    /// Write all diagnostics to a writer.
    pub fn writeAll(self: DiagnosticList, filename: []const u8, writer: anytype) !void {
        for (self.items.items) |diag| {
            try diag.format(filename, writer);
        }
    }
};

// --- Tests ---

test "Diagnostic.format with location" {
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const diag = Diagnostic{
        .severity = .err,
        .message = "unexpected key",
        .line = 15,
        .column = 7,
    };

    try diag.format("docker-compose.yml", writer);
    try std.testing.expectEqualStrings(
        "docker-compose.yml:15:7: error: unexpected key\n",
        fbs.getWritten(),
    );
}

test "Diagnostic.format without location" {
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const diag = Diagnostic{
        .severity = .warn,
        .message = "deprecated field",
        .line = null,
        .column = null,
    };

    try diag.format("compose.yml", writer);
    try std.testing.expectEqualStrings(
        "compose.yml: warning: deprecated field\n",
        fbs.getWritten(),
    );
}

test "DiagnosticList add and hasErrors" {
    var list = DiagnosticList.init(std.testing.allocator);
    defer list.deinit();

    list.addWarning(null, "this is a warning", .{});
    try std.testing.expect(!list.hasErrors());
    try std.testing.expectEqual(@as(usize, 1), list.count());

    list.addError(null, "this is an error: {s}", .{"details"});
    try std.testing.expect(list.hasErrors());
    try std.testing.expectEqual(@as(usize, 2), list.count());
}

test "DiagnosticList with yaml.Mark" {
    var list = DiagnosticList.init(std.testing.allocator);
    defer list.deinit();

    const mark = yaml.Mark{
        .line = 9, // 0-indexed, will display as 10
        .column = 4, // 0-indexed, will display as 5
        .index = 100,
    };

    list.addError(mark, "invalid value", .{});

    try std.testing.expectEqual(@as(usize, 1), list.count());
    const diag = list.items.items[0];
    try std.testing.expectEqual(@as(?usize, 10), diag.line);
    try std.testing.expectEqual(@as(?usize, 5), diag.column);
}
