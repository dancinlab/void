//! Build logic for Void. A single "build.zig" file became far too complex
//! and spaghetti, so this package extracts the build logic into smaller,
//! more manageable pieces.

pub const gtk = @import("gtk.zig");
pub const Config = @import("Config.zig");
pub const GitVersion = @import("GitVersion.zig");

// Artifacts
pub const VoidBench = @import("VoidBench.zig");
pub const VoidDist = @import("VoidDist.zig");
pub const VoidDocs = @import("VoidDocs.zig");
pub const VoidExe = @import("VoidExe.zig");
pub const VoidFrameData = @import("VoidFrameData.zig");
pub const VoidLib = @import("VoidLib.zig");
pub const VoidLibVt = @import("VoidLibVt.zig");
pub const VoidResources = @import("VoidResources.zig");
pub const VoidI18n = @import("VoidI18n.zig");
pub const VoidXcodebuild = @import("VoidXcodebuild.zig");
pub const VoidXCFramework = @import("VoidXCFramework.zig");
pub const VoidWebdata = @import("VoidWebdata.zig");
pub const VoidZig = @import("VoidZig.zig");
pub const HelpStrings = @import("HelpStrings.zig");
pub const SharedDeps = @import("SharedDeps.zig");
pub const UnicodeTables = @import("UnicodeTables.zig");

// Steps
pub const LibtoolStep = @import("LibtoolStep.zig");
pub const LipoStep = @import("LipoStep.zig");
pub const MetallibStep = @import("MetallibStep.zig");
pub const XCFrameworkStep = @import("XCFrameworkStep.zig");

// Helpers
pub const requireZig = @import("zig.zig").requireZig;
