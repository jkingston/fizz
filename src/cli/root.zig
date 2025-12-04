const std = @import("std");
const args = @import("args.zig");

pub const Args = args.Args;

/// Available CLI commands
pub const Command = enum {
    help,
    version,
};

/// Determine which command to run based on parsed args
pub fn getCommand(parsed: Args) Command {
    if (parsed.show_version) return .version;
    return .help;
}

/// Execute the CLI with parsed arguments
pub fn run(cmd: Command, version: []const u8, writer: anytype) !void {
    switch (cmd) {
        .version => try printVersion(version, writer),
        .help => try Args.printHelp(writer),
    }
}

fn printVersion(version: []const u8, writer: anytype) !void {
    try writer.print("fizz {s}\n", .{version});
}

test "getCommand returns version when show_version is true" {
    const parsed = Args{
        .show_help = false,
        .show_version = true,
    };
    try std.testing.expectEqual(Command.version, getCommand(parsed));
}

test "getCommand returns help by default" {
    const parsed = Args{
        .show_help = false,
        .show_version = false,
    };
    try std.testing.expectEqual(Command.help, getCommand(parsed));
}

test "getCommand returns help when show_help is true" {
    const parsed = Args{
        .show_help = true,
        .show_version = false,
    };
    try std.testing.expectEqual(Command.help, getCommand(parsed));
}

// Note: run function is integration-tested via CLI.
// Unit testing with generic writers fails because clap.help requires *std.Io.Writer.

test "printVersion formats correctly" {
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try printVersion("0.1.0-dev", fbs.writer());

    const output = fbs.getWritten();
    try std.testing.expectEqualStrings("fizz 0.1.0-dev\n", output);
}
