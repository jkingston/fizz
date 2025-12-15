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

// --- Integration tests for compose spec coverage ---

test "parse minimal.yml" {
    var env = EnvMap.init(std.testing.allocator);
    defer env.deinit();

    var result = try parseFile(std.testing.allocator, "tests/compose/minimal.yml", &env);
    defer result.deinit();

    try std.testing.expect(result.file != null);
    try std.testing.expect(!result.diagnostics.hasErrors());

    const web = result.file.?.services.get("web").?;
    try std.testing.expectEqualStrings("nginx", web.image.?);
}

test "parse command_entrypoint.yml" {
    var env = EnvMap.init(std.testing.allocator);
    defer env.deinit();

    var result = try parseFile(std.testing.allocator, "tests/compose/command_entrypoint.yml", &env);
    defer result.deinit();

    try std.testing.expect(result.file != null);
    try std.testing.expect(!result.diagnostics.hasErrors());

    const app = result.file.?.services.get("app").?;
    try std.testing.expectEqualStrings("alpine", app.image.?);

    // Check command
    try std.testing.expectEqual(@as(usize, 2), app.command.items.len);
    try std.testing.expectEqualStrings("echo", app.command.items[0]);
    try std.testing.expectEqualStrings("hello", app.command.items[1]);

    // Check entrypoint
    try std.testing.expectEqual(@as(usize, 2), app.entrypoint.items.len);
    try std.testing.expectEqualStrings("/bin/sh", app.entrypoint.items[0]);
    try std.testing.expectEqualStrings("-c", app.entrypoint.items[1]);

    // Check working_dir and user
    try std.testing.expectEqualStrings("/app", app.working_dir.?);
    try std.testing.expectEqualStrings("1000:1000", app.user.?);
}

test "parse restart_policies.yml" {
    var env = EnvMap.init(std.testing.allocator);
    defer env.deinit();

    var result = try parseFile(std.testing.allocator, "tests/compose/restart_policies.yml", &env);
    defer result.deinit();

    try std.testing.expect(result.file != null);
    try std.testing.expect(!result.diagnostics.hasErrors());

    const file = result.file.?;

    // Check different restart policies
    const always = file.services.get("always").?;
    try std.testing.expectEqual(types.RestartPolicy.Policy.always, always.restart.policy);

    const on_failure = file.services.get("on-failure").?;
    try std.testing.expectEqual(types.RestartPolicy.Policy.on_failure, on_failure.restart.policy);

    const on_failure_limited = file.services.get("on-failure-limited").?;
    try std.testing.expectEqual(types.RestartPolicy.Policy.on_failure, on_failure_limited.restart.policy);
    try std.testing.expectEqual(@as(?u32, 5), on_failure_limited.restart.max_retries);

    const unless_stopped = file.services.get("unless-stopped").?;
    try std.testing.expectEqual(types.RestartPolicy.Policy.unless_stopped, unless_stopped.restart.policy);

    const never = file.services.get("never").?;
    try std.testing.expectEqual(types.RestartPolicy.Policy.no, never.restart.policy);
}

test "parse networking.yml" {
    var env = EnvMap.init(std.testing.allocator);
    defer env.deinit();

    var result = try parseFile(std.testing.allocator, "tests/compose/networking.yml", &env);
    defer result.deinit();

    try std.testing.expect(result.file != null);
    try std.testing.expect(!result.diagnostics.hasErrors());

    const web = result.file.?.services.get("web").?;

    // Check hostname and domainname
    try std.testing.expectEqualStrings("web-server", web.hostname.?);
    try std.testing.expectEqualStrings("example.com", web.domainname.?);

    // Check expose
    try std.testing.expectEqual(@as(usize, 2), web.expose.items.len);
    try std.testing.expectEqualStrings("3000", web.expose.items[0]);
    try std.testing.expectEqualStrings("8000", web.expose.items[1]);

    // Check dns
    try std.testing.expectEqual(@as(usize, 2), web.dns.items.len);
    try std.testing.expectEqualStrings("8.8.8.8", web.dns.items[0]);
    try std.testing.expectEqualStrings("8.8.4.4", web.dns.items[1]);

    // Check extra_hosts
    try std.testing.expectEqual(@as(usize, 2), web.extra_hosts.items.len);
    try std.testing.expectEqualStrings("somehost:162.242.195.82", web.extra_hosts.items[0]);

    // Check service networks
    try std.testing.expectEqual(@as(usize, 2), web.networks.items.len);
    try std.testing.expectEqualStrings("frontend", web.networks.items[0]);
    try std.testing.expectEqualStrings("backend", web.networks.items[1]);

    // Check top-level networks
    try std.testing.expectEqual(@as(usize, 2), result.file.?.networks.count());
}

