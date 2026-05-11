const builtin = @import("builtin");

/// Base application ID
pub const base_application_id = "com.dancinlab.void";

/// GTK application ID
pub const application_id = switch (builtin.mode) {
    .Debug, .ReleaseSafe => base_application_id ++ "-debug",
    .ReleaseFast, .ReleaseSmall => base_application_id,
};

pub const resource_path = "/com/mitchellh/void";

/// GTK object path
pub const object_path = switch (builtin.mode) {
    .Debug, .ReleaseSafe => resource_path ++ "_debug",
    .ReleaseFast, .ReleaseSmall => resource_path,
};
