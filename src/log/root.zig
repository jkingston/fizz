//! Zerolog-style structured JSON logger
//!
//! Zero-allocation logging with method chaining API.
//! Writes JSON to stderr with level filtering.
//!
//! Usage:
//!     log.init(.info);
//!     log.info().str("event", "startup").str("version", "1.0").msg("starting");
//!     // Output: {"level":"info","event":"startup","version":"1.0","msg":"starting","ts":1234567890}
//!
//! Notes:
//! - String values must be valid UTF-8. Non-ASCII bytes are passed through.
//! - Buffer size is 4096 bytes. Messages exceeding this are silently truncated.
//! - init() must be called before spawning threads (global state is not atomic).
//! - Direct syscalls (stderr) are used - acceptable for logging
//!   infrastructure per ADR-0008 exception for bootstrap/infrastructure code.
//! - Timestamps use the sim/clock abstraction for deterministic testing.

const std = @import("std");
const clock = @import("../sim/clock.zig");

pub const Level = enum(u8) {
    debug = 0,
    info = 1,
    warn = 2,
    err = 3,
};

// Global minimum level
var global_level: Level = .info;

pub fn init(level: Level) void {
    global_level = level;
}

pub fn deinit() void {
    // No-op: kept for API symmetry and future resource cleanup
}

// Level constructors - return Event by value (stack allocated)
pub fn debug() Event {
    return Event.init(.debug);
}
pub fn info() Event {
    return Event.init(.info);
}
pub fn warn() Event {
    return Event.init(.warn);
}
pub fn err() Event {
    return Event.init(.err);
}

pub const Event = struct {
    buf: [4096]u8 = undefined,
    pos: usize = 0,
    enabled: bool,

    fn init(level: Level) Event {
        const enabled = @intFromEnum(level) >= @intFromEnum(global_level);
        var e = Event{ .enabled = enabled };
        if (enabled) {
            e.appendBytes("{\"level\":\"");
            e.appendBytes(@tagName(level));
            e.appendByte('"');
        }
        return e;
    }

    // --- Field methods (return self by value for chaining) ---

    pub fn str(self: Event, key: []const u8, val: []const u8) Event {
        if (!self.enabled) return self;
        var e = self;
        e.appendByte(',');
        e.appendJsonString(key);
        e.appendByte(':');
        e.appendJsonString(val);
        return e;
    }

    pub fn int(self: Event, key: []const u8, val: i64) Event {
        if (!self.enabled) return self;
        var e = self;
        e.appendByte(',');
        e.appendJsonString(key);
        e.appendByte(':');
        e.appendInt(val);
        return e;
    }

    pub fn boolean(self: Event, key: []const u8, val: bool) Event {
        if (!self.enabled) return self;
        var e = self;
        e.appendByte(',');
        e.appendJsonString(key);
        e.appendByte(':');
        e.appendBytes(if (val) "true" else "false");
        return e;
    }

    // --- Terminal methods (write to stderr) ---

    pub fn msg(self: Event, message: []const u8) void {
        if (!self.enabled) return;
        var e = self.str("msg", message);
        e.appendTimestamp();
        e.appendByte('}');
        e.appendByte('\n');
        e.flush();
    }

    pub fn send(self: Event) void {
        if (!self.enabled) return;
        var e = self;
        e.appendTimestamp();
        e.appendByte('}');
        e.appendByte('\n');
        e.flush();
    }

    // --- Internal: buffer operations ---

    fn appendByte(self: *Event, b: u8) void {
        if (self.pos < self.buf.len) {
            self.buf[self.pos] = b;
            self.pos += 1;
        }
    }

    fn appendBytes(self: *Event, bytes: []const u8) void {
        const available = self.buf.len - self.pos;
        const n = @min(bytes.len, available);
        @memcpy(self.buf[self.pos..][0..n], bytes[0..n]);
        self.pos += n;
    }

    fn appendJsonString(self: *Event, s: []const u8) void {
        self.appendByte('"');
        for (s) |c| {
            switch (c) {
                '"' => self.appendBytes("\\\""),
                '\\' => self.appendBytes("\\\\"),
                '\n' => self.appendBytes("\\n"),
                '\r' => self.appendBytes("\\r"),
                '\t' => self.appendBytes("\\t"),
                0x00...0x08, 0x0b, 0x0c, 0x0e...0x1f => {
                    // Control chars except \n (0x0a), \r (0x0d), \t (0x09)
                    self.appendBytes("\\u00");
                    self.appendHex(c >> 4);
                    self.appendHex(c & 0xf);
                },
                else => self.appendByte(c),
            }
        }
        self.appendByte('"');
    }

    fn appendHex(self: *Event, nibble: u8) void {
        const chars = "0123456789abcdef";
        self.appendByte(chars[nibble]);
    }

    fn appendInt(self: *Event, val: i64) void {
        if (val == 0) {
            self.appendByte('0');
            return;
        }

        // Handle negative numbers safely (including i64 minimum value, see std.math.minInt(i64))
        // Convert to u64 using bit manipulation to avoid overflow on negation
        var v: u64 = undefined;
        if (val < 0) {
            self.appendByte('-');
            // Safe conversion: ~val gives -(val+1), then add 1
            // This works for all negative values including the i64 minimum value
            v = ~@as(u64, @bitCast(val)) + 1;
        } else {
            v = @intCast(val);
        }

        var tmp: [20]u8 = undefined;
        var i: usize = 0;
        while (v > 0) : (v /= 10) {
            tmp[i] = @intCast('0' + v % 10);
            i += 1;
        }
        while (i > 0) {
            i -= 1;
            self.appendByte(tmp[i]);
        }
    }

    fn appendTimestamp(self: *Event) void {
        self.appendBytes(",\"ts\":");
        self.appendInt(clock.currentTimeMillis());
    }

    fn flush(self: *Event) void {
        const stderr = std.fs.File.stderr();
        stderr.writeAll(self.buf[0..self.pos]) catch {};
    }
};

