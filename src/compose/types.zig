//! Data structures for Docker Compose file representation.
//!
//! These types represent a parsed compose file with all strings owned
//! by the ComposeFile allocator. Call `deinit()` to free all memory.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// A parsed Docker Compose file.
pub const ComposeFile = struct {
    allocator: Allocator,
    services: std.StringArrayHashMap(Service),
    volumes: std.StringArrayHashMap(Volume),
    networks: std.StringArrayHashMap(Network),
    x_fizz: ?XFizz = null,

    pub fn init(allocator: Allocator) ComposeFile {
        return .{
            .allocator = allocator,
            .services = std.StringArrayHashMap(Service).init(allocator),
            .volumes = std.StringArrayHashMap(Volume).init(allocator),
            .networks = std.StringArrayHashMap(Network).init(allocator),
            .x_fizz = null,
        };
    }

    pub fn deinit(self: *ComposeFile) void {
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

        // Free x-fizz
        if (self.x_fizz) |*xf| {
            xf.deinit(self.allocator);
        }
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

    pub fn init(allocator: Allocator, name: []const u8) Service {
        return .{
            .name = name,
            .image = null,
            .ports = .{},
            .environment = std.StringArrayHashMap([]const u8).init(allocator),
            .depends_on = .{},
            .healthcheck = null,
            .volumes = .{},
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

/// Fizz-specific extensions (x-fizz).
pub const XFizz = struct {
    services: std.StringArrayHashMap(XFizzService),

    pub fn init(allocator: Allocator) XFizz {
        return .{
            .services = std.StringArrayHashMap(XFizzService).init(allocator),
        };
    }

    pub fn deinit(self: *XFizz, allocator: Allocator) void {
        for (self.services.values()) |*svc| {
            svc.deinit(allocator);
        }
        for (self.services.keys()) |key| {
            allocator.free(key);
        }
        self.services.deinit();
    }
};

/// Fizz-specific service configuration.
pub const XFizzService = struct {
    replicas: u32 = 1,
    placement: ?Placement = null,

    pub fn deinit(self: *XFizzService, allocator: Allocator) void {
        if (self.placement) |*p| {
            p.deinit(allocator);
        }
    }
};

/// Placement constraints for scheduling.
pub const Placement = struct {
    constraints: std.ArrayList([]const u8),

    pub fn init(allocator: Allocator) Placement {
        _ = allocator;
        return .{
            .constraints = .{},
        };
    }

    pub fn deinit(self: *Placement, allocator: Allocator) void {
        for (self.constraints.items) |c| {
            allocator.free(c);
        }
        self.constraints.deinit(allocator);
    }
};

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

    if (total_ns == 0 and input.len > 0) {
        // Input was just a number, treat as seconds
        const num = std.fmt.parseInt(u64, input, 10) catch
            return error.InvalidDuration;
        return num * std.time.ns_per_s;
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