test "parse labels.yml" {
    var env = EnvMap.init(std.testing.allocator);
    defer env.deinit();

    var result = try parseFile(std.testing.allocator, "tests/compose/labels.yml", &env);
    defer result.deinit();

    try std.testing.expect(result.file != null);
    try std.testing.expect(!result.diagnostics.hasErrors());

    const web = result.file.?.services.get("web").?;

    // Check labels
    try std.testing.expectEqual(@as(usize, 2), web.labels.count());
    try std.testing.expectEqualStrings("Web server", web.labels.get("com.example.description").?);
    try std.testing.expectEqualStrings("production", web.labels.get("com.example.environment").?);

    // Check container_name
    try std.testing.expectEqualStrings("my-web-container", web.container_name.?);
}

test "parse logging.yml" {
    var env = EnvMap.init(std.testing.allocator);
    defer env.deinit();

    var result = try parseFile(std.testing.allocator, "tests/compose/logging.yml", &env);
    defer result.deinit();

    try std.testing.expect(result.file != null);
    try std.testing.expect(!result.diagnostics.hasErrors());

    const app = result.file.?.services.get("app").?;

    // Check logging config
    try std.testing.expect(app.logging != null);
    try std.testing.expectEqualStrings("json-file", app.logging.?.driver.?);
    try std.testing.expectEqual(@as(usize, 2), app.logging.?.options.count());
    try std.testing.expectEqualStrings("10m", app.logging.?.options.get("max-size").?);
    try std.testing.expectEqualStrings("3", app.logging.?.options.get("max-file").?);
}

test "parse lifecycle.yml" {
    var env = EnvMap.init(std.testing.allocator);
    defer env.deinit();

    var result = try parseFile(std.testing.allocator, "tests/compose/lifecycle.yml", &env);
    defer result.deinit();

    try std.testing.expect(result.file != null);
    try std.testing.expect(!result.diagnostics.hasErrors());

    const app = result.file.?.services.get("app").?;

    // Check lifecycle options
    try std.testing.expect(app.run_init);
    try std.testing.expectEqualStrings("SIGTERM", app.stop_signal.?);
    try std.testing.expectEqual(30 * std.time.ns_per_s, app.stop_grace_period_ns);
    try std.testing.expect(app.read_only);
}

test "parse security.yml" {
    var env = EnvMap.init(std.testing.allocator);
    defer env.deinit();

    var result = try parseFile(std.testing.allocator, "tests/compose/security.yml", &env);
    defer result.deinit();

    try std.testing.expect(result.file != null);
    try std.testing.expect(!result.diagnostics.hasErrors());

    const file = result.file.?;

    // Check privileged app
    const privileged_app = file.services.get("privileged-app").?;
    try std.testing.expect(privileged_app.privileged);

    // Check capability app
    const capability_app = file.services.get("capability-app").?;
    try std.testing.expectEqual(@as(usize, 2), capability_app.cap_add.items.len);
    try std.testing.expectEqualStrings("NET_ADMIN", capability_app.cap_add.items[0]);
    try std.testing.expectEqualStrings("SYS_PTRACE", capability_app.cap_add.items[1]);
    try std.testing.expectEqual(@as(usize, 1), capability_app.cap_drop.items.len);
    try std.testing.expectEqualStrings("MKNOD", capability_app.cap_drop.items[0]);
}

test "parse resources.yml" {
    var env = EnvMap.init(std.testing.allocator);
    defer env.deinit();

    var result = try parseFile(std.testing.allocator, "tests/compose/resources.yml", &env);
    defer result.deinit();

    try std.testing.expect(result.file != null);
    try std.testing.expect(!result.diagnostics.hasErrors());

    const limited = result.file.?.services.get("limited").?;

    // Check resource limits
    try std.testing.expectEqual(@as(?u64, 512 * 1024 * 1024), limited.mem_limit);
    try std.testing.expectEqual(@as(?u64, 256 * 1024 * 1024), limited.mem_reservation);
    try std.testing.expectEqual(@as(?f64, 0.5), limited.cpus);
    try std.testing.expectEqual(@as(?u32, 100), limited.pids_limit);
}

