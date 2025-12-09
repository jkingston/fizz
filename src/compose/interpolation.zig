//! Environment variable interpolation for compose files.
//!
//! Supports Docker Compose variable syntax:
//! - `${VAR}` - substitute value of VAR
//! - `${VAR:-default}` - use default if VAR is unset or empty
//! - `${VAR-default}` - use default if VAR is unset (empty is valid)
//! - `${VAR:+alternate}` - use alternate if VAR is set and non-empty
//! - `${VAR+alternate}` - use alternate if VAR is set
//! - `$$` - escape, produces literal `$`

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Environment variable provider.
pub const EnvMap = std.StringHashMap([]const u8);

/// Interpolation errors.
pub const InterpolateError = error{
    UnterminatedVariable,
    InvalidVariableSyntax,
    OutOfMemory,
};

/// Interpolate environment variables in a string.
/// Returns a new allocated string with variables expanded.
/// Caller owns the returned memory.
pub fn interpolate(
    allocator: Allocator,
    input: []const u8,
    env: *const EnvMap,
) InterpolateError![]const u8 {
    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == '$') {
            if (i + 1 < input.len) {
                if (input[i + 1] == '$') {
                    // $$ -> literal $
                    result.append(allocator, '$') catch return error.OutOfMemory;
                    i += 2;
                } else if (input[i + 1] == '{') {
                    // ${...} variable
                    const var_result = try parseVariable(input[i + 2 ..], env);
                    result.appendSlice(allocator, var_result.value) catch return error.OutOfMemory;
                    i += 2 + var_result.consumed + 1; // skip ${ + content + }
                } else {
                    // Bare $ not followed by $ or { - keep as literal
                    result.append(allocator, '$') catch return error.OutOfMemory;
                    i += 1;
                }
            } else {
                // Trailing $ at end of string
                result.append(allocator, '$') catch return error.OutOfMemory;
                i += 1;
            }
        } else {
            result.append(allocator, input[i]) catch return error.OutOfMemory;
            i += 1;
        }
    }

    return result.toOwnedSlice(allocator);
}

const ParseResult = struct {
    value: []const u8,
    consumed: usize, // bytes consumed from input (not including closing })
};

fn parseVariable(input: []const u8, env: *const EnvMap) InterpolateError!ParseResult {
    // Find closing }
    const close_idx = std.mem.indexOf(u8, input, "}") orelse
        return error.UnterminatedVariable;

    const content = input[0..close_idx];
    if (content.len == 0) return error.InvalidVariableSyntax;

    // Check for modifiers: :-, -, :+, +
    if (std.mem.indexOf(u8, content, ":-")) |mod_idx| {
        // ${VAR:-default} - use default if unset or empty
        const var_name = content[0..mod_idx];
        const default_val = content[mod_idx + 2 ..];
        const env_val = env.get(var_name);

        const value = if (env_val) |v| (if (v.len > 0) v else default_val) else default_val;
        return .{ .value = value, .consumed = close_idx };
    }

    if (std.mem.indexOf(u8, content, ":+")) |mod_idx| {
        // ${VAR:+alternate} - use alternate if set and non-empty
        const var_name = content[0..mod_idx];
        const alt_val = content[mod_idx + 2 ..];
        const env_val = env.get(var_name);

        const value = if (env_val) |v| (if (v.len > 0) alt_val else "") else "";
        return .{ .value = value, .consumed = close_idx };
    }

    // Check single-char modifiers (must come after two-char checks)
    if (std.mem.indexOf(u8, content, "-")) |mod_idx| {
        // ${VAR-default} - use default if unset (empty is valid)
        const var_name = content[0..mod_idx];
        const default_val = content[mod_idx + 1 ..];
        const env_val = env.get(var_name);

        const value = env_val orelse default_val;
        return .{ .value = value, .consumed = close_idx };
    }

    if (std.mem.indexOf(u8, content, "+")) |mod_idx| {
        // ${VAR+alternate} - use alternate if set
        const var_name = content[0..mod_idx];
        const alt_val = content[mod_idx + 1 ..];
        const env_val = env.get(var_name);

        const value = if (env_val != null) alt_val else "";
        return .{ .value = value, .consumed = close_idx };
    }

    // Simple ${VAR} - substitute or empty
    const value = env.get(content) orelse "";
    return .{ .value = value, .consumed = close_idx };
}

