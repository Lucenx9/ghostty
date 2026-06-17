//! Experimental C ABI for embedding the Ghostty GTK widget in another GTK app.
//!
//! This is intentionally separate from main_c.zig, which remains the embedded
//! non-GTK C API used by existing libghostty consumers.

const std = @import("std");
const builtin = @import("builtin");
const gio = @import("gio");
const glib = @import("glib");
const gtk = @import("gtk");

const main = @import("main_ghostty.zig");
const state = &@import("global.zig").state;
const CoreApp = @import("App.zig");
const GtkApp = @import("apprt/gtk/App.zig");
const Application = @import("apprt/gtk/class/application.zig").Application;
const Surface = @import("apprt/gtk/class/surface.zig").Surface;

pub const std_options = main.std_options;

const Context = struct {
    core_app: *CoreApp,
    gtk_app: GtkApp,
    registered: bool = false,
};

var global_state_initialized = false;

fn initGlobalState() !void {
    if (global_state_initialized) return;
    try state.init();
    global_state_initialized = true;
}

fn contextFromOpaque(context: ?*anyopaque) ?*Context {
    const ptr = context orelse return null;
    return @ptrCast(@alignCast(ptr));
}

pub export fn ghostty_gtk_context_new() ?*Context {
    initGlobalState() catch |err| {
        std.log.err("failed to initialize Ghostty global state: {}", .{err});
        return null;
    };

    const alloc = std.heap.c_allocator;
    const context = alloc.create(Context) catch return null;
    errdefer alloc.destroy(context);

    const core_app = CoreApp.create(alloc) catch |err| {
        std.log.err("failed to create Ghostty core app: {}", .{err});
        return null;
    };
    errdefer core_app.destroy();

    var gtk_app: GtkApp = undefined;
    gtk_app.init(core_app, .{}) catch |err| {
        std.log.err("failed to create Ghostty GTK app: {}", .{err});
        return null;
    };

    context.* = .{
        .core_app = core_app,
        .gtk_app = gtk_app,
    };
    Application.setEmbeddedDefault(context.gtk_app.app);
    return context;
}

pub export fn ghostty_gtk_context_free(context_: ?*Context) void {
    const context = context_ orelse return;
    const alloc = std.heap.c_allocator;

    context.gtk_app.terminate();
    Application.setEmbeddedDefault(null);
    context.gtk_app.app.unref();
    context.core_app.destroy();
    alloc.destroy(context);
}

pub export fn ghostty_gtk_context_register(context_: ?*Context) c_int {
    const context = context_ orelse return 0;
    if (context.registered) return 1;

    var err_: ?*glib.Error = null;
    if (context.gtk_app.app.as(gio.Application).register(null, &err_) == 0) {
        if (err_) |err| {
            defer err.free();
            std.log.warn("error registering Ghostty GTK application: {s}", .{
                err.f_message orelse "(unknown)",
            });
        }
        return 0;
    }

    context.registered = true;
    return 1;
}

pub export fn ghostty_gtk_context_tick(context_: ?*Context) c_int {
    const context = context_ orelse return 0;
    context.core_app.tick(&context.gtk_app) catch |err| {
        std.log.warn("Ghostty GTK tick failed: {}", .{err});
        return 0;
    };
    return 1;
}

pub export fn ghostty_gtk_surface_new(context_: ?*Context) ?*gtk.Widget {
    const context = context_ orelse return null;
    if (ghostty_gtk_context_register(context) == 0) return null;

    const surface = Surface.new(.none);
    return surface.as(gtk.Widget);
}

pub export fn ghostty_gtk_surface_free(surface_: ?*gtk.Widget) void {
    const surface = surface_ orelse return;
    surface.unref();
}

comptime {
    if (!builtin.link_libc) {
        @compileError("ghostty_gtk requires libc");
    }
}
