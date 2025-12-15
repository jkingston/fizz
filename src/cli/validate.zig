//! Validate command handler - parses and validates compose files.

const std = @import("std");
const Allocator = std.mem.Allocator;

const args = @import("args.zig");
const compose = @import("../compose/root.zig");

const max_file_size_bytes = 10 * 1024 * 1024; // 10 MB

pub const ValidateError = error{
    FileNotFound,
    FileTooBig,
    ReadError,
    OutOfMemory,
};

/// Run the validate command.
/// Returns 0 on success (file is valid), 1 on validation errors.
pub fn run(
    allocator: Allocator,
    validate_args: args.ValidateArgs,
    writer: anytype,
) ValidateError!u8 {
    const file_path = validate_args.file;

    // Read file contents
    const content = std.fs.cwd().readFileAlloc(allocator, file_path, max_file_size_bytes) catch |err| {
        switch (err) {
            error.FileNotFound => {
                writer.print("error: file not found: {s}\n", .{file_path}) catch {};
                return ValidateError.FileNotFound;
            },
            error.FileTooBig => {
                writer.print("error: file too large (max 10 MB): {s}\n", .{file_path}) catch {};
                return ValidateError.FileTooBig;
            },
            error.OutOfMemory => return ValidateError.OutOfMemory,
            else => {
                writer.print("error: cannot read file: {s}\n", .{file_path}) catch {};
                return ValidateError.ReadError;
            },
        }
    };
    defer allocator.free(content);

    // Use empty environment map - defaults will be used for interpolation.
    // Full env var support will be added in M2 when we have proper env handling.
    var env = compose.interpolation.EnvMap.init(allocator);
    defer env.deinit();

    // Parse the compose file
    var result = compose.parseString(allocator, content, &env) catch |err| {
        switch (err) {
            error.YamlError => {
                writer.print("{s}: invalid YAML syntax\n", .{file_path}) catch {};
                return 1;
            },
            error.OutOfMemory => return ValidateError.OutOfMemory,
            error.InvalidStructure => {
                // Diagnostics already contain the error details
            },
        }

        // Fall through to print diagnostics if we got InvalidStructure
        writer.print("{s}: invalid (parse error)\n", .{file_path}) catch {};
        return 1;
    };
    defer result.deinit();

    // Count errors and warnings
    var error_count: usize = 0;
    var warning_count: usize = 0;
    for (result.diagnostics.items.items) |diag| {
        switch (diag.severity) {
            .err => error_count += 1,
            .warn => warning_count += 1,
            .hint => {},
        }
    }

    // Print all diagnostics (ignore write errors - best effort output)
    result.diagnostics.writeAll(file_path, writer) catch {};

    // Print dropped diagnostics warning if any
    if (result.diagnostics.dropped_count > 0) {
        writer.print("warning: {d} diagnostic(s) were dropped due to memory pressure\n", .{result.diagnostics.dropped_count}) catch {};
    }

    // Print summary and return appropriate exit code
    if (error_count > 0) {
        writer.print("{s}: invalid ({d} error{s})\n", .{
            file_path,
            error_count,
            if (error_count != 1) "s" else "",
        }) catch {};
        return 1;
    } else if (warning_count > 0) {
        writer.print("{s}: valid ({d} warning{s})\n", .{
            file_path,
            warning_count,
            if (warning_count != 1) "s" else "",
        }) catch {};
        return 0;
    } else {
        writer.print("{s}: valid\n", .{file_path}) catch {};
        return 0;
    }
}

// --- Tests ---

test "validate existing valid file" {
    const allocator = std.testing.allocator;

    var output_buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&output_buf);

    const validate_args = args.ValidateArgs{
        .file = "examples/simple-compose.yml",
    };

    const exit_code = try run(allocator, validate_args, fbs.writer());

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "valid") != null);
    try std.testing.expectEqual(@as(u8, 0), exit_code);
}

test "validate nonexistent file" {
    const allocator = std.testing.allocator;

    var output_buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&output_buf);

    const validate_args = args.ValidateArgs{
        .file = "nonexistent-file-xyz.yml",
    };

    const result = run(allocator, validate_args, fbs.writer());
    try std.testing.expectError(ValidateError.FileNotFound, result);
}

test "validate wordpress compose file" {
    const allocator = std.testing.allocator;

    var output_buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&output_buf);

    const validate_args = args.ValidateArgs{
        .file = "examples/wordpress-compose.yml",
    };

    const exit_code = try run(allocator, validate_args, fbs.writer());

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "valid") != null);
    try std.testing.expectEqual(@as(u8, 0), exit_code);
}
