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
/// If `file_owned` is true, `file` was allocated and must be freed by the caller.
pub const ValidateArgs = struct {
    file: []const u8,
    file_owned: bool = false,
    allocator: ?std.mem.Allocator = null,

    /// Free owned resources.
    pub fn deinit(self: *ValidateArgs) void {
        if (self.file_owned) {
            if (self.allocator) |alloc| {
                alloc.free(self.file);
            }
        }
        self.* = undefined;
    }
};

/// Parse command-line arguments and return the command to execute
pub fn parse(allocator: std.mem.Allocator) ParseError!Command {
    // Get command-line args, skipping program name
    var args = std.process.argsWithAllocator(allocator) catch {
        return ParseError.InvalidArguments;
    };
    defer args.deinit();

    // Skip program name
    _ = args.next();

    // Get first argument
    const first_arg = args.next() orelse return .help;

    // Check for global flags
    if (std.mem.eql(u8, first_arg, "-h") or std.mem.eql(u8, first_arg, "--help")) {
        return .help;
    }
    if (std.mem.eql(u8, first_arg, "-v") or std.mem.eql(u8, first_arg, "--version")) {
        return .version;
    }

    // Check for subcommands
    if (std.mem.eql(u8, first_arg, "help")) {
        return .help;
    }
    if (std.mem.eql(u8, first_arg, "version")) {
        return .version;
    }
    if (std.mem.eql(u8, first_arg, "validate")) {
        return parseValidate(&args, allocator);
    }

    // Unknown command
    printErr("Unknown command: {s}\n\nRun 'fizz --help' for usage.\n", .{first_arg});
    return ParseError.UnknownCommand;
}

/// Parse the validate subcommand arguments.
/// Duplicates user-provided file paths to avoid use-after-free when ArgIterator is freed.
fn parseValidate(args: *std.process.ArgIterator, allocator: std.mem.Allocator) ParseError!Command {
    var file: []const u8 = "docker-compose.yml";
    var file_owned = false;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            const stdout = std.fs.File.stdout();
            var buf: [4096]u8 = undefined;
            var writer = stdout.writer(&buf);
            printValidateHelp(&writer.interface) catch {};
            writer.interface.flush() catch {};
            return .done;
        } else if (std.mem.eql(u8, arg, "-f") or std.mem.eql(u8, arg, "--file")) {
            const arg_file = args.next() orelse {
                printErr("error: --file requires an argument\n", .{});
                return ParseError.InvalidArguments;
            };
            // Free previous allocation if user specified file multiple times
            if (file_owned) {
                allocator.free(file);
            }
            // Duplicate the file path to avoid use-after-free when ArgIterator is freed
            file = allocator.dupe(u8, arg_file) catch return ParseError.InvalidArguments;
            file_owned = true;
        } else if (arg.len > 0 and arg[0] != '-') {
            // Positional argument - the file
            // Free previous allocation if user specified file multiple times
            if (file_owned) {
                allocator.free(file);
            }
            // Duplicate to avoid use-after-free when ArgIterator is freed
            file = allocator.dupe(u8, arg) catch return ParseError.InvalidArguments;
            file_owned = true;
        } else {
            printErr("Unknown option: {s}\n", .{arg});
            return ParseError.InvalidArguments;
        }
    }

    return .{ .validate = .{
        .file = file,
        .file_owned = file_owned,
        .allocator = allocator,
    } };
}

/// Print an error message to stderr.
/// Silently ignores write errors since there's no recovery path for stderr failures.
fn printErr(comptime fmt: []const u8, args: anytype) void {
    const stderr = std.fs.File.stderr();
    var buf: [512]u8 = undefined;
    var writer = stderr.writer(&buf);
    writer.interface.print(fmt, args) catch {};
    writer.interface.flush() catch {};
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
