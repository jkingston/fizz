//! Data structures for Docker Compose file representation.
//!
//! These types represent a parsed compose file with all strings owned
//! by the ComposeFile allocator. Call `deinit()` to free all memory.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// A parsed Docker Compose file.
pub const ComposeFile = struct {
    allocator: Allocator,
    name: ?[]const u8 = null,
    services: std.StringArrayHashMap(Service),
    volumes: std.StringArrayHashMap(Volume),
    networks: std.StringArrayHashMap(Network),

    pub fn init(allocator: Allocator) ComposeFile {
        return .{
            .allocator = allocator,
            .name = null,
            .services = std.StringArrayHashMap(Service).init(allocator),
            .volumes = std.StringArrayHashMap(Volume).init(allocator),
            .networks = std.StringArrayHashMap(Network).init(allocator),
        };
    }

    pub fn deinit(self: *ComposeFile) void {
        if (self.name) |n| self.allocator.free(n);

        // Free service contents (service.name is the same as the key, so don't double-free)
        for (self.services.values()) |*service| {
            service.deinit(self.allocator);
        }
        self.services.deinit();

        // Free volume keys
        for (self.volumes.keys()) |key| {
            self.allocator.free(key);
        }
        self.volumes.deinit();

        // Free network keys
        for (self.networks.keys()) |key| {
            self.allocator.free(key);
        }
        self.networks.deinit();
    }
};

/// A service definition.
pub const Service = struct {
    name: []const u8,
    image: ?[]const u8 = null,
    ports: std.ArrayList(Port),
    environment: std.StringArrayHashMap([]const u8),
    depends_on: std.ArrayList(Dependency),
    healthcheck: ?Healthcheck = null,
    volumes: std.ArrayList(VolumeMount),

    // Command and entrypoint
    command: std.ArrayList([]const u8),
    entrypoint: std.ArrayList([]const u8),
    working_dir: ?[]const u8 = null,
    user: ?[]const u8 = null,

    // Container identity
    container_name: ?[]const u8 = null,
    hostname: ?[]const u8 = null,
    domainname: ?[]const u8 = null,

    // Lifecycle
    restart: RestartPolicy = .{},
    run_init: bool = false,
    stop_signal: ?[]const u8 = null,
    stop_grace_period_ns: u64 = 10 * std.time.ns_per_s,

    // Security
    read_only: bool = false,
    privileged: bool = false,
    cap_add: std.ArrayList([]const u8),
    cap_drop: std.ArrayList([]const u8),

    // Networking
    expose: std.ArrayList([]const u8),
    dns: std.ArrayList([]const u8),
    dns_search: std.ArrayList([]const u8),
    extra_hosts: std.ArrayList([]const u8),
    networks: std.ArrayList([]const u8),

    // Configuration
    labels: std.StringArrayHashMap([]const u8),
    env_file: std.ArrayList([]const u8),

    // Resource limits
    mem_limit: ?u64 = null,
    mem_reservation: ?u64 = null,
    cpus: ?f64 = null,
    pids_limit: ?u32 = null,

    // Logging
    logging: ?Logging = null,

    pub fn init(allocator: Allocator, name: []const u8) Service {
        return .{
            .name = name,
            .image = null,
            .ports = .{},
            .environment = std.StringArrayHashMap([]const u8).init(allocator),
            .depends_on = .{},
            .healthcheck = null,
            .volumes = .{},
            .command = .{},
            .entrypoint = .{},
            .working_dir = null,
            .user = null,
            .container_name = null,
            .hostname = null,
            .domainname = null,
            .restart = .{},
            .run_init = false,
            .stop_signal = null,
            .stop_grace_period_ns = 10 * std.time.ns_per_s,
            .read_only = false,
            .privileged = false,
            .cap_add = .{},
            .cap_drop = .{},
            .expose = .{},
            .dns = .{},
            .dns_search = .{},
            .extra_hosts = .{},
            .networks = .{},
            .labels = std.StringArrayHashMap([]const u8).init(allocator),
            .env_file = .{},
            .mem_limit = null,
            .mem_reservation = null,
            .cpus = null,
            .pids_limit = null,
            .logging = null,
        };
    }

    pub fn deinit(self: *Service, allocator: Allocator) void {
        allocator.free(self.name);
        if (self.image) |img| allocator.free(img);

        self.ports.deinit(allocator);

        for (self.environment.keys()) |key| {
            allocator.free(key);
        }
        for (self.environment.values()) |value| {
            allocator.free(value);
        }
        self.environment.deinit();

        for (self.depends_on.items) |dep| {
            allocator.free(dep.service);
        }
        self.depends_on.deinit(allocator);

        if (self.healthcheck) |*hc| {
            hc.deinit(allocator);
        }

        for (self.volumes.items) |vol| {
            allocator.free(vol.source);
            allocator.free(vol.target);
        }
        self.volumes.deinit(allocator);

        // Free command and entrypoint
        for (self.command.items) |item| allocator.free(item);
        self.command.deinit(allocator);
        for (self.entrypoint.items) |item| allocator.free(item);
        self.entrypoint.deinit(allocator);

        if (self.working_dir) |wd| allocator.free(wd);
        if (self.user) |u| allocator.free(u);
        if (self.container_name) |cn| allocator.free(cn);
        if (self.hostname) |h| allocator.free(h);
        if (self.domainname) |d| allocator.free(d);
        if (self.stop_signal) |ss| allocator.free(ss);

        // Free security lists
        for (self.cap_add.items) |item| allocator.free(item);
        self.cap_add.deinit(allocator);
        for (self.cap_drop.items) |item| allocator.free(item);
        self.cap_drop.deinit(allocator);

        // Free networking lists
        for (self.expose.items) |item| allocator.free(item);
        self.expose.deinit(allocator);
        for (self.dns.items) |item| allocator.free(item);
        self.dns.deinit(allocator);
        for (self.dns_search.items) |item| allocator.free(item);
        self.dns_search.deinit(allocator);
        for (self.extra_hosts.items) |item| allocator.free(item);
        self.extra_hosts.deinit(allocator);
        for (self.networks.items) |item| allocator.free(item);
        self.networks.deinit(allocator);

        // Free labels
        for (self.labels.keys()) |key| allocator.free(key);
        for (self.labels.values()) |value| allocator.free(value);
        self.labels.deinit();

        // Free env_file
        for (self.env_file.items) |item| allocator.free(item);
        self.env_file.deinit(allocator);

        // Free logging
        if (self.logging) |*log| log.deinit(allocator);
    }
};

