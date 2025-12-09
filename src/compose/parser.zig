//! Compose file parser - converts YAML events to ComposeFile struct.

const std = @import("std");
const Allocator = std.mem.Allocator;

const yaml = @import("yaml.zig");
const types = @import("types.zig");
const Diagnostic = @import("Diagnostic.zig");
const interpolation = @import("interpolation.zig");

const ComposeFile = types.ComposeFile;
const Service = types.Service;
const Port = types.Port;
const Dependency = types.Dependency;
const Healthcheck = types.Healthcheck;
const VolumeMount = types.VolumeMount;
const Volume = types.Volume;
const Network = types.Network;
const XFizz = types.XFizz;
const XFizzService = types.XFizzService;
const Placement = types.Placement;

pub const ParseError = error{
    YamlError,
    OutOfMemory,
    InvalidStructure,
};

/// Parse a compose file from a YAML string.
pub fn parse(
    allocator: Allocator,
    input: []const u8,
    env: *const interpolation.EnvMap,
) ParseError!ParseResult {
    var yaml_parser: yaml.Parser = undefined;
    yaml_parser.init(allocator, input) catch return error.YamlError;
    defer yaml_parser.deinit();

    var parser = Parser{
        .allocator = allocator,
        .yaml = &yaml_parser,
        .env = env,
        .diagnostics = Diagnostic.DiagnosticList.init(allocator),
        .result = ComposeFile.init(allocator),
    };

    parser.parseRoot() catch |err| {
        parser.result.deinit();
        return err;
    };

    if (parser.diagnostics.hasErrors()) {
        parser.result.deinit();
        return ParseResult{
            .file = null,
            .diagnostics = parser.diagnostics,
        };
    }

    return ParseResult{
        .file = parser.result,
        .diagnostics = parser.diagnostics,
    };
}

pub const ParseResult = struct {
    file: ?ComposeFile,
    diagnostics: Diagnostic.DiagnosticList,

    pub fn deinit(self: *ParseResult) void {
        if (self.file) |*f| f.deinit();
        self.diagnostics.deinit();
    }
};