test "parse project_name.yml" {
    var env = EnvMap.init(std.testing.allocator);
    defer env.deinit();

    var result = try parseFile(std.testing.allocator, "tests/compose/project_name.yml", &env);
    defer result.deinit();

    try std.testing.expect(result.file != null);
    try std.testing.expect(!result.diagnostics.hasErrors());

    // Check project name
    try std.testing.expectEqualStrings("my-project", result.file.?.name.?);
}

test "parse version_header.yml" {
    var env = EnvMap.init(std.testing.allocator);
    defer env.deinit();

    var result = try parseFile(std.testing.allocator, "tests/compose/version_header.yml", &env);
    defer result.deinit();

    // Version should be silently ignored (obsolete per spec)
    try std.testing.expect(result.file != null);
    try std.testing.expect(!result.diagnostics.hasErrors());
    try std.testing.expectEqual(@as(usize, 1), result.file.?.services.count());
}

test "parse version_and_name.yml" {
    var env = EnvMap.init(std.testing.allocator);
    defer env.deinit();

    var result = try parseFile(std.testing.allocator, "tests/compose/version_and_name.yml", &env);
    defer result.deinit();

    try std.testing.expect(result.file != null);
    try std.testing.expect(!result.diagnostics.hasErrors());

    // Check name (version should be ignored)
    try std.testing.expectEqualStrings("my-app", result.file.?.name.?);

    // Check command parsing
    const web = result.file.?.services.get("web").?;
    try std.testing.expectEqual(@as(usize, 3), web.command.items.len);
    try std.testing.expectEqualStrings("nginx", web.command.items[0]);
}

test "parse full_example.yml" {
    var env = EnvMap.init(std.testing.allocator);
    defer env.deinit();

    var result = try parseFile(std.testing.allocator, "tests/compose/full_example.yml", &env);
    defer result.deinit();

    try std.testing.expect(result.file != null);
    try std.testing.expect(!result.diagnostics.hasErrors());

    const file = result.file.?;

    // Check project name
    try std.testing.expectEqualStrings("full-example", file.name.?);

    // Check we have all services
    try std.testing.expectEqual(@as(usize, 3), file.services.count());
    try std.testing.expect(file.services.contains("web"));
    try std.testing.expect(file.services.contains("api"));
    try std.testing.expect(file.services.contains("db"));

    // Spot check web service
    const web = file.services.get("web").?;
    try std.testing.expectEqualStrings("nginx:alpine", web.image.?);
    try std.testing.expectEqualStrings("web-server", web.container_name.?);
    try std.testing.expectEqualStrings("web", web.hostname.?);
    try std.testing.expectEqual(types.RestartPolicy.Policy.unless_stopped, web.restart.policy);
    try std.testing.expect(web.run_init);
    try std.testing.expect(!web.read_only);

    // Check api service
    const api = file.services.get("api").?;
    try std.testing.expectEqual(@as(usize, 1), api.entrypoint.items.len);
    try std.testing.expectEqualStrings("/app/entrypoint.sh", api.entrypoint.items[0]);
    try std.testing.expectEqual(@as(usize, 3), api.command.items.len);
    try std.testing.expectEqual(@as(?u64, 512 * 1024 * 1024), api.mem_limit);
    try std.testing.expectEqual(@as(?f64, 1.0), api.cpus);

    // Check networks
    try std.testing.expectEqual(@as(usize, 2), file.networks.count());

    // Check volumes
    try std.testing.expectEqual(@as(usize, 1), file.volumes.count());
}

test "parse environment_files.yml" {
    var env = EnvMap.init(std.testing.allocator);
    defer env.deinit();

    var result = try parseFile(std.testing.allocator, "tests/compose/environment_files.yml", &env);
    defer result.deinit();

    try std.testing.expect(result.file != null);
    try std.testing.expect(!result.diagnostics.hasErrors());

    const app = result.file.?.services.get("app").?;

    // Check env_file
    try std.testing.expectEqual(@as(usize, 2), app.env_file.items.len);
    try std.testing.expectEqualStrings(".env", app.env_file.items[0]);
    try std.testing.expectEqualStrings("./config/app.env", app.env_file.items[1]);

    // Check environment override
    try std.testing.expectEqualStrings("value", app.environment.get("OVERRIDE").?);
}

test {
    // Import submodules for their tests
    _ = @import("types.zig");
    _ = @import("Diagnostic.zig");
    _ = @import("interpolation.zig");
    _ = @import("parser.zig");
    _ = @import("yaml.zig");
}