/// Port mapping (host:container).
pub const Port = struct {
    host: u16,
    container: u16,
    protocol: Protocol = .tcp,

    pub const Protocol = enum { tcp, udp };

    /// Parse a port string like "8080:80" or "8080:80/udp".
    pub fn parse(input: []const u8) !Port {
        // Check for protocol suffix
        var protocol: Protocol = .tcp;
        var port_part = input;

        if (std.mem.lastIndexOf(u8, input, "/")) |slash_idx| {
            const proto_str = input[slash_idx + 1 ..];
            port_part = input[0..slash_idx];

            if (std.mem.eql(u8, proto_str, "tcp")) {
                protocol = .tcp;
            } else if (std.mem.eql(u8, proto_str, "udp")) {
                protocol = .udp;
            } else {
                return error.InvalidProtocol;
            }
        }

        // Parse host:container
        const colon_idx = std.mem.indexOf(u8, port_part, ":") orelse
            return error.InvalidPortFormat;

        const host_str = port_part[0..colon_idx];
        const container_str = port_part[colon_idx + 1 ..];

        const host = std.fmt.parseInt(u16, host_str, 10) catch
            return error.InvalidPortNumber;
        const container = std.fmt.parseInt(u16, container_str, 10) catch
            return error.InvalidPortNumber;

        return Port{
            .host = host,
            .container = container,
            .protocol = protocol,
        };
    }
};

/// Service dependency with condition.
pub const Dependency = struct {
    service: []const u8,
    condition: Condition = .service_started,

    pub const Condition = enum {
        service_started,
        service_healthy,
        service_completed_successfully,

        pub fn fromString(s: []const u8) ?Condition {
            if (std.mem.eql(u8, s, "service_started")) return .service_started;
            if (std.mem.eql(u8, s, "service_healthy")) return .service_healthy;
            if (std.mem.eql(u8, s, "service_completed_successfully")) return .service_completed_successfully;
            return null;
        }
    };
};