const Parser = struct {
    allocator: Allocator,
    yaml: *yaml.Parser,
    env: *const interpolation.EnvMap,
    diagnostics: Diagnostic.DiagnosticList,
    result: ComposeFile,
    current_mark: ?yaml.Mark = null,

    fn parseRoot(self: *Parser) ParseError!void {
        // Skip stream_start
        _ = self.nextEvent() catch return error.YamlError;

        // Skip document_start
        _ = self.nextEvent() catch return error.YamlError;

        // Expect root mapping
        const root_event = self.nextEvent() catch return error.YamlError;
        if (root_event == null or root_event.?.type != .mapping_start) {
            self.diagnostics.addError(self.current_mark, "expected root mapping", .{});
            return error.InvalidStructure;
        }

        // Parse root keys
        while (true) {
            const key_event = self.nextEvent() catch return error.YamlError;
            if (key_event == null) break;

            if (key_event.?.type == .mapping_end) break;

            if (key_event.?.type != .scalar) {
                self.diagnostics.addError(key_event.?.start_mark, "expected key", .{});
                try self.skipValue();
                continue;
            }

            const key = key_event.?.data.scalar.value;

            if (std.mem.eql(u8, key, "services")) {
                try self.parseServices();
            } else if (std.mem.eql(u8, key, "volumes")) {
                try self.parseVolumes();
            } else if (std.mem.eql(u8, key, "networks")) {
                try self.parseNetworks();
            } else if (std.mem.eql(u8, key, "x-fizz")) {
                try self.parseXFizz();
            } else {
                // Unknown key - warn and skip
                self.diagnostics.addWarning(key_event.?.start_mark, "unknown key: {s}", .{key});
                try self.skipValue();
            }
        }
    }

    fn parseServices(self: *Parser) ParseError!void {
        const event = self.nextEvent() catch return error.YamlError;
        if (event == null or event.?.type != .mapping_start) {
            self.diagnostics.addError(self.current_mark, "services must be a mapping", .{});
            return;
        }

        while (true) {
            const key_event = self.nextEvent() catch return error.YamlError;
            if (key_event == null) break;
            if (key_event.?.type == .mapping_end) break;

            if (key_event.?.type != .scalar) {
                self.diagnostics.addError(key_event.?.start_mark, "expected service name", .{});
                try self.skipValue();
                continue;
            }

            const name = self.allocator.dupe(u8, key_event.?.data.scalar.value) catch
                return error.OutOfMemory;
            errdefer self.allocator.free(name);

            var service = Service.init(self.allocator, name);
            errdefer service.deinit(self.allocator);

            try self.parseService(&service);

            self.result.services.put(name, service) catch
                return error.OutOfMemory;
        }
    }

    fn parseService(self: *Parser, service: *Service) ParseError!void {
        const event = self.nextEvent() catch return error.YamlError;
        if (event == null or event.?.type != .mapping_start) {
            self.diagnostics.addError(self.current_mark, "service must be a mapping", .{});
            return;
        }

        while (true) {
            const key_event = self.nextEvent() catch return error.YamlError;
            if (key_event == null) break;
            if (key_event.?.type == .mapping_end) break;

            if (key_event.?.type != .scalar) {
                self.diagnostics.addError(key_event.?.start_mark, "expected key", .{});
                try self.skipValue();
                continue;
            }

            const key = key_event.?.data.scalar.value;

            if (std.mem.eql(u8, key, "image")) {
                service.image = try self.parseInterpolatedScalar();
            } else if (std.mem.eql(u8, key, "ports")) {
                try self.parsePorts(service);
            } else if (std.mem.eql(u8, key, "environment")) {
                try self.parseEnvironment(service);
            } else if (std.mem.eql(u8, key, "depends_on")) {
                try self.parseDependsOn(service);
            } else if (std.mem.eql(u8, key, "healthcheck")) {
                try self.parseHealthcheck(service);
            } else if (std.mem.eql(u8, key, "volumes")) {
                try self.parseServiceVolumes(service);
            } else {
                // Unknown service key - warn and skip
                self.diagnostics.addWarning(key_event.?.start_mark, "unknown service key: {s}", .{key});
                try self.skipValue();
            }
        }
    }

    fn parsePorts(self: *Parser, service: *Service) ParseError!void {
        const event = self.nextEvent() catch return error.YamlError;
        if (event == null or event.?.type != .sequence_start) {
            self.diagnostics.addError(self.current_mark, "ports must be a list", .{});
            return;
        }

        while (true) {
            const item_event = self.nextEvent() catch return error.YamlError;
            if (item_event == null) break;
            if (item_event.?.type == .sequence_end) break;

            if (item_event.?.type != .scalar) {
                self.diagnostics.addError(item_event.?.start_mark, "port must be a string", .{});
                try self.skipValue();
                continue;
            }

            const port_str = item_event.?.data.scalar.value;
            const port = Port.parse(port_str) catch {
                self.diagnostics.addError(item_event.?.start_mark, "invalid port: {s}", .{port_str});
                continue;
            };

            service.ports.append(self.allocator, port) catch return error.OutOfMemory;
        }
    }

    fn parseEnvironment(self: *Parser, service: *Service) ParseError!void {
        const event = self.nextEvent() catch return error.YamlError;
        if (event == null) return;

        if (event.?.type == .mapping_start) {
            // mapping form: KEY: value
            while (true) {
                const key_event = self.nextEvent() catch return error.YamlError;
                if (key_event == null) break;
                if (key_event.?.type == .mapping_end) break;

                if (key_event.?.type != .scalar) {
                    try self.skipValue();
                    continue;
                }

                const key = self.allocator.dupe(u8, key_event.?.data.scalar.value) catch
                    return error.OutOfMemory;
                errdefer self.allocator.free(key);

                const value = try self.parseInterpolatedScalar();
                errdefer if (value) |v| self.allocator.free(v);

                service.environment.put(key, value orelse "") catch
                    return error.OutOfMemory;
            }
        } else if (event.?.type == .sequence_start) {
            // list form: - KEY=value
            while (true) {
                const item_event = self.nextEvent() catch return error.YamlError;
                if (item_event == null) break;
                if (item_event.?.type == .sequence_end) break;

                if (item_event.?.type != .scalar) {
                    try self.skipValue();
                    continue;
                }

                const item = item_event.?.data.scalar.value;
                if (std.mem.indexOf(u8, item, "=")) |eq_idx| {
                    const key = self.allocator.dupe(u8, item[0..eq_idx]) catch
                        return error.OutOfMemory;
                    errdefer self.allocator.free(key);

                    const raw_value = item[eq_idx + 1 ..];
                    const value = interpolation.interpolate(self.allocator, raw_value, self.env) catch
                        return error.OutOfMemory;

                    service.environment.put(key, value) catch
                        return error.OutOfMemory;
                } else {
                    self.diagnostics.addWarning(item_event.?.start_mark, "environment entry missing '=': {s}", .{item});
                }
            }
        } else {
            self.diagnostics.addError(event.?.start_mark, "environment must be a mapping or list", .{});
        }
    }

    fn parseDependsOn(self: *Parser, service: *Service) ParseError!void {
        const event = self.nextEvent() catch return error.YamlError;
        if (event == null) return;

        if (event.?.type == .sequence_start) {
            // Simple list form: [service1, service2]
            while (true) {
                const item_event = self.nextEvent() catch return error.YamlError;
                if (item_event == null) break;
                if (item_event.?.type == .sequence_end) break;

                if (item_event.?.type != .scalar) {
                    try self.skipValue();
                    continue;
                }

                const svc_name = self.allocator.dupe(u8, item_event.?.data.scalar.value) catch
                    return error.OutOfMemory;

                service.depends_on.append(self.allocator, .{
                    .service = svc_name,
                    .condition = .service_started,
                }) catch return error.OutOfMemory;
            }
        } else if (event.?.type == .mapping_start) {
            // Long form with conditions
            while (true) {
                const key_event = self.nextEvent() catch return error.YamlError;
                if (key_event == null) break;
                if (key_event.?.type == .mapping_end) break;

                if (key_event.?.type != .scalar) {
                    try self.skipValue();
                    continue;
                }

                const svc_name = self.allocator.dupe(u8, key_event.?.data.scalar.value) catch
                    return error.OutOfMemory;
                errdefer self.allocator.free(svc_name);

                var condition: Dependency.Condition = .service_started;

                // Parse the dependency config mapping
                const cfg_event = self.nextEvent() catch return error.YamlError;
                if (cfg_event != null and cfg_event.?.type == .mapping_start) {
                    while (true) {
                        const cfg_key = self.nextEvent() catch return error.YamlError;
                        if (cfg_key == null) break;
                        if (cfg_key.?.type == .mapping_end) break;

                        if (cfg_key.?.type == .scalar and
                            std.mem.eql(u8, cfg_key.?.data.scalar.value, "condition"))
                        {
                            const cond_event = self.nextEvent() catch return error.YamlError;
                            if (cond_event != null and cond_event.?.type == .scalar) {
                                if (Dependency.Condition.fromString(cond_event.?.data.scalar.value)) |c| {
                                    condition = c;
                                } else {
                                    self.diagnostics.addWarning(cond_event.?.start_mark, "unknown condition: {s}", .{cond_event.?.data.scalar.value});
                                }
                            }
                        } else {
                            try self.skipValue();
                        }
                    }
                }

                service.depends_on.append(self.allocator, .{
                    .service = svc_name,
                    .condition = condition,
                }) catch return error.OutOfMemory;
            }
        } else {
            self.diagnostics.addError(event.?.start_mark, "depends_on must be a list or mapping", .{});
        }
    }

    fn parseHealthcheck(self: *Parser, service: *Service) ParseError!void {
        const event = self.nextEvent() catch return error.YamlError;
        if (event == null or event.?.type != .mapping_start) {
            self.diagnostics.addError(self.current_mark, "healthcheck must be a mapping", .{});
            return;
        }

        var hc = Healthcheck.init(self.allocator);
        errdefer hc.deinit(self.allocator);

        while (true) {
            const key_event = self.nextEvent() catch return error.YamlError;
            if (key_event == null) break;
            if (key_event.?.type == .mapping_end) break;

            if (key_event.?.type != .scalar) {
                try self.skipValue();
                continue;
            }

            const key = key_event.?.data.scalar.value;

            if (std.mem.eql(u8, key, "test")) {
                try self.parseHealthcheckTest(&hc);
            } else if (std.mem.eql(u8, key, "interval")) {
                if (try self.parseScalar()) |val| {
                    hc.interval_ns = types.parseDuration(val) catch {
                        self.diagnostics.addWarning(key_event.?.start_mark, "invalid interval: {s}", .{val});
                        continue;
                    };
                }
            } else if (std.mem.eql(u8, key, "timeout")) {
                if (try self.parseScalar()) |val| {
                    hc.timeout_ns = types.parseDuration(val) catch {
                        self.diagnostics.addWarning(key_event.?.start_mark, "invalid timeout: {s}", .{val});
                        continue;
                    };
                }
            } else if (std.mem.eql(u8, key, "retries")) {
                if (try self.parseScalar()) |val| {
                    hc.retries = std.fmt.parseInt(u32, val, 10) catch {
                        self.diagnostics.addWarning(key_event.?.start_mark, "invalid retries: {s}", .{val});
                        continue;
                    };
                }
            } else if (std.mem.eql(u8, key, "start_period")) {
                if (try self.parseScalar()) |val| {
                    hc.start_period_ns = types.parseDuration(val) catch {
                        self.diagnostics.addWarning(key_event.?.start_mark, "invalid start_period: {s}", .{val});
                        continue;
                    };
                }
            } else {
                try self.skipValue();
            }
        }

        service.healthcheck = hc;
    }

    fn parseHealthcheckTest(self: *Parser, hc: *Healthcheck) ParseError!void {
        const event = self.nextEvent() catch return error.YamlError;
        if (event == null) return;

        if (event.?.type == .sequence_start) {
            // Array form: ["CMD", "arg1", "arg2"]
            while (true) {
                const item = self.nextEvent() catch return error.YamlError;
                if (item == null) break;
                if (item.?.type == .sequence_end) break;

                if (item.?.type == .scalar) {
                    const val = self.allocator.dupe(u8, item.?.data.scalar.value) catch
                        return error.OutOfMemory;
                    hc.test_cmd.append(self.allocator, val) catch return error.OutOfMemory;
                }
            }
        } else if (event.?.type == .scalar) {
            // String form: "CMD curl ..."
            const val = self.allocator.dupe(u8, event.?.data.scalar.value) catch
                return error.OutOfMemory;
            hc.test_cmd.append(self.allocator, val) catch return error.OutOfMemory;
        }
    }

    fn parseServiceVolumes(self: *Parser, service: *Service) ParseError!void {
        const event = self.nextEvent() catch return error.YamlError;
        if (event == null or event.?.type != .sequence_start) {
            self.diagnostics.addError(self.current_mark, "volumes must be a list", .{});
            return;
        }

        while (true) {
            const item = self.nextEvent() catch return error.YamlError;
            if (item == null) break;
            if (item.?.type == .sequence_end) break;

            if (item.?.type == .scalar) {
                const vol = VolumeMount.parse(self.allocator, item.?.data.scalar.value) catch {
                    self.diagnostics.addError(item.?.start_mark, "invalid volume: {s}", .{item.?.data.scalar.value});
                    continue;
                };
                service.volumes.append(self.allocator, vol) catch return error.OutOfMemory;
            } else {
                try self.skipValue();
            }
        }
    }

    fn parseVolumes(self: *Parser) ParseError!void {
        const event = self.nextEvent() catch return error.YamlError;
        if (event == null or event.?.type != .mapping_start) {
            self.diagnostics.addError(self.current_mark, "volumes must be a mapping", .{});
            return;
        }

        while (true) {
            const key_event = self.nextEvent() catch return error.YamlError;
            if (key_event == null) break;
            if (key_event.?.type == .mapping_end) break;

            if (key_event.?.type != .scalar) {
                try self.skipValue();
                continue;
            }

            const name = self.allocator.dupe(u8, key_event.?.data.scalar.value) catch
                return error.OutOfMemory;

            // Volume value can be null or a mapping - skip either way for now
            try self.skipValue();

            self.result.volumes.put(name, Volume{}) catch
                return error.OutOfMemory;
        }
    }

    fn parseNetworks(self: *Parser) ParseError!void {
        const event = self.nextEvent() catch return error.YamlError;
        if (event == null or event.?.type != .mapping_start) {
            self.diagnostics.addError(self.current_mark, "networks must be a mapping", .{});
            return;
        }

        while (true) {
            const key_event = self.nextEvent() catch return error.YamlError;
            if (key_event == null) break;
            if (key_event.?.type == .mapping_end) break;

            if (key_event.?.type != .scalar) {
                try self.skipValue();
                continue;
            }

            const name = self.allocator.dupe(u8, key_event.?.data.scalar.value) catch
                return error.OutOfMemory;

            try self.skipValue();

            self.result.networks.put(name, Network{}) catch
                return error.OutOfMemory;
        }
    }

    fn parseXFizz(self: *Parser) ParseError!void {
        const event = self.nextEvent() catch return error.YamlError;
        if (event == null or event.?.type != .mapping_start) {
            self.diagnostics.addError(self.current_mark, "x-fizz must be a mapping", .{});
            return;
        }

        var xfizz = XFizz.init(self.allocator);
        errdefer xfizz.deinit(self.allocator);

        while (true) {
            const key_event = self.nextEvent() catch return error.YamlError;
            if (key_event == null) break;
            if (key_event.?.type == .mapping_end) break;

            if (key_event.?.type != .scalar) {
                try self.skipValue();
                continue;
            }

            const svc_name = self.allocator.dupe(u8, key_event.?.data.scalar.value) catch
                return error.OutOfMemory;
            errdefer self.allocator.free(svc_name);

            var xsvc = XFizzService{};
            errdefer if (xsvc.placement) |*p| p.deinit(self.allocator);

            try self.parseXFizzService(&xsvc);

            xfizz.services.put(svc_name, xsvc) catch
                return error.OutOfMemory;
        }

        self.result.x_fizz = xfizz;
    }

    fn parseXFizzService(self: *Parser, xsvc: *XFizzService) ParseError!void {
        const event = self.nextEvent() catch return error.YamlError;
        if (event == null or event.?.type != .mapping_start) {
            return;
        }

        while (true) {
            const key_event = self.nextEvent() catch return error.YamlError;
            if (key_event == null) break;
            if (key_event.?.type == .mapping_end) break;

            if (key_event.?.type != .scalar) {
                try self.skipValue();
                continue;
            }

            const key = key_event.?.data.scalar.value;

            if (std.mem.eql(u8, key, "replicas")) {
                if (try self.parseScalar()) |val| {
                    xsvc.replicas = std.fmt.parseInt(u32, val, 10) catch 1;
                }
            } else if (std.mem.eql(u8, key, "placement")) {
                try self.parseXFizzPlacement(xsvc);
            } else {
                try self.skipValue();
            }
        }
    }

    fn parseXFizzPlacement(self: *Parser, xsvc: *XFizzService) ParseError!void {
        const event = self.nextEvent() catch return error.YamlError;
        if (event == null or event.?.type != .mapping_start) {
            return;
        }

        var placement = Placement.init(self.allocator);
        errdefer placement.deinit(self.allocator);

        while (true) {
            const key_event = self.nextEvent() catch return error.YamlError;
            if (key_event == null) break;
            if (key_event.?.type == .mapping_end) break;

            if (key_event.?.type != .scalar) {
                try self.skipValue();
                continue;
            }

            const key = key_event.?.data.scalar.value;

            if (std.mem.eql(u8, key, "constraints")) {
                const seq_event = self.nextEvent() catch return error.YamlError;
                if (seq_event != null and seq_event.?.type == .sequence_start) {
                    while (true) {
                        const item = self.nextEvent() catch return error.YamlError;
                        if (item == null) break;
                        if (item.?.type == .sequence_end) break;

                        if (item.?.type == .scalar) {
                            const constraint = self.allocator.dupe(u8, item.?.data.scalar.value) catch
                                return error.OutOfMemory;
                            placement.constraints.append(self.allocator, constraint) catch
                                return error.OutOfMemory;
                        }
                    }
                }
            } else {
                try self.skipValue();
            }
        }

        xsvc.placement = placement;
    }

    // --- Helper functions ---

    fn nextEvent(self: *Parser) !?yaml.Event {
        const event = try self.yaml.next();
        if (event) |e| {
            self.current_mark = e.start_mark;
        }
        return event;
    }

    fn parseScalar(self: *Parser) ParseError!?[]const u8 {
        const event = self.nextEvent() catch return error.YamlError;
        if (event == null) return null;
        if (event.?.type != .scalar) return null;
        return event.?.data.scalar.value;
    }

    fn parseInterpolatedScalar(self: *Parser) ParseError!?[]const u8 {
        const raw = try self.parseScalar();
        if (raw) |r| {
            return interpolation.interpolate(self.allocator, r, self.env) catch
                return error.OutOfMemory;
        }
        return null;
    }

    fn skipValue(self: *Parser) ParseError!void {
        const event = self.nextEvent() catch return error.YamlError;
        if (event == null) return;

        switch (event.?.type) {
            .scalar, .alias => return,
            .sequence_start => {
                var depth: usize = 1;
                while (depth > 0) {
                    const e = self.nextEvent() catch return error.YamlError;
                    if (e == null) return;
                    switch (e.?.type) {
                        .sequence_start, .mapping_start => depth += 1,
                        .sequence_end, .mapping_end => depth -= 1,
                        else => {},
                    }
                }
            },
            .mapping_start => {
                var depth: usize = 1;
                while (depth > 0) {
                    const e = self.nextEvent() catch return error.YamlError;
                    if (e == null) return;
                    switch (e.?.type) {
                        .sequence_start, .mapping_start => depth += 1,
                        .sequence_end, .mapping_end => depth -= 1,
                        else => {},
                    }
                }
            },
            else => {},
        }
    }
};

