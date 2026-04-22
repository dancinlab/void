const diags = @import("cli/diagnostics.zig");

pub const args = @import("cli/args.zig");
pub const action = @import("cli/action.zig");
pub const app = @import("cli/void.zig");
pub const CompatibilityHandler = args.CompatibilityHandler;
pub const compatibilityRenamed = args.compatibilityRenamed;
pub const DiagnosticList = diags.DiagnosticList;
pub const Diagnostic = diags.Diagnostic;
pub const Location = diags.Location;

test {
    @import("std").testing.refAllDecls(@This());
}
