//! P7 Phase B1-prep: PTY byte stream persistence via mmap'd ring buffer.
//!
//! One PersistRing per pane. Backed by a fixed-size file at
//! `~/.void/sessions/<wid>/tabs/<tid>/panes/<pid>/bytes.ring` mapped
//! MAP_SHARED. Writes are `memcpy` into the mapped region — the kernel
//! flushes dirty pages asynchronously, so write cost is ~0 µs.
//!
//! `msync(MS_ASYNC)` is called every 1 second from a background timer
//! to bound macOS-crash data loss to ≤ 1 second.
//!
//! ## Status
//!
//! Phase B1-prep: skeleton + interface only. Termio.zig integration
//! (call `append` from the PTY read path) is Phase B1-impl, separate
//! commit. Selftest pending Phase B1-impl since the interface here
//! has no callers yet.
//!
//! ## File layout
//!
//! ```
//! +------+--------+--------+----------+----------------+
//! | hdr  | wrt    | gen    | reserved | payload (CAP)  |
//! | u32  | u64    | u64    | 12 bytes | ring of bytes  |
//! +------+--------+--------+----------+----------------+
//!   0    4        12       20         32 ... 32+CAP
//! ```
//!
//! - `hdr`        magic 0x52455650 ("PVER") to detect ring vs garbage
//! - `wrt`        atomic monotonic write offset (bytes since ring open)
//! - `gen`        ring generation counter (incremented on every wraparound)
//! - `payload`    fixed-size byte ring; physical pos = wrt mod CAP
//!
//! Replay reads from `(wrt mod CAP)` going backward `min(wrt, CAP)` bytes
//! to reconstruct the most recent CAP bytes of PTY output.
//!
//! ## Origin
//!
//! 2026-04-29 conversation — user asked for void abnormal-termination
//! + macOS-crash recovery. Hybrid policy: structural changes flush
//! immediately (cheap, rare), screen state recomputable from byte
//! stream (5s timer OK), byte stream itself written immediately
//! (loss = unrecoverable).
//!
//! See `docs/design/sighup-resistant-session.md` Phase B1 section.

const PersistRing = @This();

const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;
const log = std.log.scoped(.persist_ring);

/// Magic in header: "PVER" little-endian.
const MAGIC: u32 = 0x52455650;

/// Default ring payload capacity (4 MB ≈ 100k rows of 80x100).
pub const DEFAULT_CAP: usize = 4 * 1024 * 1024;

/// Header occupies the first 32 bytes of the file. Payload follows.
const HEADER_SIZE: usize = 32;

const Header = extern struct {
    magic: u32,
    _pad0: u32 = 0,
    write_offset: u64 align(8),
    generation: u64 align(8),
    _reserved: [8]u8 = .{0} ** 8,
};

comptime {
    std.debug.assert(@sizeOf(Header) == HEADER_SIZE);
}

/// File descriptor of the backing ring file.
fd: posix.fd_t,

/// Mapped region. `[0..HEADER_SIZE]` is the header, rest is payload.
mapped: []align(std.heap.page_size_min) u8,

/// Payload capacity (does not include header).
cap: usize,

/// Open or create a ring at `path`. Caller owns the file path string.
/// `cap` is the payload capacity (default `DEFAULT_CAP`).
pub fn open(path: [:0]const u8, cap: usize) !PersistRing {
    const fd = try posix.open(path, .{
        .ACCMODE = .RDWR,
        .CREAT = true,
    }, 0o600);
    errdefer posix.close(fd);

    const total = HEADER_SIZE + cap;
    const stat = try posix.fstat(fd);
    if (stat.size != total) {
        try posix.ftruncate(fd, total);
    }

    const mapped = try posix.mmap(
        null,
        total,
        posix.PROT.READ | posix.PROT.WRITE,
        .{ .TYPE = .SHARED },
        fd,
        0,
    );
    errdefer posix.munmap(mapped);

    var self: PersistRing = .{
        .fd = fd,
        .mapped = mapped,
        .cap = cap,
    };

    // Initialize header on fresh ring.
    const hdr = self.header();
    if (hdr.magic != MAGIC) {
        hdr.* = .{
            .magic = MAGIC,
            .write_offset = 0,
            .generation = 0,
        };
    }

    return self;
}

pub fn close(self: *PersistRing) void {
    posix.munmap(self.mapped);
    posix.close(self.fd);
    self.* = undefined;
}

fn header(self: *PersistRing) *Header {
    return @ptrCast(@alignCast(self.mapped.ptr));
}

fn payload(self: *PersistRing) []u8 {
    return self.mapped[HEADER_SIZE..];
}

