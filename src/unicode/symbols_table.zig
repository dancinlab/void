const lut = @import("lut.zig");

/// The lookup tables for Void.
pub const table = table: {
    // This is only available after running a generator as part of the Void
    // build.zig process, but due to Zig's lazy analysis we can still reference
    // it here.
    //
    // An example process is the `main` in `symbols_uucode.zig`
    const generated = @import("symbols_tables").Tables(bool);
    const Tables = lut.Tables(bool);
    break :table Tables{
        .stage1 = &generated.stage1,
        .stage2 = &generated.stage2,
        .stage3 = &generated.stage3,
    };
};
