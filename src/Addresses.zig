//! Abstractions for commonly used Network Addresses.

const std = @import("std");
const fmt = std.fmt;
const heap = std.heap;
const json = std.json;
const log = std.log;
const math = std.math;
const mem = std.mem;

const BFG = @import("BitFieldGroup.zig");
const utils = @import("utils.zig");

/// IPv4
pub const IPv4 = packed struct(u32) {
    first: u8 = 0,
    second: u8 = 0,
    third: u8 = 0,
    fourth: u8 = 0,

    // Equivalent to 0.0.0.0
    pub const Any = mem.zeroes(@This());
    // This could be any 127.0.0.0/8, but is set to the common 127.0.0.1 for convenience.
    pub const Loopback = fromStr("127.0.0.1");

    /// Create an IPv4 Address from a String (`str`).
    pub fn fromStr(str: []const u8) !@This() {
        var ip_tokens = ipTokens: {
            // Parse out port data

            var port_tokens = mem.tokenizeScalar(u8, str, ':');
            _ = port_tokens.next();
            const port = port_tokens.next();
            _ = port;

            // Parse out CIDR data
            port_tokens.reset();
            const cidr_str = port_tokens.next() orelse {
                std.debug.print("\nThe provided string '{s}' is not a valid IPv4 address.\n", .{str});
                return error.InvalidIPv4String;
            };
            var cidr_tokens = mem.tokenizeScalar(u8, cidr_str, '/');
            _ = cidr_tokens.next();
            const cidr = cidr_tokens.next();
            _ = cidr;

            // Parse out IP data
            cidr_tokens.reset();
            const ip_str = cidr_tokens.next() orelse {
                std.debug.print("\nThe provided string '{s}' is not a valid IPv4 address.\n", .{str});
                return error.InvalidIPv4String;
            };
            break :ipTokens mem.tokenizeScalar(u8, ip_str, '.');
        };

        var ip_out: @This() = .{};
        var idx: u8 = 0;
        while (ip_tokens.next()) |byte| : (idx += 1) {
            const field = switch (idx) {
                0 => &ip_out.first,
                1 => &ip_out.second,
                2 => &ip_out.third,
                3 => &ip_out.fourth,
                else => return error.InvalidIPv4String,
            };
            field.* = fmt.parseInt(u8, byte, 10) catch |err| {
                log.err("\nThere was an error while parsing the provided string '{s}':\n{}\n", .{ str, err });
                return error.InvalidIPv4String;
            };
        }

        return ip_out;
    }

    /// Create a Slice of IPv4 Addresses from a String (`ip_fmt`).
    /// This supports comma-separated IPv4 Addresses or a CIDR Notation subnet.
    /// Note, user owns memory of returned slice.
    pub fn sliceFromStr(alloc: mem.Allocator, ip_fmt: []const u8) ![]@This() {
        var ip_list = std.ArrayList(@This()).init(alloc);
        // Handle CIDR Notation
        if (mem.indexOfScalar(u8, ip_fmt, '/')) |split| {
            const base_ip: u32 = @bitCast(try fromStr(ip_fmt[0..split]));
            const cidr = try fmt.parseInt(u6, ip_fmt[(split + 1)..], 10);
            if (cidr > 31) return error.CIDRIsTooLarge;
            const subnet_size: u32 = math.pow(u32, 2, (32 - cidr));

            for (0..subnet_size) |idx| {
                const new_ip: u32 = base_ip +% mem.nativeToBig(u32, @as(u32, @intCast(idx)));
                try ip_list.append(@bitCast(new_ip));
            }
            return ip_list.toOwnedSlice();
        }

        // Handle Range
        if (mem.indexOfScalar(u8, ip_fmt, '-')) |_| {
            var oct_iter = mem.tokenizeScalar(u8, ip_fmt, '.');
            var octs: [4][]const u8 = undefined;
            for (octs[0..]) |*oct| oct.* = try getRange(alloc, u8, 0, oct_iter.next() orelse "0");
            defer for (octs[0..]) |oct| alloc.free(oct);
            for (octs[0]) |byte_1| {
                var out_ip = Any;
                out_ip.first = byte_1;
                for (octs[1]) |byte_2| {
                    out_ip.second = byte_2;
                    for (octs[2]) |byte_3| {
                        out_ip.third = byte_3;
                        for (octs[3]) |byte_4| {
                            out_ip.fourth = byte_4;
                            try ip_list.append(out_ip);
                        }
                    }
                }
            }
            return ip_list.toOwnedSlice();
        }

        // Handle Comma-Separated List
        var ip_iter = mem.splitScalar(u8, ip_fmt, ',');
        while (ip_iter.next()) |ip_str| try ip_list.append(try fromStr(ip_str));

        return ip_list.toOwnedSlice();
    }

    /// Return this IPv4 Address as a String `[]const u8`.
    /// Note, user owns memory of returned slice.
    pub fn toStr(self: *const @This(), alloc: mem.Allocator) ![]const u8 {
        var str_builder = std.ArrayList(u8).init(alloc);
        try str_builder.writer().print("{d}.{d}.{d}.{d}", .{
            self.first,
            self.second,
            self.third,
            self.fourth,
        });
        return try str_builder.toOwnedSlice();
    }

    /// Return this IPv4 Address as a ByteArray `[4]u8`.
    pub fn toByteArray(self: *const @This()) [4]u8 {
        return [_]u8{ self.first, self.second, self.third, self.fourth };
    }

    /// Custom JSON decoding into an IPv4 Address.
    pub fn jsonParse(alloc: mem.Allocator, source: anytype, options: json.ParseOptions) json.ParseError(@TypeOf(source.*))!@This() {
        return switch (try source.nextAlloc(alloc, .alloc_always)) {
            inline .string, .allocated_string => |str| fromStr(str) catch return error.UnexpectedToken,
            else => (try json.parseFromTokenSource(@This(), alloc, source, options)).value,
        };
    }

    /// Custom JSON encoding for this IPv4 Address.
    pub fn jsonStringify(self: *const @This(), writer: anytype) !void {
        var out_buf: [20]u8 = undefined;
        var fba = heap.FixedBufferAllocator.init(out_buf[0..]);
        try writer.print("\"{s}\"", .{try self.toStr(fba.allocator())});
    }

    pub usingnamespace BFG.ImplBitFieldGroup(@This(), .{});
};

