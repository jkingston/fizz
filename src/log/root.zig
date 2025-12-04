const std = @import("std");
const logz = @import("logz");

/// Initialize the global logging pool with JSON output to stderr
pub fn init(allocator: std.mem.Allocator) !void {
    try logz.setup(allocator, .{
        .level = .Info,
        .pool_size = 8,
        .buffer_size = 4096,
        .output = .stderr,
        .encoding = .json,
    });
}

/// Deinitialize the logging pool
pub fn deinit() void {
    logz.deinit();
}

/// Log an info message
pub fn info() logz.Logger {
    return logz.info();
}

/// Log a warning message
pub fn warn() logz.Logger {
    return logz.warn();
}

/// Log an error message
pub fn err() logz.Logger {
    return logz.err();
}

/// Log a debug message
pub fn debug() logz.Logger {
    return logz.debug();
}

// Re-export types for convenience
pub const Logger = logz.Logger;
pub const Level = logz.Level;