/// Healthcheck configuration.
pub const Healthcheck = struct {
    test_cmd: std.ArrayList([]const u8),
    interval_ns: u64 = 30 * std.time.ns_per_s,
    timeout_ns: u64 = 30 * std.time.ns_per_s,
    retries: u32 = 3,
    start_period_ns: u64 = 0,

    pub fn init(allocator: Allocator) Healthcheck {
        _ = allocator;
        return .{
            .test_cmd = .{},
        };
    }

    pub fn deinit(self: *Healthcheck, allocator: Allocator) void {
        for (self.test_cmd.items) |item| {
            allocator.free(item);
        }
        self.test_cmd.deinit(allocator);
    }
};

/// Volume mount specification.
pub const VolumeMount = struct {
    source: []const u8, // named volume or host path
    target: []const u8, // container path
    read_only: bool = false,

    /// Parse a volume string like "name:/path" or "name:/path:ro".
    pub fn parse(allocator: Allocator, input: []const u8) !VolumeMount {
        var read_only = false;
        var parts_str = input;

        // Check for :ro or :rw suffix
        if (std.mem.endsWith(u8, input, ":ro")) {
            read_only = true;
            parts_str = input[0 .. input.len - 3];
        } else if (std.mem.endsWith(u8, input, ":rw")) {
            read_only = false;
            parts_str = input[0 .. input.len - 3];
        }

        // Split source:target
        const colon_idx = std.mem.indexOf(u8, parts_str, ":") orelse
            return error.InvalidVolumeFormat;

        const source = try allocator.dupe(u8, parts_str[0..colon_idx]);
        errdefer allocator.free(source);

        const target = try allocator.dupe(u8, parts_str[colon_idx + 1 ..]);

        return VolumeMount{
            .source = source,
            .target = target,
            .read_only = read_only,
        };
    }
};

/// Named volume definition.
pub const Volume = struct {
    // Currently just a marker - no configuration parsed yet
};

/// Named network definition.
pub const Network = struct {
    // Currently just a marker - no configuration parsed yet
};

/// Restart policy for a service.
pub const RestartPolicy = struct {
    policy: Policy = .no,
    max_retries: ?u32 = null,

    pub const Policy = enum {
        no,
        always,
        on_failure,
        unless_stopped,
    };

    /// Parse a restart policy string like "always", "on-failure", "on-failure:5".
    pub fn parse(input: []const u8) RestartPolicy {
        if (std.mem.eql(u8, input, "no") or std.mem.eql(u8, input, "\"no\"")) {
            return .{ .policy = .no };
        } else if (std.mem.eql(u8, input, "always")) {
            return .{ .policy = .always };
        } else if (std.mem.eql(u8, input, "unless-stopped")) {
            return .{ .policy = .unless_stopped };
        } else if (std.mem.startsWith(u8, input, "on-failure")) {
            if (std.mem.indexOf(u8, input, ":")) |colon_idx| {
                const count_str = input[colon_idx + 1 ..];
                const max_retries = std.fmt.parseInt(u32, count_str, 10) catch null;
                return .{ .policy = .on_failure, .max_retries = max_retries };
            }
            return .{ .policy = .on_failure };
        }
        return .{ .policy = .no };
    }
};

