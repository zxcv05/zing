//! Datagram Union Templates

// Standard
const std = @import("std");
const mem = std.mem;
const meta = std.meta;

const eql = mem.eql;
const strToEnum = meta.stringToEnum;

// Zing
const lib = @import("lib.zig");
const BFG = lib.BitFieldGroup;
const Frames = lib.Frames;
const Packets = lib.Packets;


/// Layer 2
pub const Layer2Header = union(enum) {
    eth: Frames.EthFrame.Header,
    wifi: Frames.WifiFrame.Header,

    pub usingnamespace implCommonToAll(@This());
};

/// Layer 2 Footers
pub const Layer2Footer = union(enum) {
    eth: Frames.EthFrame.Footer,
    wifi: Frames.WifiFrame.Footer,

    pub usingnamespace implCommonToAll(@This());
};

/// Layer 3 Headers
pub const Layer3 = union(enum) {
    ip: Packets.IPPacket.Header,
    icmp: Packets.ICMPPacket,

    pub usingnamespace implCommonToAll(@This());
};

/// Layer 4 Headers
pub const Layer4 = union(enum) {
    udp: Packets.UDPPacket.Header,
    tcp: Packets.TCPPacket.Header,

    pub usingnamespace implCommonToAll(@This());
};

/// Common-to-All Functions
fn implCommonToAll(comptime T: type) type {
    return struct {
        /// Call the asBytes method of the inner BitFieldGroup.
        pub fn asBytes(self: *T) ![]u8 {
            return switch (meta.activeTag(self.*)) {
                inline else => |tag| {
                    var bfg = @constCast(&@field(self, @tagName(tag)));
                    return if (@hasDecl(@TypeOf(bfg.*), "asBytes")) @constCast(bfg.asBytes()[0..])
                           else error.NoAsBytesMethod;
                },
            };
        }

        /// Call the specific calc method of the inner BitFieldGroup.
        pub fn calc(self: *T, alloc: mem.Allocator, payload: []u8) !void {
            switch (meta.activeTag(self.*)) {
                inline else => |tag| {
                    var bfg = @constCast(&@field(self, @tagName(tag)));
                    if (@hasDecl(@TypeOf(bfg.*), "calcLengthAndChecksum")) try bfg.calcLengthAndChecksum(alloc, payload)
                    else if (@hasDecl(@TypeOf(bfg.*), "calcLengthAndHeaderChecksum")) bfg.calcLengthAndHeaderChecksum(payload)
                    else if (@hasDecl(@TypeOf(bfg.*), "calcCRC")) bfg.calcCRC(payload)
                    else return error.NoCalcMethod;
                },
            }
            return;
        }
    };
}

