const std = @import("std");
const clap = @import("clap");

pub const ParseError = error{
    InvalidArguments,
};

/// Parsed command-line arguments
pub const Args = struct {
    show_help: bool,
    show_version: bool,

    const params = clap.parseParamsComptime(
        \\-h, --help       Show this help message and exit
        \\-v, --version    Show version information and exit
        \\
    );

    /// Parse command-line arguments
    pub fn parse(allocator: std.mem.Allocator) ParseError!Args {
        var diag = clap.Diagnostic{};
        var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
            .diagnostic = &diag,
            .allocator = allocator,
        }) catch |err| {
            // Report parse error to stderr
            const stderr = std.fs.File.stderr();
            var buf: [4096]u8 = undefined;
            var writer = stderr.writer(&buf);
            diag.report(&writer.interface, err) catch {};
            writer.interface.flush() catch {};
            return ParseError.InvalidArguments;
        };
        defer res.deinit();

        return .{
            .show_help = res.args.help != 0,
            .show_version = res.args.version != 0,
        };
    }

    /// Print help message to writer
    pub fn printHelp(writer: anytype) !void {
        try writer.print(
            \\fizz - A lightweight container orchestrator
            \\
            \\Usage: fizz [OPTIONS]
            \\
            \\Options:
            \\
        , .{});
        try clap.help(writer, clap.Help, &params, .{});
    }
};

// Note: printHelp and parse are integration-tested via CLI.
// Unit testing requires a compatible writer type for clap.help.
