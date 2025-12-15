const std = @import("std");
const clap = @import("clap");

pub const ParseError = error{
    InvalidArguments,
    UnknownCommand,
};

/// Parsed command with its arguments
pub const Command = union(enum) {
    help,
    version,
    validate: ValidateArgs,
    /// Signals that help was already shown (e.g., subcommand help)
    done,
};

/// Arguments for the validate command.
/// If `needs_free` is true, `file` was allocated and must be freed by the caller.
pub const ValidateArgs = struct {
    file: []const u8,
    allocator: ?std.mem.Allocator = null,
    needs_free: bool = false,

    /// Free owned resources.
    pub fn deinit(self: *ValidateArgs) void {
        if (self.needs_free) {
            if (self.allocator) |alloc| {
                alloc.free(self.file);
            }
        }
        self.* = undefined;
    }
};

// Subcommand enum
const SubCommand = enum {
    help,
    version,
    validate,
};

// Main command parameters
const main_params = clap.parseParamsComptime(
    \\-h, --help     Show this help message and exit.
    \\-v, --version  Show version information and exit.
    \\<command>
    \\
);

const main_parsers = .{
    .command = clap.parsers.enumeration(SubCommand),
};

// Validate subcommand parameters
const validate_params = clap.parseParamsComptime(
    \\-h, --help         Show this help message.
    \\-f, --file <str>   Compose file to validate.
    \\<str>
    \\
);

/// Parse command-line arguments and return the command to execute
pub fn parse(allocator: std.mem.Allocator) ParseError!Command {
    var iter = std.process.argsWithAllocator(allocator) catch {
        return ParseError.InvalidArguments;
    };
    defer iter.deinit();

    // Skip program name
    _ = iter.next();

    var diag: clap.Diagnostic = .{};
    var res = clap.parseEx(clap.Help, &main_params, main_parsers, &iter, .{
        .diagnostic = &diag,
        .allocator = allocator,
        .terminating_positional = 0,
    }) catch {
        return ParseError.InvalidArguments;
    };
    defer res.deinit();

    // Check global flags first
    if (res.args.help != 0) return .help;
    if (res.args.version != 0) return .version;

    // Get subcommand from positionals
    const subcommand = res.positionals[0] orelse return .help;

    return switch (subcommand) {
        .help => .help,
        .version => .version,
        .validate => parseValidate(allocator, &iter),
    };
}

/// Parse the validate subcommand arguments.
fn parseValidate(allocator: std.mem.Allocator, iter: anytype) ParseError!Command {
    var diag: clap.Diagnostic = .{};
    var res = clap.parseEx(clap.Help, &validate_params, clap.parsers.default, iter, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch {
        return ParseError.InvalidArguments;
    };
    defer res.deinit();

    // Handle --help for validate subcommand
    if (res.args.help != 0) {
        const stdout = std.fs.File.stdout();
        var buf: [4096]u8 = undefined;
        var writer = stdout.writer(&buf);
        printValidateHelp(&writer.interface) catch {};
        writer.interface.flush() catch {};
        return .done;
    }

    // Determine file: --file flag takes precedence, then positional, then default
    const file_arg = res.args.file;
    const positional_file: ?[]const u8 = res.positionals[0];
    const file_source = file_arg orelse positional_file;

    if (file_source) |src| {
        // Duplicate string since clap result will be freed
        const file = allocator.dupe(u8, src) catch return ParseError.InvalidArguments;
        return .{ .validate = .{
            .file = file,
            .allocator = allocator,
            .needs_free = true,
        } };
    } else {
        // Use default - no allocation needed
        return .{ .validate = .{
            .file = "docker-compose.yml",
            .allocator = allocator,
            .needs_free = false,
        } };
    }
}

/// Print main help message
pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\fizz - A lightweight container orchestrator
        \\
        \\Usage: fizz [OPTIONS] <COMMAND>
        \\
        \\Commands:
        \\  validate    Validate a compose file
        \\  help        Show this help message
        \\  version     Show version information
        \\
        \\Options:
        \\  -h, --help       Show this help message and exit
        \\  -v, --version    Show version information and exit
        \\
        \\Run 'fizz <command> --help' for more information on a command.
        \\
    );
}

/// Print validate command help
pub fn printValidateHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Validate a Docker Compose file
        \\
        \\Usage: fizz validate [OPTIONS] [FILE]
        \\
        \\Arguments:
        \\  [FILE]  Compose file to validate (default: docker-compose.yml)
        \\
        \\Options:
        \\  -f, --file <FILE>  Compose file to validate
        \\  -h, --help         Show this help message
        \\
        \\Examples:
        \\  fizz validate
        \\  fizz validate docker-compose.yml
        \\  fizz validate -f custom-compose.yml
        \\
    );
}

// --- Tests ---

test "printHelp formats correctly" {
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try printHelp(fbs.writer());

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "fizz - A lightweight") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "validate") != null);
}

test "printValidateHelp formats correctly" {
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try printValidateHelp(fbs.writer());

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "docker-compose.yml") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "--file") != null);
}