/// Full Layer 2 - 4 Datagram
pub const Full = struct {
    l2_header: Layer2Header = .{ .eth = .{} },
    l3_header: Layer3 = .{ .ip = .{} },
    l4_header: ?Layer4 = .{ .udp = .{} },
    payload: []const u8 = "Hello World!",
    l2_footer: Layer2Footer = .{ .eth = .{} },

    /// Initialize a Full Datagram based on the given Headers, Payload, and Footer types.
    pub fn init(layer: u3, headers: [][]const u8, payload: []const u8, footer: []const u8) !@This() {
        const l_diff = 2 - @intCast(i4, layer); // Layer Difference. Aligns input headers based on given layer.
        return .{
            .l2_header = if (layer > 2) .{ .eth = .{} } else l2Hdr: {
                const l2_hdr_type = strToEnum(meta.Tag(Layer2Header), headers[0]) orelse return error.InvalidHeader;
                switch(l2_hdr_type) { 
                    inline else => |l2_hdr_tag| break :l2Hdr @unionInit(Layer2Header, @tagName(l2_hdr_tag), .{}),
                }
            },
            .l3_header = if (layer > 3) .{ .ip = .{} } else l3Hdr: {
                const l3_hdr_type = strToEnum(meta.Tag(Layer3), headers[@intCast(u3, l_diff + 1)]) orelse return error.InvalidHeader;
                switch(l3_hdr_type) {
                    inline else => |l3_hdr_tag| break :l3Hdr @unionInit(Layer3, @tagName(l3_hdr_tag), .{}),
                }
            },
            .l4_header = l4Hdr: {
                const l4_hdr_type = strToEnum(meta.Tag(Layer4), headers[@intCast(u3, l_diff + 2)]) orelse break :l4Hdr null;
                switch (l4_hdr_type) {
                    inline else => |l4_hdr_tag| break :l4Hdr @unionInit(Layer4, @tagName(l4_hdr_tag), .{}),
                }
            },
            .payload = payload,
            .l2_footer = if (layer > 2) .{ .eth = .{} } else l2Hdr: {
                const l2_ftr_type = strToEnum(meta.Tag(Layer2Footer), footer) orelse return error.InvalidFooter;
                switch(l2_ftr_type) { 
                    inline else => |l2_ftr_tag| break :l2Hdr @unionInit(Layer2Footer, @tagName(l2_ftr_tag), .{}),
                }
            },
        };
    }

    /// Perform various calculations (Length, Checksum, etc...) for each relevant field within this Datagram
    pub fn calcFromPayload(self: *@This(), alloc: mem.Allocator) !void {
        // Data Payload
        // - Add 2 bytes to compensate for Eth Frame Header.
        var payload = try mem.concat(alloc, u8, &[_][]const u8{ self.payload, "|ETHPADDINGBITS|" });//&([_]u8{ 0 } ** 16) });
        //defer alloc.free(payload);
        // - Add any additionally required padding to ensure the Payload lines up with 32-bit words.
        const l4_len = if (self.l4_header == null) 0 else (try self.l4_header.?.asBytes()).len;
        const pad: u64 = (payload.len + l4_len + (try self.l3_header.asBytes()).len + (try self.l2_header.asBytes()).len)  % 32;
        if (pad > 0) payload = try mem.concat(alloc, u8, &[_][]const u8{ payload, ([_]u8{ '0' } ** 32)[0..pad] });
        self.payload = payload;

        // Layer 4
        if (self.l4_header != null) try self.l4_header.?.calc(alloc, payload);
        
        // Layer 3
        var l3_payload = if (self.l4_header == null) payload else try mem.concat(alloc, u8, &[_][]const u8{ try self.l4_header.?.asBytes(), payload });
        defer alloc.free(l3_payload);
        try self.l3_header.calc(alloc, l3_payload);

        // Layer 2
        var l2_payload = try mem.concat(alloc, u8, &[_][]const u8{ try self.l2_header.asBytes(), l3_payload });
        defer alloc.free(l2_payload);
        try self.l2_footer.calc(alloc, l2_payload);
    }

    /// Returns this Datagram as a Byte Array in Network Byte Order / Big Endian. Network Byte Order words are 32-bits.
    /// User must free. TODO - Determine if freeing the returned slice also frees out_buf. (Copied from BitFieldGroup.zig)
    pub fn asNetBytes(self: *@This(), alloc: mem.Allocator) ![]u8 {
        var byte_buf = if (self.l4_header != null) 
            try mem.concat(alloc, u8, &[_][]const u8{ 
                try self.l2_header.asBytes(), 
                try self.l3_header.asBytes(), 
                try self.l4_header.?.asBytes(), 
                self.payload, 
                try self.l2_footer.asBytes() 
            })
        else 
            try mem.concat(alloc, u8, &[_][]const u8{ 
                try self.l2_header.asBytes(), 
                try self.l3_header.asBytes(), 
                self.payload, 
                try self.l2_footer.asBytes() 
            });
        std.debug.print("Net Bytes Length: {d}\n", .{ byte_buf.len }); 
        var word_buf = mem.bytesAsSlice(u32, byte_buf); 
        var out_buf = std.ArrayList(u8).init(alloc);
        for (word_buf) |word| try out_buf.appendSlice(mem.asBytes(&mem.nativeToBig(u32, word)));
        return out_buf.toOwnedSlice();
    }

    pub usingnamespace BFG.implBitFieldGroup(@This(), .{ .kind = .FRAME });
};

