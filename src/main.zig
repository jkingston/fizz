const std = @import("std");
const build_options = @import("build_options");

pub fn main() !void {
    const stdout = std.fs.File.stdout();
    var buf: [4096]u8 = undefined;
    var writer = stdout.writer(&buf);

    try writer.interface.print("fizz {s}\n", .{build_options.version});
    try writer.interface.flush();
}

test "build options available" {
    const version = build_options.version;
    try std.testing.expect(version.len > 0);
}