// TODO IPv6

/// MAC
pub const MAC = packed struct(u48) {
    first: u8 = 0,
    second: u8 = 0,
    third: u8 = 0,
    fourth: u8 = 0,
    fifth: u8 = 0,
    sixth: u8 = 0,

    /// Create a MAC Address from a string.
    pub fn fromStr(str: []const u8) !@This() {
        var mac_tokens = macTokens: {
            const symbols = [_]u8{ ':', '-', ' ' };
            for (symbols) |symbol| {
                if (!std.mem.containsAtLeast(u8, str, 5, symbol)) continue;
                var iter = mem.tokenizeScalar(u8, str, symbol);
                break :macTokens utils.Iterator(u8).from(&iter);
            } else if (str.len == 12) {
                var iter = mem.window(u8, str, 2, 2);
                break :macTokens utils.Iterator(u8).from(&iter);
            } else {
                log.err("The provided string '{s}' is not a valid MAC Address.", .{str});
                return error.InvalidMACString;
            }
        };

        var mac_out: @This() = .{};
        var idx: u8 = 0;
        while (mac_tokens.next()) |byte| : (idx += 1) {
            const field = switch (idx) {
                0 => &mac_out.first,
                1 => &mac_out.second,
                2 => &mac_out.third,
                3 => &mac_out.fourth,
                4 => &mac_out.fifth,
                5 => &mac_out.sixth,
                else => return error.InvalidMACString,
            };
            field.* = fmt.parseInt(u8, byte, 16) catch |err| {
                std.debug.print("\nThere was an error while parsing the provided string '{s}':\n{}\n", .{ str, err });
                return error.InvalidMACString;
            };
        }
        return mac_out;
    }

    /// Return this MAC Address as a String `[]const u8`
    /// Note, user owns memory of returned slice.
    pub fn toStr(self: *const @This(), alloc: mem.Allocator) ![]const u8 {
        var str_builder = std.ArrayList(u8).init(alloc);
        try str_builder.writer().print("{X:0>2}:{X:0>2}:{X:0>2}:{X:0>2}:{X:0>2}:{X:0>2}", .{
            self.first,
            self.second,
            self.third,
            self.fourth,
            self.fifth,
            self.sixth,
        });
        return try str_builder.toOwnedSlice();
    }

    /// Return this MAC Address as a ByteArray `[6]u8`
    pub fn toByteArray(self: *@This()) [6]u8 {
        return [_]u8{ self.first, self.second, self.third, self.fourth, self.fifth, self.sixth };
    }

    /// Custom JSON decoding into an MAC Address.
    pub fn jsonParse(alloc: mem.Allocator, source: anytype, options: json.ParseOptions) json.ParseError(@TypeOf(source.*))!@This() {
        return switch (try source.nextAlloc(alloc, .alloc_always)) {
            inline .string, .allocated_string => |str| fromStr(str) catch return error.UnexpectedToken,
            else => (try json.parseFromTokenSource(@This(), alloc, source, options)).value,
        };
    }

    /// Custom JSON encoding for this MAC Address.
    pub fn jsonStringify(self: *const @This(), writer: anytype) !void {
        var out_buf: [30]u8 = undefined;
        var fba = heap.FixedBufferAllocator.init(out_buf[0..]);
        try writer.print("\"{s}\"", .{try self.toStr(fba.allocator())});
    }

    pub usingnamespace BFG.ImplBitFieldGroup(@This(), .{});
};

/// Port
pub const Port = struct {
    pub fn sliceFromStr(alloc: mem.Allocator, ports_str: []const u8) ![]u16 {
        if (mem.indexOfScalar(u8, ports_str, '-')) |_| return try getRange(alloc, u16, 10, ports_str);
        var ports_list = std.ArrayList(u16).init(alloc);
        defer ports_list.deinit();
        var ports_iter = mem.tokenizeScalar(u8, ports_str, ',');
        while (ports_iter.next()) |port| try ports_list.append(try fmt.parseInt(u16, port, 10));
        return ports_list.toOwnedSlice();
    }
};

/// Get a range of the given Number Type (NumT) with the given (`base`) from the provided Range String (`rng_str`) using the provided Allocator (`alloc`).
pub fn getRange(alloc: mem.Allocator, comptime NumT: type, base: u8, rng_str: []const u8) ![]NumT {
    var token_iter = mem.splitScalar(u8, rng_str, '-');
    const start: NumT = try fmt.parseInt(NumT, token_iter.first(), base);
    const end: NumT = if (token_iter.next()) |tok_next| try fmt.parseInt(NumT, tok_next, base) else start + 1;

    var num_list = std.ArrayList(NumT).init(alloc);
    for (start..end) |num| try num_list.append(@truncate(num));

    return num_list.toOwnedSlice();
}
