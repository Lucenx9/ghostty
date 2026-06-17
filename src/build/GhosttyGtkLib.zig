const GhosttyGtkLib = @This();

const std = @import("std");
const SharedDeps = @import("SharedDeps.zig");

step: *std.Build.Step,
output: std.Build.LazyPath,

pub fn initShared(
    b: *std.Build,
    deps: *const SharedDeps,
) !GhosttyGtkLib {
    const lib = b.addLibrary(.{
        .name = "ghostty-gtk-embed",
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main_gtk_c.zig"),
            .target = deps.config.target,
            .optimize = deps.config.optimize,
            .strip = deps.config.strip,
            .omit_frame_pointer = deps.config.strip,
            .unwind_tables = if (deps.config.strip) .none else .sync,
        }),

        // The GTK apprt transitively pulls in C/C++ and platform libraries.
        .use_llvm = true,
    });

    _ = try deps.add(lib);

    return .{
        .step = &lib.step,
        .output = lib.getEmittedBin(),
    };
}

pub fn install(self: *const GhosttyGtkLib, name: []const u8) void {
    const b = self.step.owner;
    const lib_install = b.addInstallLibFile(self.output, name);
    b.getInstallStep().dependOn(&lib_install.step);
}

pub fn installHeader(self: *const GhosttyGtkLib) void {
    const b = self.step.owner;
    const header_install = b.addInstallHeaderFile(
        b.path("include/ghostty_gtk.h"),
        "ghostty_gtk.h",
    );
    b.getInstallStep().dependOn(&header_install.step);
}
