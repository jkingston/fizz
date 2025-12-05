//! Clock abstraction for deterministic simulation testing.
//!
//! Production code uses `system_clock` (real time).
//! Tests use `SimulatedClock` (controllable time).
//!
//! THREAD SAFETY: init() must be called before spawning threads.
//! The global clock state is not atomic and not thread-safe during init/deinit.
//!
//! Usage:
//!     // Production (default - no init needed)
//!     const ts = clock.currentTimeMillis();
//!
//!     // Testing
//!     var sim = clock.SimulatedClock.init(1000);
//!     clock.init(sim.clock());
//!     defer clock.deinit();
//!     sim.advance(500);  // Time is now 1500

const std = @import("std");

/// Clock interface - provides current time in milliseconds since Unix epoch.
pub const Clock = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        currentTimeMillis: *const fn (ptr: *anyopaque) i64,
    };

    pub fn currentTimeMillis(self: Clock) i64 {
        return self.vtable.currentTimeMillis(self.ptr);
    }
};

// --- Global clock instance ---

var global_clock: Clock = system_clock;

pub fn init(clk: Clock) void {
    global_clock = clk;
}

pub fn deinit() void {
    global_clock = system_clock;
}

pub fn currentTimeMillis() i64 {
    return global_clock.currentTimeMillis();
}

// --- SystemClock: real time implementation ---

fn systemClockImpl(_: *anyopaque) i64 {
    return std.time.milliTimestamp();
}

const system_clock_vtable = Clock.VTable{
    .currentTimeMillis = systemClockImpl,
};

// Zero-sized type to explicitly communicate "no state" for system clock
const SystemClockState = struct {};
const system_clock_state: SystemClockState = .{};

pub const system_clock = Clock{
    .ptr = @ptrCast(@constCast(&system_clock_state)),
    .vtable = &system_clock_vtable,
};

// --- SimulatedClock: controllable time for testing ---

pub const SimulatedClock = struct {
    current_time_ms: i64,

    pub fn init(start_time_ms: i64) SimulatedClock {
        return SimulatedClock{
            .current_time_ms = start_time_ms,
        };
    }

    /// Advances time by delta_ms. Saturates at i64 bounds on overflow.
    pub fn advance(self: *SimulatedClock, delta_ms: i64) void {
        self.current_time_ms = std.math.add(i64, self.current_time_ms, delta_ms) catch |err| switch (err) {
            error.Overflow => if (delta_ms > 0) std.math.maxInt(i64) else std.math.minInt(i64),
        };
    }

    pub fn setTime(self: *SimulatedClock, time_ms: i64) void {
        self.current_time_ms = time_ms;
    }

    pub fn currentTimeMillis(self: *SimulatedClock) i64 {
        return self.current_time_ms;
    }

    fn clockImpl(ptr: *anyopaque) i64 {
        const self: *SimulatedClock = @ptrCast(@alignCast(ptr));
        return self.current_time_ms;
    }

    const vtable = Clock.VTable{
        .currentTimeMillis = clockImpl,
    };

    pub fn clock(self: *SimulatedClock) Clock {
        return Clock{
            .ptr = @ptrCast(self),
            .vtable = &vtable,
        };
    }
};

// --- Tests ---

test "system clock returns reasonable value" {
    const ts = system_clock.currentTimeMillis();
    // Should be after 2024-01-01 (1704067200000)
    try std.testing.expect(ts > 1704067200000);
}

test "simulated clock starts at specified time" {
    var sim = SimulatedClock.init(1000);
    try std.testing.expectEqual(@as(i64, 1000), sim.currentTimeMillis());
}

test "simulated clock advance" {
    var sim = SimulatedClock.init(1000);
    sim.advance(500);
    try std.testing.expectEqual(@as(i64, 1500), sim.currentTimeMillis());
}

test "simulated clock setTime" {
    var sim = SimulatedClock.init(1000);
    sim.setTime(9999);
    try std.testing.expectEqual(@as(i64, 9999), sim.currentTimeMillis());
}

test "global clock can be overridden" {
    var sim = SimulatedClock.init(42);
    init(sim.clock());
    defer deinit();

    try std.testing.expectEqual(@as(i64, 42), currentTimeMillis());
}
