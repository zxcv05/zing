//! BitFieldGroup - Common-to-All functionality for BitField Groups (Frames, Packets, Headers, etc).

const builtin = @import("builtin");
const cpu_endian = builtin.target.cpu.arch.endian();
const std = @import("std");
const ascii = std.ascii;
const fmt = std.fmt;
const math = std.math;
const mem = std.mem;
const meta = std.meta;

/// Config for a Bit Field Group Implementation
const ImplBitFieldGroupConfig = struct {
    kind: Kind = Kind.BASIC,
    layer: u3 = 7,
    name: []const u8 = "",
};

/// Bit Field Group Implementation.
/// Add to a Struct with `usingnamespace`.
pub fn ImplBitFieldGroup(comptime T: type, comptime impl_config: ImplBitFieldGroupConfig) type {
    return struct {
        pub const bfg_kind: Kind = impl_config.kind;
        pub const bfg_layer: u3 = impl_config.layer;
        pub const bfg_name: []const u8 = impl_config.name;

        /// Returns this BitFieldGroup as a Byte Array Slice based on its bit-width (not its byte-width, which can differ for packed structs).
        pub fn asBytes(self: *T, alloc: mem.Allocator) ![]u8 {
            return try alloc.dupe(u8, mem.asBytes(self)[0..(@bitSizeOf(T) / 8)]);
        }

        /// Returns this BitFieldGroup as a Byte Array Slice with all Fields in Network Byte Order / Big Endian
        pub fn asNetBytesBFG(self: *T, alloc: mem.Allocator) ![]u8 {
            if (cpu_endian == .little) {
                const be_bits = switch (@typeInfo(T)) {
                    .pointer => |ptr| ptrSelf: {
                        if (ptr.child == u8) return try alloc.dupe(u8, self[0..]) else break :ptrSelf try toBitsMSB(self.*);
                    },
                    .optional => try toBitsMSB(self orelse return &.{}),
                    else => try toBitsMSB(self.*),
                };
                //var be_bits = try toBitsMSB(bits.*);
                const BEBitsT = @TypeOf(be_bits);
                var be_buf: [@bitSizeOf(BEBitsT) / 8]u8 = undefined;
                mem.writeInt(BEBitsT, be_buf[0..], be_bits, .big);
                return try alloc.dupe(u8, be_buf[0..]);
            }
            return self.asBytes(alloc); // TODO - change this to take the bits in LSB order
        }

        /// Convert this BitFieldGroup to Little Endian
        pub fn toLSB(self: *T) !void {
            self.* = @bitCast(mem.bigToNative(@TypeOf(try toBitsMSB(self.*)), try toBitsMSB(self.*)));
            //inline for (meta.fields(T)) |field| {
            //    var field_self = @field(self, field.name);
            //    const field_info = @typeInfo(field.type);
            //    switch (field_info) {
            //        .Struct, .Union => {
            //            if (@hasDecl(field.type, "toLE")) try field_self.toLE()
            //            else if (@hasDecl(field.type, "toLSB")) try field_self.toLSB()
            //            else field_self.* = @bitCast(mem.bigToNative(try toBitsMSB(field_self.*)));
            //        },
            //        .pointer => |ptr| ptrSelf: {
            //            if (ptr.child != u8) toBitsMSB(self.*);
            //        },
            //        .optional => try toBitsMSB(self orelse return &.{}),
            //        inline else => field_self.* = @bitCast(mem.bigToNative(try toBitsMSB(field_self.*))),
            //    }
            //}
        }

        /// Format this BitFieldGroup for use by `std.fmt.format`.
        pub fn format(value: T, comptime _: []const u8, _: fmt.FormatOptions, writer: anytype) !void {
            var self = @constCast(&value);
            _ = try self.formatToText(writer, .{ .add_bit_ruler = true });
        }

        /// Format the bits of each bitfield within a BitField Group to an IETF-like format.
        pub fn formatToText(self: *const T, writer: anytype, fmt_config: FormatToTextConfig) !FormatToTextConfig {
            var config = fmt_config;
            if (config.add_bit_ruler) {
                try writer.print("{s}", .{FormatToTextSeparators.bit_ruler_bin});
                config.add_bit_ruler = false;
            }
            if (!config.add_bitfield_title) {
                config.add_bitfield_title = switch (T.bfg_kind) {
                    Kind.BASIC, Kind.OPTION => false,
                    else => true,
                };
            }
            if (config.add_bitfield_title) {
                const name = if (T.bfg_name.len > 0) T.bfg_name else @typeName(T);
                var ns_buf: [100]u8 = undefined;
                const name_and_size = try fmt.bufPrint(ns_buf[0..], "{s} ({d}b | {d}B)", .{ name, @bitSizeOf(T), @bitSizeOf(T) / 8 });
                const prefix = setPrefix: {
                    if (config._col_idx != 0) {
                        config._col_idx = 0;
                        break :setPrefix "\n";
                    } else break :setPrefix "";
                };
                try writer.print(FormatToTextSeparators.bitfield_header, .{ prefix, name_and_size });
            }
            config.add_bitfield_title = false;

            const fields = meta.fields(T);
            inline for (fields) |field| {
                const field_self = @field(self.*, field.name);
                if (try fmtFieldRaw(self, field_self, field.name, writer, config)) |conf| config = conf;
            }
            if (config._depth == 0) {
                const line_sep = if (config._col_idx != 0) "\n" else "";
                try writer.print("{s}{s}", .{ line_sep, FormatToTextSeparators.bitfield_cutoff_bin });
            } else config._depth -= 1;
            return config;
        }

        /// Recursive Function for Field Formatting
        fn fmtFieldRaw(self: *const T, field_raw: anytype, field_name: []const u8, writer: anytype, conf: FormatToTextConfig) !?FormatToTextConfig {
            var config = conf;
            const FieldT = @TypeOf(field_raw);
            const field_info = @typeInfo(FieldT);
            switch (field_info) {
                .@"struct" => config = try fmtStruct(@constCast(&field_raw), writer, config),
                .@"union" => {
                    switch (meta.activeTag(field_raw)) {
                        inline else => |tag| config = try fmtStruct(@constCast(&@field(field_raw, @tagName(tag))), writer, config),
                    }
                },
                .pointer => |ptr| { //TODO Properly add support for Arrays?
                    if (ptr.child != u8) {
                        if (!meta.hasFn(ptr.child, "formatToText")) return null;
                        switch (ptr.size) {
                            .One => config = try field_raw.*.formatToText(writer, config),
                            .Slice, .Many => {
                                for (field_raw) |*elm| config = try elm.*.formatToText(writer, config);
                            },
                            else => return null,
                        }
                        return config;
                    }
                    var slice_upper_buf: [100]u8 = undefined;
                    try writer.print(FormatToTextSeparators.bitfield_header, .{ "", ascii.upperString(slice_upper_buf[0..field_name.len], field_name) });
                    if (config.enable_neat_strings or config.enable_detailed_strings) {
                        const slice = if (field_raw.len > 0 and field_raw[field_raw.len - 1] == '\n') field_raw[0 .. field_raw.len - 1] else field_raw;
                        try writer.print(FormatToTextSeparators.raw_data_bin, .{"START RAW DATA"});
                        if (config.enable_neat_strings) {
                            var data_window = mem.window(u8, slice, 59, 59);
                            while (data_window.next()) |data| try writer.print(FormatToTextSeparators.raw_data_win_bin, .{data});
                        }
                        if (config.enable_detailed_strings) {
                            for (slice, 0..) |elem, idx| {
                                const elem_out = switch (elem) {
                                    '\n' => " NEWLINE",
                                    '\t' => " TAB",
                                    '\r' => " CARRIAGE RETURN",
                                    ' ' => " SPACE",
                                    '\u{0}' => " NULL",
                                    else => &[_:0]u8{elem},
                                };
                                try writer.print(FormatToTextSeparators.raw_data_elem_bin, .{ idx, elem, elem, elem_out });
                            }
                        }
                        try writer.print(FormatToTextSeparators.raw_data_bin, .{"END RAW DATA"});
                    } else try writer.print(FormatToTextSeparators.raw_data_bin, .{"DATA OMITTED FROM OUTPUT"});
                },
                .optional => {
                    return fmtFieldRaw(self, field_raw orelse return null, field_name, writer, config);
                },
                .int, .bool => {
                    const bits = try intToBitArray(field_raw);
                    for (bits) |bit| {
                        if (config._col_idx == 0) try writer.print("{d:0>4}|", .{config._row_idx});
                        const gap: u8 = gapBlk: {
                            if (config._field_idx < bits.len - 1) {
                                config._field_idx += 1;
                                break :gapBlk ' ';
                            }
                            config._field_idx = 0;
                            break :gapBlk '|';
                        };
                        try writer.print("{b}{c}", .{ bit, gap });

                        config._col_idx += 1;

                        if (config._col_idx == 32) {
                            config._row_idx += 1;
                            config._col_idx = 0;
                            try writer.writeAll("\n");
                        }
                    }
                },
                else => return null,
            }
            return config;
        }

        /// Help function for Structs
        fn fmtStruct(fmt_struct: anytype, writer: anytype, config: FormatToTextConfig) !FormatToTextConfig {
            if (!@hasDecl(@TypeOf(fmt_struct.*), "formatToText")) return config;
            var conf = config;
            conf._depth += 1;
            return try @constCast(fmt_struct).formatToText(writer, conf);
        }
    };
}

