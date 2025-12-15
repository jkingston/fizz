const std = @import("std");
const build_options = @import("build_options");
const cli = @import("cli/root.zig");
const log = @import("log/root.zig");

pub fn main() u8 {
    // Initialize allocator with leak detection
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    // Initialize logging
    log.init(.info);
    defer log.deinit();

    log.info().str("event", "startup").str("version", build_options.version).send();

    // Setup stdout writer
    const stdout = std.fs.File.stdout();
    var buf: [4096]u8 = undefined;
    var writer = stdout.writer(&buf);

    // Parse arguments
    const cmd = cli.Args.parse(allocator) catch {
        // Error already reported to stderr by parse()
        return 1;
    };

    // Run command and get exit code
    const exit_code = cli.run(allocator, cmd, build_options.version, &writer.interface) catch {
        return 1;
    };

    writer.interface.flush() catch {
        return 1;
    };

    return exit_code;
}

test "build options available" {
    const version = build_options.version;
    try std.testing.expect(version.len > 0);
}

test {
    // Import all test modules
    _ = @import("cli/root.zig");
    _ = @import("log/root.zig");
    _ = @import("sim/clock.zig");
    _ = @import("compose/root.zig");
}