// --- Tests ---

test "parse minimal compose" {
    const input =
        \\services:
        \\  web:
        \\    image: nginx
    ;

    var env = interpolation.EnvMap.init(std.testing.allocator);
    defer env.deinit();

    var result = try parse(std.testing.allocator, input, &env);
    defer result.deinit();

    try std.testing.expect(result.file != null);
    try std.testing.expectEqual(@as(usize, 1), result.file.?.services.count());

    const web = result.file.?.services.get("web").?;
    try std.testing.expectEqualStrings("nginx", web.image.?);
}

test "parse service with ports" {
    const input =
        \\services:
        \\  web:
        \\    image: nginx
        \\    ports:
        \\      - "8080:80"
        \\      - "443:443"
    ;

    var env = interpolation.EnvMap.init(std.testing.allocator);
    defer env.deinit();

    var result = try parse(std.testing.allocator, input, &env);
    defer result.deinit();

    const web = result.file.?.services.get("web").?;
    try std.testing.expectEqual(@as(usize, 2), web.ports.items.len);
    try std.testing.expectEqual(@as(u16, 8080), web.ports.items[0].host);
    try std.testing.expectEqual(@as(u16, 80), web.ports.items[0].container);
}

test "parse environment interpolation" {
    const input =
        \\services:
        \\  db:
        \\    image: mysql
        \\    environment:
        \\      DB_PASSWORD: ${DB_PASSWORD:-secret}
    ;

    var env = interpolation.EnvMap.init(std.testing.allocator);
    defer env.deinit();

    var result = try parse(std.testing.allocator, input, &env);
    defer result.deinit();

    const db = result.file.?.services.get("db").?;
    try std.testing.expectEqualStrings("secret", db.environment.get("DB_PASSWORD").?);
}