/// Convert an Integer to a BitArray of equivalent bits in MSB Format.
pub fn intToBitArray(int: anytype) ![@bitSizeOf(@TypeOf(int))]u1 {
    const IntT = @TypeOf(int);
    if (IntT == bool or IntT == u1) return [_]u1{@bitCast(int)};
    if ((@typeInfo(IntT) != .int)) {
        std.debug.print("\nType '{s}' is not an Integer.\n", .{@typeName(IntT)});
        return error.NotAnInteger;
    }
    var bit_ary: [@bitSizeOf(IntT)]u1 = undefined;
    inline for (&bit_ary, 0..) |*bit, idx|
        bit.* = @as(u1, @truncate((@bitReverse(int)) >> idx));
    return bit_ary;
}

/// Convert the provided Struct, Int, or Bool to an Int in MSB format
pub fn toBitsMSB(obj: anytype) !meta.Int(.unsigned, @bitSizeOf(@TypeOf(obj))) {
    const ObjT = @TypeOf(obj);
    return switch (@typeInfo(ObjT)) {
        .bool => @bitCast(obj),
        .int => obj,
        .@"struct" => structInt: {
            const obj_size = @bitSizeOf(ObjT);
            var bits_int: meta.Int(.unsigned, obj_size) = 0;
            var bits_width: math.Log2IntCeil(@TypeOf(bits_int)) = obj_size;
            const fields = meta.fields(ObjT);
            inline for (fields) |field| {
                const field_info = @typeInfo(field.type);
                if (field_info == .optional) continue;

                const field_self = @field(obj, field.name);
                bits_width -= @bitSizeOf(@TypeOf(field_self));
                bits_int |= @as(@TypeOf(bits_int), @intCast(try toBitsMSB(field_self))) << @as(math.Log2Int(@TypeOf(bits_int)), @intCast(bits_width));
            }
            break :structInt bits_int;
        },
        else => {
            std.debug.print("\nType '{s}' is not an Integer, Bool, or Struct.\n", .{@typeName(ObjT)});
            return error.NoConversionToMSB;
        },
    };
}

