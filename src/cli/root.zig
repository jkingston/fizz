const std = @import("std");
const args_mod = @import("args.zig");
const validate = @import("validate.zig");

pub const Args = args_mod;
pub const Command = args_mod.Command;
pub const ValidateArgs = args_mod.ValidateArgs;
pub const ParseError = args_mod.ParseError;

/// Execute the CLI with parsed command.
/// Returns the exit code (0 for success, non-zero for errors).
pub fn run(
    allocator: std.mem.Allocator,
    cmd: Command,
    version: []const u8,
    writer: anytype,
) !u8 {
    return switch (cmd) {
        .version => {
            try printVersion(version, writer);
            return 0;
        },
        .help => {
            try args_mod.printHelp(writer);
            return 0;
        },
        .done => {
            // Help was already shown (e.g., subcommand help)
            return 0;
        },
        .validate => |validate_args| {
            return validate.run(allocator, validate_args, writer) catch |err| {
                switch (err) {
                    validate.ValidateError.FileNotFound => return 1,
                    validate.ValidateError.ReadError => return 1,
                    validate.ValidateError.OutOfMemory => return error.OutOfMemory,
                }
            };
        },
    };
}

fn printVersion(version: []const u8, writer: anytype) !void {
    try writer.print("fizz {s}\n", .{version});
}

// --- Tests ---

test "run version command" {
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const exit_code = try run(std.testing.allocator, .version, "0.1.0-test", fbs.writer());

    try std.testing.expectEqualStrings("fizz 0.1.0-test\n", fbs.getWritten());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
}

test "run help command" {
    var buf: [2048]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const exit_code = try run(std.testing.allocator, .help, "0.1.0", fbs.writer());

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "fizz - A lightweight") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "validate") != null);
    try std.testing.expectEqual(@as(u8, 0), exit_code);
}

test "run validate with valid file" {
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    const cmd = Command{ .validate = .{ .file = "examples/simple-compose.yml" } };
    const exit_code = try run(std.testing.allocator, cmd, "0.1.0", fbs.writer());

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "valid") != null);
    try std.testing.expectEqual(@as(u8, 0), exit_code);
}

test "run validate with nonexistent file" {
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    const cmd = Command{ .validate = .{ .file = "nonexistent.yml" } };
    const exit_code = try run(std.testing.allocator, cmd, "0.1.0", fbs.writer());

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "not found") != null);
    try std.testing.expectEqual(@as(u8, 1), exit_code);
}

test {
    _ = @import("args.zig");
    _ = @import("validate.zig");
}
