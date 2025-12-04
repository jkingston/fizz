const std = @import("std");
const build_options = @import("build_options");
const cli = @import("cli/root.zig");

pub fn main() u8 {
    // Initialize allocator with leak detection
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Setup stdout writer
    const stdout = std.fs.File.stdout();
    var buf: [4096]u8 = undefined;
    var writer = stdout.writer(&buf);

    // Parse arguments
    const args = cli.Args.parse(allocator) catch {
        // Error already reported to stderr by parse()
        return 1;
    };

    // Determine and run command
    const cmd = cli.getCommand(args);
    cli.run(cmd, build_options.version, &writer.interface) catch {
        return 1;
    };
    writer.interface.flush() catch {
        return 1;
    };

    return 0;
}

test "build options available" {
    const version = build_options.version;
    try std.testing.expect(version.len > 0);
}

test {
    // Import all test modules
    _ = @import("cli/root.zig");
    _ = @import("cli/args.zig");
}
