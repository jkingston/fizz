//! Compose file parsing and validation.
//!
//! This module provides functionality to parse Docker Compose files
//! into typed Zig structures.
//!
//! Usage:
//!     const compose = @import("compose/root.zig");
//!
//!     var env = compose.EnvMap.init(allocator);
//!     defer env.deinit();
//!
//!     var result = try compose.parseString(allocator, yaml_content, &env);
//!     defer result.deinit();
//!
//!     if (result.file) |file| {
//!         for (file.services.keys()) |name| {
//!             // Process service
//!         }
//!     }

const std = @import("std");
const Allocator = std.mem.Allocator;

// Re-export types
pub const types = @import("types.zig");
pub const ComposeFile = types.ComposeFile;
pub const Service = types.Service;
pub const Port = types.Port;
pub const Dependency = types.Dependency;
pub const Healthcheck = types.Healthcheck;
pub const VolumeMount = types.VolumeMount;
pub const Volume = types.Volume;
pub const Network = types.Network;
pub const XFizz = types.XFizz;
pub const XFizzService = types.XFizzService;
pub const Placement = types.Placement;
pub const parseDuration = types.parseDuration;

// Re-export parser
pub const parser = @import("parser.zig");
pub const ParseResult = parser.ParseResult;
pub const ParseError = parser.ParseError;

// Re-export diagnostics
pub const Diagnostic = @import("Diagnostic.zig").Diagnostic;
pub const DiagnosticList = @import("Diagnostic.zig").DiagnosticList;

// Re-export interpolation
pub const interpolation = @import("interpolation.zig");
pub const EnvMap = interpolation.EnvMap;

// Re-export yaml for advanced usage
pub const yaml = @import("yaml.zig");

/// Parse a compose file from a string.
pub fn parseString(
    allocator: Allocator,
    content: []const u8,
    env: *const EnvMap,
) ParseError!ParseResult {
    return parser.parse(allocator, content, env);
}

/// Parse a compose file from a file path.
pub fn parseFile(
    allocator: Allocator,
    path: []const u8,
    env: *const EnvMap,
) !ParseResult {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024); // 1MB max
    defer allocator.free(content);

    return parser.parse(allocator, content, env);
}

// --- Tests ---

test "parseString minimal" {
    const input =
        \\services:
        \\  web:
        \\    image: nginx
    ;

    var env = EnvMap.init(std.testing.allocator);
    defer env.deinit();

    var result = try parseString(std.testing.allocator, input, &env);
    defer result.deinit();

    try std.testing.expect(result.file != null);
    try std.testing.expectEqual(@as(usize, 1), result.file.?.services.count());
}

test "parse simple-compose.yml" {
    var env = EnvMap.init(std.testing.allocator);
    defer env.deinit();

    var result = try parseFile(std.testing.allocator, "examples/simple-compose.yml", &env);
    defer result.deinit();

    try std.testing.expect(result.file != null);
    try std.testing.expect(!result.diagnostics.hasErrors());

    const file = result.file.?;

    // Check services
    try std.testing.expectEqual(@as(usize, 1), file.services.count());
    const web = file.services.get("web").?;
    try std.testing.expectEqualStrings("nginx:alpine", web.image.?);

    // Check ports
    try std.testing.expectEqual(@as(usize, 1), web.ports.items.len);
    try std.testing.expectEqual(@as(u16, 8080), web.ports.items[0].host);
    try std.testing.expectEqual(@as(u16, 80), web.ports.items[0].container);

    // Check healthcheck
    try std.testing.expect(web.healthcheck != null);
    try std.testing.expectEqual(@as(usize, 5), web.healthcheck.?.test_cmd.items.len);
    try std.testing.expectEqualStrings("CMD", web.healthcheck.?.test_cmd.items[0]);
    try std.testing.expectEqualStrings("http://localhost/", web.healthcheck.?.test_cmd.items[4]);
}

test "parse wordpress-compose.yml" {
    var env = EnvMap.init(std.testing.allocator);
    defer env.deinit();

    var result = try parseFile(std.testing.allocator, "examples/wordpress-compose.yml", &env);
    defer result.deinit();

    try std.testing.expect(result.file != null);
    try std.testing.expect(!result.diagnostics.hasErrors());

    const file = result.file.?;

    // Check services
    try std.testing.expectEqual(@as(usize, 2), file.services.count());
    try std.testing.expect(file.services.contains("wordpress"));
    try std.testing.expect(file.services.contains("db"));

    // Check wordpress service
    const wordpress = file.services.get("wordpress").?;
    try std.testing.expectEqualStrings("wordpress:latest", wordpress.image.?);

    // Check depends_on with condition
    try std.testing.expectEqual(@as(usize, 1), wordpress.depends_on.items.len);
    try std.testing.expectEqualStrings("db", wordpress.depends_on.items[0].service);
    try std.testing.expectEqual(Dependency.Condition.service_healthy, wordpress.depends_on.items[0].condition);

    // Check environment interpolation (uses default since DB_PASSWORD not set)
    try std.testing.expectEqualStrings("wordpress", wordpress.environment.get("WORDPRESS_DB_PASSWORD").?);

    // Check db service volumes
    const db = file.services.get("db").?;
    try std.testing.expectEqual(@as(usize, 1), db.volumes.items.len);
    try std.testing.expectEqualStrings("db_data", db.volumes.items[0].source);

    // Check named volumes
    try std.testing.expectEqual(@as(usize, 1), file.volumes.count());
    try std.testing.expect(file.volumes.contains("db_data"));

    // Check x-fizz
    try std.testing.expect(file.x_fizz != null);
    const xwp = file.x_fizz.?.services.get("wordpress").?;
    try std.testing.expectEqual(@as(u32, 1), xwp.replicas);
    try std.testing.expect(xwp.placement != null);
}

test "parse wordpress-compose.yml with env override" {
    var env = EnvMap.init(std.testing.allocator);
    defer env.deinit();
    try env.put("DB_PASSWORD", "supersecret");

    var result = try parseFile(std.testing.allocator, "examples/wordpress-compose.yml", &env);
    defer result.deinit();

    try std.testing.expect(result.file != null);
    const wordpress = result.file.?.services.get("wordpress").?;
    try std.testing.expectEqualStrings("supersecret", wordpress.environment.get("WORDPRESS_DB_PASSWORD").?);
}

test {
    // Import submodules for their tests
    _ = @import("types.zig");
    _ = @import("Diagnostic.zig");
    _ = @import("interpolation.zig");
    _ = @import("parser.zig");
    _ = @import("yaml.zig");
}