// --- Tests ---

test "interpolate plain string" {
    var env = EnvMap.init(std.testing.allocator);
    defer env.deinit();

    const result = try interpolate(std.testing.allocator, "hello world", &env);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("hello world", result);
}

test "interpolate simple variable" {
    var env = EnvMap.init(std.testing.allocator);
    defer env.deinit();
    try env.put("FOO", "bar");

    const result = try interpolate(std.testing.allocator, "value is ${FOO}", &env);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("value is bar", result);
}

test "interpolate unset variable" {
    var env = EnvMap.init(std.testing.allocator);
    defer env.deinit();

    const result = try interpolate(std.testing.allocator, "value is ${UNSET}", &env);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("value is ", result);
}

test "interpolate with default (unset)" {
    var env = EnvMap.init(std.testing.allocator);
    defer env.deinit();

    const result = try interpolate(std.testing.allocator, "${FOO:-default}", &env);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("default", result);
}

test "interpolate with default (empty)" {
    var env = EnvMap.init(std.testing.allocator);
    defer env.deinit();
    try env.put("FOO", "");

    const result = try interpolate(std.testing.allocator, "${FOO:-default}", &env);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("default", result);
}

test "interpolate with default (set)" {
    var env = EnvMap.init(std.testing.allocator);
    defer env.deinit();
    try env.put("FOO", "actual");

    const result = try interpolate(std.testing.allocator, "${FOO:-default}", &env);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("actual", result);
}

test "interpolate dash default (unset)" {
    var env = EnvMap.init(std.testing.allocator);
    defer env.deinit();

    const result = try interpolate(std.testing.allocator, "${FOO-default}", &env);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("default", result);
}

test "interpolate dash default (empty)" {
    var env = EnvMap.init(std.testing.allocator);
    defer env.deinit();
    try env.put("FOO", "");

    // ${FOO-default} - empty is valid, so returns empty
    const result = try interpolate(std.testing.allocator, "${FOO-default}", &env);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("", result);
}

test "interpolate alternate (set and non-empty)" {
    var env = EnvMap.init(std.testing.allocator);
    defer env.deinit();
    try env.put("FOO", "something");

    const result = try interpolate(std.testing.allocator, "${FOO:+alternate}", &env);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("alternate", result);
}

test "interpolate alternate (unset)" {
    var env = EnvMap.init(std.testing.allocator);
    defer env.deinit();

    const result = try interpolate(std.testing.allocator, "${FOO:+alternate}", &env);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("", result);
}

test "interpolate dollar escape" {
    var env = EnvMap.init(std.testing.allocator);
    defer env.deinit();

    const result = try interpolate(std.testing.allocator, "price is $$100", &env);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("price is $100", result);
}

test "interpolate multiple variables" {
    var env = EnvMap.init(std.testing.allocator);
    defer env.deinit();
    try env.put("USER", "alice");
    try env.put("HOST", "localhost");

    const result = try interpolate(std.testing.allocator, "${USER}@${HOST}", &env);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("alice@localhost", result);
}

test "interpolate unterminated variable" {
    var env = EnvMap.init(std.testing.allocator);
    defer env.deinit();

    const result = interpolate(std.testing.allocator, "${FOO", &env);
    try std.testing.expectError(error.UnterminatedVariable, result);
}

test "interpolate empty variable name" {
    var env = EnvMap.init(std.testing.allocator);
    defer env.deinit();

    const result = interpolate(std.testing.allocator, "${}", &env);
    try std.testing.expectError(error.InvalidVariableSyntax, result);
}

test "interpolate bare dollar" {
    var env = EnvMap.init(std.testing.allocator);
    defer env.deinit();

    const result = try interpolate(std.testing.allocator, "a $ b", &env);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("a $ b", result);
}

test "interpolate trailing dollar" {
    var env = EnvMap.init(std.testing.allocator);
    defer env.deinit();

    const result = try interpolate(std.testing.allocator, "end$", &env);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("end$", result);
}
