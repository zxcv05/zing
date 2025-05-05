//! Zing Library

/// Abstractions for commonly used Network Addresses.
pub const Addresses = @import("Addresses.zig");
/// BitFieldGroup - Common-to-All functionality for BitField Groups (Frames, Packets, Headers, etc).
pub const BitFieldGroup = @import("BitFieldGroup.zig");
/// Components of basic frame types. (Currently just Ethernet)
pub const Frames = @import("Frames.zig");
/// Components of the base Packet structure for IP, ICMP, TCP, and UDP packets.
pub const Packets = @import("Packets.zig");
/// Datagram Union Templates.
pub const Datagrams = @import("Datagrams.zig");

/// Functions for Crafting Datagrams.
pub const craft = @import("craft.zig");
/// Functions for Sending Datagrams.
pub const send = @import("send.zig");
/// Functions for Receiving Datagrams.
pub const recv = @import("receive.zig");
/// Functions for Interacting with a Network.
pub const interact = @import("interact.zig");
/// Functions for Connecting to Interfaces.
pub const connect = @import("connect.zig");

/// Linux Constants for System Control and Networking.
pub const constants = @import("constants.zig");

/// Simple Tools built on top of the Zing library.
pub const tools = @import("tools.zig");

/// Utility functions for the Zing Library.
pub const utils = @import("utils.zig");

test {
    @import("std").testing.refAllDeclsRecursive(@This());
}