test "parse depends_on with condition" {
    const input =
        \\services:
        \\  web:
        \\    image: nginx
        \\    depends_on:
        \\      db:
        \\        condition: service_healthy
        \\  db:
        \\    image: mysql
    ;

    var env = interpolation.EnvMap.init(std.testing.allocator);
    defer env.deinit();

    var result = try parse(std.testing.allocator, input, &env);
    defer result.deinit();

    const web = result.file.?.services.get("web").?;
    try std.testing.expectEqual(@as(usize, 1), web.depends_on.items.len);
    try std.testing.expectEqualStrings("db", web.depends_on.items[0].service);
    try std.testing.expectEqual(Dependency.Condition.service_healthy, web.depends_on.items[0].condition);
}

test "parse healthcheck" {
    const input =
        \\services:
        \\  web:
        \\    image: nginx
        \\    healthcheck:
        \\      test: ["CMD", "curl", "-f", "http://localhost/"]
        \\      interval: 30s
        \\      timeout: 10s
        \\      retries: 3
    ;

    var env = interpolation.EnvMap.init(std.testing.allocator);
    defer env.deinit();

    var result = try parse(std.testing.allocator, input, &env);
    defer result.deinit();

    const web = result.file.?.services.get("web").?;
    try std.testing.expect(web.healthcheck != null);
    try std.testing.expectEqual(@as(usize, 4), web.healthcheck.?.test_cmd.items.len);
    try std.testing.expectEqualStrings("CMD", web.healthcheck.?.test_cmd.items[0]);
    try std.testing.expectEqual(30 * std.time.ns_per_s, web.healthcheck.?.interval_ns);
    try std.testing.expectEqual(@as(u32, 3), web.healthcheck.?.retries);
}