/// Logging configuration for a service.
pub const Logging = struct {
    driver: ?[]const u8 = null,
    options: std.StringArrayHashMap([]const u8),

    pub fn init(allocator: Allocator) Logging {
        return .{
            .driver = null,
            .options = std.StringArrayHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Logging, allocator: Allocator) void {
        if (self.driver) |d| allocator.free(d);
        for (self.options.keys()) |key| allocator.free(key);
        for (self.options.values()) |value| allocator.free(value);
        self.options.deinit();
    }
};

/// Parse a byte size string like "512m", "1g", "100k" to bytes.
pub fn parseByteSize(input: []const u8) !u64 {
    if (input.len == 0) return error.InvalidByteSize;

    const last_char = input[input.len - 1];
    const multiplier: u64 = switch (last_char) {
        'k', 'K' => 1024,
        'm', 'M' => 1024 * 1024,
        'g', 'G' => 1024 * 1024 * 1024,
        't', 'T' => 1024 * 1024 * 1024 * 1024,
        'b', 'B' => 1,
        '0'...'9' => {
            // No suffix, assume bytes
            return std.fmt.parseInt(u64, input, 10) catch return error.InvalidByteSize;
        },
        else => return error.InvalidByteSize,
    };

    const num_str = input[0 .. input.len - 1];
    const num = std.fmt.parseInt(u64, num_str, 10) catch return error.InvalidByteSize;
    return num * multiplier;
}

/// Parse a duration string like "30s", "1m", "1h30m" to nanoseconds.
pub fn parseDuration(input: []const u8) !u64 {
    var total_ns: u64 = 0;
    var num_start: usize = 0;
    var i: usize = 0;

    while (i < input.len) {
        if (std.ascii.isDigit(input[i])) {
            i += 1;
            continue;
        }

        // Found a unit character
        const num_str = input[num_start..i];
        if (num_str.len == 0) return error.InvalidDuration;

        const num = std.fmt.parseInt(u64, num_str, 10) catch
            return error.InvalidDuration;

        const multiplier: u64 = switch (input[i]) {
            'h' => std.time.ns_per_hour,
            'm' => std.time.ns_per_min,
            's' => std.time.ns_per_s,
            else => return error.InvalidDuration,
        };

        total_ns += num * multiplier;
        i += 1;
        num_start = i;
    }

    // Handle trailing number without unit (assume seconds)
    if (num_start < input.len) {
        const num_str = input[num_start..];
        const num = std.fmt.parseInt(u64, num_str, 10) catch
            return error.InvalidDuration;
        total_ns += num * std.time.ns_per_s;
    }

    return total_ns;
}

// --- Tests ---

test "Port.parse basic" {
    const port = try Port.parse("8080:80");
    try std.testing.expectEqual(@as(u16, 8080), port.host);
    try std.testing.expectEqual(@as(u16, 80), port.container);
    try std.testing.expectEqual(Port.Protocol.tcp, port.protocol);
}

test "Port.parse with protocol" {
    const tcp_port = try Port.parse("8080:80/tcp");
    try std.testing.expectEqual(Port.Protocol.tcp, tcp_port.protocol);

    const udp_port = try Port.parse("53:53/udp");
    try std.testing.expectEqual(Port.Protocol.udp, udp_port.protocol);
}

test "Port.parse invalid" {
    try std.testing.expectError(error.InvalidPortFormat, Port.parse("8080"));
    try std.testing.expectError(error.InvalidPortNumber, Port.parse("abc:80"));
    try std.testing.expectError(error.InvalidProtocol, Port.parse("8080:80/xyz"));
}

test "VolumeMount.parse basic" {
    const vol = try VolumeMount.parse(std.testing.allocator, "db_data:/var/lib/mysql");
    defer std.testing.allocator.free(vol.source);
    defer std.testing.allocator.free(vol.target);

    try std.testing.expectEqualStrings("db_data", vol.source);
    try std.testing.expectEqualStrings("/var/lib/mysql", vol.target);
    try std.testing.expect(!vol.read_only);
}

test "VolumeMount.parse read-only" {
    const vol = try VolumeMount.parse(std.testing.allocator, "config:/etc/config:ro");
    defer std.testing.allocator.free(vol.source);
    defer std.testing.allocator.free(vol.target);

    try std.testing.expectEqualStrings("config", vol.source);
    try std.testing.expectEqualStrings("/etc/config", vol.target);
    try std.testing.expect(vol.read_only);
}

test "parseDuration seconds" {
    try std.testing.expectEqual(30 * std.time.ns_per_s, try parseDuration("30s"));
    try std.testing.expectEqual(10 * std.time.ns_per_s, try parseDuration("10s"));
}

test "parseDuration minutes" {
    try std.testing.expectEqual(5 * std.time.ns_per_min, try parseDuration("5m"));
}

test "parseDuration hours" {
    try std.testing.expectEqual(2 * std.time.ns_per_hour, try parseDuration("2h"));
}

test "parseDuration combined" {
    try std.testing.expectEqual(
        1 * std.time.ns_per_hour + 30 * std.time.ns_per_min,
        try parseDuration("1h30m"),
    );
}

test "parseDuration plain number" {
    try std.testing.expectEqual(60 * std.time.ns_per_s, try parseDuration("60"));
}

test "Dependency.Condition.fromString" {
    try std.testing.expectEqual(Dependency.Condition.service_started, Dependency.Condition.fromString("service_started").?);
    try std.testing.expectEqual(Dependency.Condition.service_healthy, Dependency.Condition.fromString("service_healthy").?);
    try std.testing.expect(Dependency.Condition.fromString("invalid") == null);
}
