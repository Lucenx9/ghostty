//! Experimental C ABI for embedding the Ghostty GTK widget in another GTK app.
//!
//! This is intentionally separate from main_c.zig, which remains the embedded
//! non-GTK C API used by existing libghostty consumers.

const std = @import("std");
const builtin = @import("builtin");
const gio = @import("gio");
const glib = @import("glib");
const gobject = @import("gobject");
const gtk = @import("gtk");

const main = @import("main_ghostty.zig");
const input = @import("input.zig");
const state = &@import("global.zig").state;
const CoreApp = @import("App.zig");
const GtkApp = @import("apprt/gtk/App.zig");
const gtk_application = @import("apprt/gtk/class/application.zig");
const Application = gtk_application.Application;
const Surface = @import("apprt/gtk/class/surface.zig").Surface;
const configpkg = @import("config.zig");

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

    context.* = .{
        .core_app = core_app,
        .gtk_app = undefined,
    };
    context.gtk_app.init(core_app, .{}) catch |err| {
        std.log.err("failed to create Ghostty GTK app: {}", .{err});
        return null;
    };

    Application.setEmbeddedDefault(context.gtk_app.app);
    return context;
}

pub export fn ghostty_gtk_context_free(context_: ?*Context) void {
    const context = context_ orelse return;
    const alloc = std.heap.c_allocator;

    Application.setEmbeddedWakeupCallback(null, null);
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

pub export fn ghostty_gtk_context_set_wakeup_callback(
    context_: ?*Context,
    callback: ?gtk_application.EmbeddedWakeupCallback,
    userdata: ?*anyopaque,
) c_int {
    _ = context_ orelse return 0;
    Application.setEmbeddedWakeupCallback(callback, userdata);
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

fn surfaceNew(
    context: *Context,
    working_directory: ?[:0]const u8,
    command: ?configpkg.Command,
    scrollback_limit: ?usize,
) ?*gtk.Widget {
    if (ghostty_gtk_context_register(context) == 0) return null;

    const surface = Surface.new(.{
        .command = command,
        .working_directory = working_directory,
        .scrollback_limit = scrollback_limit,
        .wait_after_command = true,
        .cursor_style_blink = false,
    });
    return surface.refSink().as(gtk.Widget);
}

pub export fn ghostty_gtk_surface_new(context_: ?*Context) ?*gtk.Widget {
    const context = context_ orelse return null;
    return surfaceNew(context, null, null, null);
}

pub export fn ghostty_gtk_surface_new_with_working_directory(
    context_: ?*Context,
    working_directory_: ?[*:0]const u8,
) ?*gtk.Widget {
    const context = context_ orelse return null;
    const working_directory = if (working_directory_) |ptr| std.mem.span(ptr) else null;
    return surfaceNew(context, working_directory, null, null);
}

pub export fn ghostty_gtk_surface_new_with_working_directory_and_command(
    context_: ?*Context,
    working_directory_: ?[*:0]const u8,
    argv_: ?[*]const [*:0]const u8,
    argv_len: usize,
) ?*gtk.Widget {
    const context = context_ orelse return null;
    const argv_ptr = argv_ orelse return null;
    if (argv_len == 0) return null;

    const working_directory = if (working_directory_) |ptr| std.mem.span(ptr) else null;
    const alloc = std.heap.c_allocator;
    const argv = alloc.alloc([:0]const u8, argv_len) catch return null;
    defer alloc.free(argv);
    for (argv_ptr[0..argv_len], 0..) |arg, index| {
        argv[index] = std.mem.span(arg);
    }
    const command: configpkg.Command = .{ .direct = argv };
    return surfaceNew(context, working_directory, command, null);
}

pub export fn ghostty_gtk_surface_new_with_working_directory_command_and_scrollback_limit(
    context_: ?*Context,
    working_directory_: ?[*:0]const u8,
    argv_: ?[*]const [*:0]const u8,
    argv_len: usize,
    scrollback_limit: usize,
) ?*gtk.Widget {
    const context = context_ orelse return null;
    const argv_ptr = argv_ orelse return null;
    if (argv_len == 0) return null;

    const working_directory = if (working_directory_) |ptr| std.mem.span(ptr) else null;
    const alloc = std.heap.c_allocator;
    const argv = alloc.alloc([:0]const u8, argv_len) catch return null;
    defer alloc.free(argv);
    for (argv_ptr[0..argv_len], 0..) |arg, index| {
        argv[index] = std.mem.span(arg);
    }
    const command: configpkg.Command = .{ .direct = argv };
    return surfaceNew(context, working_directory, command, scrollback_limit);
}

pub export fn ghostty_gtk_surface_send_text(
    surface_: ?*gtk.Widget,
    text_: ?[*]const u8,
    text_len: usize,
) c_int {
    if (text_len == 0) return 1;
    const surface_widget = surface_ orelse return 0;
    const text_ptr = text_ orelse return 0;
    const surface = gobject.ext.cast(Surface, surface_widget) orelse return 0;
    const core_surface = surface.core() orelse return 0;
    core_surface.writeBytes(text_ptr[0..text_len]) catch |err| {
        std.log.warn("failed to send text to Ghostty GTK surface: {}", .{err});
        return 0;
    };
    return 1;
}

/// Inject already terminal-ready bytes (CR/LF normalized by the caller) into
/// the surface's terminal VT stream (scrollback/screen) WITHOUT writing them to
/// the child PTY, so restored scrollback is not replayed as shell input. Routes
/// through the IO thread (processOutput) the same way writeBytes routes through
/// queueWrite. Returns 1 on success, 0 if the surface is invalid/not yet
/// initialized.
pub export fn ghostty_gtk_surface_restore_scrollback(
    surface_: ?*gtk.Widget,
    text_: ?[*]const u8,
    text_len: usize,
) c_int {
    if (text_len == 0) return 1;
    const surface_widget = surface_ orelse return 0;
    const text_ptr = text_ orelse return 0;
    const surface = gobject.ext.cast(Surface, surface_widget) orelse return 0;
    const core_surface = surface.core() orelse return 0;
    core_surface.injectOutput(text_ptr[0..text_len]) catch |err| {
        std.log.warn("failed to restore scrollback to Ghostty GTK surface: {}", .{err});
        return 0;
    };
    return 1;
}

pub const GhosttyGtkText = extern struct {
    text: ?[*]u8,
    text_len: usize,
    cols: u32,
    rows: u32,
};

fn clearText(text: *GhosttyGtkText) void {
    text.* = .{
        .text = null,
        .text_len = 0,
        .cols = 0,
        .rows = 0,
    };
}

pub export fn ghostty_gtk_surface_read_text(
    surface_: ?*gtk.Widget,
    scope_raw: c_int,
    out_: ?*GhosttyGtkText,
) c_int {
    const out = out_ orelse return 0;
    clearText(out);

    const surface_widget = surface_ orelse return 0;
    const surface = gobject.ext.cast(Surface, surface_widget) orelse return 0;
    const core_surface = surface.core() orelse return 0;
    const scope: @import("Surface.zig").PlainTextScope = @enumFromInt(scope_raw);
    const text = core_surface.dumpPlainText(std.heap.c_allocator, scope) catch |err| {
        std.log.warn("failed to read text from Ghostty GTK surface: {}", .{err});
        return 0;
    };
    out.* = .{
        .text = @ptrCast(@constCast(text.text.ptr)),
        .text_len = text.text.len,
        .cols = text.cols,
        .rows = text.rows,
    };
    return 1;
}

pub export fn ghostty_gtk_surface_read_text_limited(
    surface_: ?*gtk.Widget,
    scope_raw: c_int,
    max_bytes: usize,
    truncate_from_end: c_int,
    out_: ?*GhosttyGtkText,
) c_int {
    const out = out_ orelse return 0;
    clearText(out);

    const surface_widget = surface_ orelse return 0;
    const surface = gobject.ext.cast(Surface, surface_widget) orelse return 0;
    const core_surface = surface.core() orelse return 0;
    const scope: @import("Surface.zig").PlainTextScope = @enumFromInt(scope_raw);
    const text = core_surface.dumpPlainTextLimited(
        std.heap.c_allocator,
        scope,
        max_bytes,
        truncate_from_end != 0,
    ) catch |err| {
        std.log.warn("failed to read limited text from Ghostty GTK surface: {}", .{err});
        return 0;
    };
    out.* = .{
        .text = @ptrCast(@constCast(text.text.ptr)),
        .text_len = text.text.len,
        .cols = text.cols,
        .rows = text.rows,
    };
    return 1;
}

pub export fn ghostty_gtk_text_free(text_: ?*GhosttyGtkText) void {
    const text = text_ orelse return;
    if (text.text) |ptr| {
        std.heap.c_allocator.free(ptr[0..text.text_len]);
    }
    clearText(text);
}

pub export fn ghostty_gtk_surface_exit_code(
    surface_: ?*gtk.Widget,
    out_code: ?*u32,
) c_int {
    const out = out_code orelse return 0;
    const surface_widget = surface_ orelse return 0;
    const surface = gobject.ext.cast(Surface, surface_widget) orelse return 0;
    const code = surface.childExitCode() orelse return 0;
    out.* = code;
    return 1;
}

/// Write the PID of the surface's child process into `out_pid`. Returns 1 if
/// the PID is available, 0 if the surface is invalid/not yet initialized or the
/// child has not been spawned yet. Prefer the cached child PID handed off from
/// the IO thread; if that startup mailbox has not been observed yet, fall back
/// to the PTY foreground PID exposed by Ghostty's existing embedded API.
pub export fn ghostty_gtk_surface_child_pid(
    surface_: ?*gtk.Widget,
    out_pid: ?*i64,
) c_int {
    const out = out_pid orelse return 0;
    const surface_widget = surface_ orelse return 0;
    const surface = gobject.ext.cast(Surface, surface_widget) orelse return 0;
    const core_surface = surface.core() orelse return 0;
    if (core_surface.child_pid) |pid| {
        out.* = pid;
        return 1;
    }
    const foreground_pid = core_surface.getProcessInfo(.foreground_pid) orelse return 0;
    out.* = std.math.cast(i64, foreground_pid) orelse return 0;
    return 1;
}

/// Perform a Ghostty keybinding action on the surface by name. The action is
/// parsed with the same grammar as Ghostty's `keybind` config values (e.g.
/// "copy_to_clipboard", "paste_from_clipboard", "select_all", "start_search").
/// Returns 1 if the action was performed, 0 if the surface is invalid/not yet
/// initialized, the action name is unknown, or the action reported no effect.
pub export fn ghostty_gtk_surface_perform_action(
    surface_: ?*gtk.Widget,
    action_: ?[*:0]const u8,
) c_int {
    const surface_widget = surface_ orelse return 0;
    const action_ptr = action_ orelse return 0;
    const surface = gobject.ext.cast(Surface, surface_widget) orelse return 0;
    const core_surface = surface.core() orelse return 0;
    const action = input.Binding.Action.parse(std.mem.span(action_ptr)) catch |err| {
        std.log.warn("unknown Ghostty GTK action: {}", .{err});
        return 0;
    };
    const performed = core_surface.performBindingAction(action) catch |err| {
        std.log.warn("failed to perform Ghostty GTK action: {}", .{err});
        return 0;
    };
    return @intFromBool(performed);
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