test "parse volumes" {
    const input =
        \\services:
        \\  db:
        \\    image: mysql
        \\    volumes:
        \\      - db_data:/var/lib/mysql
        \\volumes:
        \\  db_data:
    ;

    var env = interpolation.EnvMap.init(std.testing.allocator);
    defer env.deinit();

    var result = try parse(std.testing.allocator, input, &env);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 1), result.file.?.volumes.count());
    try std.testing.expect(result.file.?.volumes.contains("db_data"));

    const db = result.file.?.services.get("db").?;
    try std.testing.expectEqual(@as(usize, 1), db.volumes.items.len);
    try std.testing.expectEqualStrings("db_data", db.volumes.items[0].source);
    try std.testing.expectEqualStrings("/var/lib/mysql", db.volumes.items[0].target);
}

test "parse x-fizz" {
    const input =
        \\services:
        \\  web:
        \\    image: nginx
        \\x-fizz:
        \\  web:
        \\    replicas: 3
        \\    placement:
        \\      constraints:
        \\        - node.role == worker
    ;

    var env = interpolation.EnvMap.init(std.testing.allocator);
    defer env.deinit();

    var result = try parse(std.testing.allocator, input, &env);
    defer result.deinit();

    try std.testing.expect(result.file.?.x_fizz != null);
    const xweb = result.file.?.x_fizz.?.services.get("web").?;
    try std.testing.expectEqual(@as(u32, 3), xweb.replicas);
    try std.testing.expect(xweb.placement != null);
    try std.testing.expectEqual(@as(usize, 1), xweb.placement.?.constraints.items.len);
}

test "unknown keys produce warnings" {
    const input =
        \\services:
        \\  web:
        \\    image: nginx
        \\    unknown_key: value
    ;

    var env = interpolation.EnvMap.init(std.testing.allocator);
    defer env.deinit();

    var result = try parse(std.testing.allocator, input, &env);
    defer result.deinit();

    try std.testing.expect(result.file != null);
    try std.testing.expect(!result.diagnostics.hasErrors());
    try std.testing.expect(result.diagnostics.count() > 0); // Has warnings
}