// --- Tests ---

test "info event produces valid JSON" {
    const saved_level = global_level;
    defer global_level = saved_level;
    global_level = .debug;

    const e = info().str("key", "value").int("num", 42);
    const output = e.buf[0..e.pos];
    try std.testing.expect(std.mem.startsWith(u8, output, "{\"level\":\"info\""));
    try std.testing.expect(std.mem.indexOf(u8, output, "\"key\":\"value\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"num\":42") != null);
}

test "disabled level produces no output" {
    const saved_level = global_level;
    defer global_level = saved_level;
    global_level = .err;

    const e = info().str("key", "value"); // info < err, so disabled
    try std.testing.expect(e.pos == 0);
    try std.testing.expect(!e.enabled);
}

test "json escaping" {
    const saved_level = global_level;
    defer global_level = saved_level;
    global_level = .debug;

    const e = info().str("msg", "hello\"world\n");
    const output = e.buf[0..e.pos];
    try std.testing.expect(std.mem.indexOf(u8, output, "\\\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\\n") != null);
}

test "integer formatting" {
    const saved_level = global_level;
    defer global_level = saved_level;
    global_level = .debug;

    // Positive
    const e1 = info().int("val", 12345);
    try std.testing.expect(std.mem.indexOf(u8, e1.buf[0..e1.pos], "12345") != null);

    // Negative
    const e2 = info().int("val", -42);
    try std.testing.expect(std.mem.indexOf(u8, e2.buf[0..e2.pos], "-42") != null);

    // Zero
    const e3 = info().int("val", 0);
    try std.testing.expect(std.mem.indexOf(u8, e3.buf[0..e3.pos], ":0") != null);
}