/// Config Struct for `formatToText`()
/// Note, this is also used as a Context between recursive calls.
const FormatToTextConfig = struct {
    /// Add a Bit Ruler to the formatted output.
    add_bit_ruler: bool = false,
    /// Add the Title of BitFieldGroups to the formatted output.
    add_bitfield_title: bool = false,
    /// Enable Neat `[]const u8` (strings) in the formatted output.
    enable_neat_strings: bool = true,
    /// Enable Detailed `[]const u8` (strings) in the formatted output.
    enable_detailed_strings: bool = false,

    /// Line Row Index while formatting.
    ///
    /// **INTERNAL USE**
    _row_idx: u16 = 0,
    /// Line Column Index while formatting.
    ///
    /// **INTERNAL USE**
    _col_idx: u6 = 0,
    /// BitFieldGroup Field Index while formatting.
    ///
    /// **INTERNAL USE**
    _field_idx: u16 = 0,
    /// BitFieldGroup Depth while formatting.
    ///
    /// **INTERNAL USE**
    _depth: u8 = 0,
};

/// Struct of Separators for `formatToText`()
const FormatToTextSeparators = struct {
    // Binary Separators
    pub const bit_ruler_bin: []const u8 =
        \\     0                   1                   2                   3
        \\     0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
        \\WORD+---------------+---------------+---------------+---------------+
        \\
    ;
    pub const bitfield_break_bin: []const u8 = "    +---------------+---------------+---------------+---------------+\n";
    pub const bitfield_cutoff_bin: []const u8 = "END>+---------------+---------------+---------------+---------------+\n";
    pub const bitfield_header: []const u8 = "{s}    |-+-+-+{s: ^51}+-+-+-|\n";
    pub const raw_data_bin: []const u8 = "    |{s: ^63}|\n";
    pub const raw_data_elem_bin: []const u8 = "     > {d:0>4}: 0b{b:0>8} 0x{X:0>2} {s: <38}<\n";
    pub const raw_data_win_bin: []const u8 = "     > {s: <60}<\n";
    // Decimal Separators - TODO
    // Hexadecimal Separators - TODO

    pub const bit_ruler_bin_old: []const u8 =
        \\                    B               B               B               B
        \\     0              |    1          |        2      |            3  |
        \\     0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
        \\    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
        \\
    ;
    pub const bitfield_cutoff_bin_old: []const u8 = "END>+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+\n";
};

/// Kinds of BitField Groups
pub const Kind = enum {
    BASIC,
    OPTION,
    HEADER,
    PACKET,
    FRAME,
};