/// Append `bytes` to the ring. Wraps around at `cap`. Cheap memcpy +
/// atomic offset increment — no fsync, no msync (those are batched
/// every 1s from `msyncAsync`).
pub fn append(self: *PersistRing, bytes: []const u8) void {
    if (bytes.len == 0) return;
    const hdr = self.header();
    const pl = self.payload();

    // Compute physical write position. Atomic so two threads writing to
    // the same ring file would not corrupt the offset (in practice each
    // pane has its own ring, single-writer; this is for paranoia).
    const start_off = @atomicRmw(u64, &hdr.write_offset, .Add, bytes.len, .release);
    const phys_start: usize = @intCast(start_off % @as(u64, self.cap));

    // Single-segment fast path.
    if (phys_start + bytes.len <= self.cap) {
        @memcpy(pl[phys_start..][0..bytes.len], bytes);
        return;
    }

    // Wraparound: split into two memcpys.
    const first = self.cap - phys_start;
    @memcpy(pl[phys_start..][0..first], bytes[0..first]);
    @memcpy(pl[0 .. bytes.len - first], bytes[first..]);
    _ = @atomicRmw(u64, &hdr.generation, .Add, 1, .release);
}

/// Schedule asynchronous flush of dirty pages to disk. Caller invokes
/// this every ~1 second (e.g. from a libxev timer). Cheap; returns
/// immediately. Bounds macOS-crash data loss to ≤ 1 second.
pub fn msyncAsync(self: *PersistRing) !void {
    // posix.msync currently has limited Zig stdlib coverage on macOS;
    // call the libc wrapper directly via std.c.
    const c = std.c;
    const rc = c.msync(self.mapped.ptr, self.mapped.len, c.MSF.ASYNC);
    if (rc != 0) {
        log.warn("msync failed errno={d}", .{c.getErrno(rc).?});
        return error.MsyncFailed;
    }
}

/// Replay the most recent ≤ cap bytes of PTY output into `out`.
/// Returns the slice of `out` actually filled. Caller-allocated `out`
/// must be at least `cap` bytes for full replay.
pub fn replay(self: *PersistRing, out: []u8) []u8 {
    const hdr = self.header();
    const pl = self.payload();
    const wrt = @atomicLoad(u64, &hdr.write_offset, .acquire);
    const wrt_usize: usize = @intCast(@min(wrt, @as(u64, self.cap)));
    const have: usize = @min(wrt_usize, out.len);

    if (wrt < self.cap) {
        // Ring not yet wrapped: payload[0..wrt] is the entire stream.
        @memcpy(out[0..have], pl[0..have]);
        return out[0..have];
    }

    // Ring wrapped: oldest byte is at (wrt mod cap), newest at (wrt-1 mod cap).
    const phys: usize = @intCast(wrt % @as(u64, self.cap));
    const first = self.cap - phys;
    if (have <= first) {
        @memcpy(out[0..have], pl[phys..][0..have]);
    } else {
        @memcpy(out[0..first], pl[phys..][0..first]);
        @memcpy(out[first..have], pl[0 .. have - first]);
    }
    return out[0..have];
}

// ============================================================================
// Selftest scaffolding (Phase B1-impl will wire actual integration tests).
// ============================================================================

test "open + append + replay round-trip (no wrap)" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path_z = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(path_z);

    const ring_path = try std.fmt.allocPrintSentinel(
        std.testing.allocator,
        "{s}/test.ring",
        .{path_z},
        0,
    );
    defer std.testing.allocator.free(ring_path);

    var ring = try PersistRing.open(ring_path, 1024);
    defer ring.close();

    ring.append("hello ");
    ring.append("world");

    var buf: [1024]u8 = undefined;
    const got = ring.replay(&buf);
    try std.testing.expectEqualStrings("hello world", got);
}

test "wrap-around preserves only most recent cap bytes" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path_z = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(path_z);

    const ring_path = try std.fmt.allocPrintSentinel(
        std.testing.allocator,
        "{s}/wrap.ring",
        .{path_z},
        0,
    );
    defer std.testing.allocator.free(ring_path);

    const cap: usize = 16;
    var ring = try PersistRing.open(ring_path, cap);
    defer ring.close();

    // Write 32 bytes of distinct content; only last 16 should survive.
    const long_input = "0123456789abcdefABCDEFGHIJKLMNOP";
    ring.append(long_input);

    var buf: [16]u8 = undefined;
    const got = ring.replay(&buf);
    try std.testing.expectEqualStrings("ABCDEFGHIJKLMNOP", got);
}