test "boolean formatting" {
    const saved_level = global_level;
    defer global_level = saved_level;
    global_level = .debug;

    const e = info().boolean("flag", true).boolean("other", false);
    const output = e.buf[0..e.pos];
    try std.testing.expect(std.mem.indexOf(u8, output, "\"flag\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"other\":false") != null);
}

test "control character escaping" {
    const saved_level = global_level;
    defer global_level = saved_level;
    global_level = .debug;

    const e = info().str("data", "a\x00b\x1fc");
    const output = e.buf[0..e.pos];
    try std.testing.expect(std.mem.indexOf(u8, output, "\\u0000") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\\u001f") != null);
}

test "level ordering" {
    const saved_level = global_level;
    defer global_level = saved_level;
    global_level = .warn;

    const e1 = debug(); // debug < warn, disabled
    try std.testing.expect(!e1.enabled);

    const e2 = info(); // info < warn, disabled
    try std.testing.expect(!e2.enabled);

    const e3 = warn(); // warn == warn, enabled
    try std.testing.expect(e3.enabled);

    const e4 = err(); // err > warn, enabled
    try std.testing.expect(e4.enabled);
}

test "i64 min value" {
    const saved_level = global_level;
    defer global_level = saved_level;
    global_level = .debug;

    // Test that i64 minimum value (std.math.minInt(i64), -9223372036854775808) doesn't overflow
    const min_val = std.math.minInt(i64);
    const e = info().int("val", min_val);
    const output = e.buf[0..e.pos];
    try std.testing.expect(std.mem.indexOf(u8, output, "-9223372036854775808") != null);
}

test "i64 max value" {
    const saved_level = global_level;
    defer global_level = saved_level;
    global_level = .debug;

    const max_val = std.math.maxInt(i64);
    const e = info().int("val", max_val);
    const output = e.buf[0..e.pos];
    try std.testing.expect(std.mem.indexOf(u8, output, "9223372036854775807") != null);
}

test "buffer overflow handling" {
    const saved_level = global_level;
    defer global_level = saved_level;
    global_level = .debug;

    // Create a string longer than buffer size (4096)
    var long_string: [5000]u8 = undefined;
    @memset(&long_string, 'a');
    const e = info().str("data", &long_string);
    // Should not crash, buffer should be capped at 4096
    try std.testing.expect(e.pos <= 4096);
    try std.testing.expect(e.pos > 0); // Some data was written
}

test "unicode string handling" {
    const saved_level = global_level;
    defer global_level = saved_level;
    global_level = .debug;

    // Multi-byte UTF-8 characters (Japanese)
    const e1 = info().str("msg", "日本語");
    const output1 = e1.buf[0..e1.pos];
    try std.testing.expect(std.mem.indexOf(u8, output1, "日本語") != null);

    // Emoji (4-byte UTF-8)
    const e2 = info().str("emoji", "🎉🚀");
    const output2 = e2.buf[0..e2.pos];
    try std.testing.expect(std.mem.indexOf(u8, output2, "🎉🚀") != null);

    // Mixed ASCII and unicode
    const e3 = info().str("mixed", "hello 世界 world");
    const output3 = e3.buf[0..e3.pos];
    try std.testing.expect(std.mem.indexOf(u8, output3, "hello 世界 world") != null);
}

test "timestamp uses clock abstraction" {
    const saved_level = global_level;
    defer global_level = saved_level;

    var sim = clock.SimulatedClock.init(1234567890);
    clock.init(sim.clock());
    defer clock.deinit();

    global_level = .debug;
    var e = info().str("key", "value");
    e.appendTimestamp();

    const output = e.buf[0..e.pos];
    try std.testing.expect(std.mem.indexOf(u8, output, "\"ts\":1234567890") != null);
}

test "empty string field" {
    const saved_level = global_level;
    defer global_level = saved_level;
    global_level = .debug;

    const e = info().str("empty", "");
    const output = e.buf[0..e.pos];
    try std.testing.expect(std.mem.indexOf(u8, output, "\"empty\":\"\"") != null);
}
