#ifndef GHOSTTY_GTK_H
#define GHOSTTY_GTK_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct _GtkWidget GtkWidget;
typedef struct ghostty_gtk_context_s ghostty_gtk_context_t;
typedef struct ghostty_gtk_text_s {
    char *text;
    size_t text_len;
    uint32_t cols;
    uint32_t rows;
} ghostty_gtk_text_t;
typedef void (*ghostty_gtk_context_wakeup_fn)(void *userdata);

typedef enum ghostty_gtk_text_scope_e {
    GHOSTTY_GTK_TEXT_VISIBLE = 0,
    GHOSTTY_GTK_TEXT_ALL = 1,
} ghostty_gtk_text_scope_t;

ghostty_gtk_context_t *ghostty_gtk_context_new(void);
void ghostty_gtk_context_free(ghostty_gtk_context_t *context);
int ghostty_gtk_context_register(ghostty_gtk_context_t *context);
int ghostty_gtk_context_set_wakeup_callback(
    ghostty_gtk_context_t *context,
    ghostty_gtk_context_wakeup_fn callback,
    void *userdata
);
int ghostty_gtk_context_tick(ghostty_gtk_context_t *context);

// Returns a full reference. Callers should unref with ghostty_gtk_surface_free
// after the widget is no longer needed.
GtkWidget *ghostty_gtk_surface_new(ghostty_gtk_context_t *context);
GtkWidget *ghostty_gtk_surface_new_with_working_directory(
    ghostty_gtk_context_t *context,
    const char *working_directory
);
GtkWidget *ghostty_gtk_surface_new_with_working_directory_and_command(
    ghostty_gtk_context_t *context,
    const char *working_directory,
    const char *const *argv,
    size_t argv_len
);
GtkWidget *ghostty_gtk_surface_new_with_working_directory_command_and_scrollback_limit(
    ghostty_gtk_context_t *context,
    const char *working_directory,
    const char *const *argv,
    size_t argv_len,
    size_t scrollback_limit
);
int ghostty_gtk_surface_send_text(
    GtkWidget *surface,
    const char *text,
    size_t text_len
);
int ghostty_gtk_surface_read_text(
    GtkWidget *surface,
    ghostty_gtk_text_scope_t scope,
    ghostty_gtk_text_t *out
);
int ghostty_gtk_surface_read_text_limited(
    GtkWidget *surface,
    ghostty_gtk_text_scope_t scope,
    size_t max_bytes,
    int truncate_from_end,
    ghostty_gtk_text_t *out
);
void ghostty_gtk_text_free(ghostty_gtk_text_t *text);

// Writes the child process exit code to *out_code and returns 1 if the
// surface's child has exited; returns 0 (leaving *out_code untouched) if it
// is still running or the surface is invalid.
int ghostty_gtk_surface_exit_code(GtkWidget *surface, uint32_t *out_code);

// Writes the surface's child process PID to *out_pid and returns 1 once the
// child has been spawned; returns 0 (leaving *out_pid untouched) if the surface
// is invalid/not yet initialized or the child has not been spawned yet. The PID
// is cached on the GTK main thread, so this is safe to call from there.
int ghostty_gtk_surface_child_pid(GtkWidget *surface, int64_t *out_pid);

// Performs a Ghostty keybinding action on the surface by name, using the same
// grammar as Ghostty's `keybind` config values (e.g. "copy_to_clipboard",
// "paste_from_clipboard", "select_all", "start_search"). Returns 1 if the
// action was performed, 0 if the surface is invalid/not yet initialized, the
// action name is unknown, or the action reported no effect.
int ghostty_gtk_surface_perform_action(GtkWidget *surface, const char *action);

// Injects already terminal-ready bytes (CR/LF normalized by the caller) into
// the surface's terminal VT stream (scrollback/screen) WITHOUT writing them to
// the child PTY. Used to restore persisted scrollback on respawn, so restored
// output is not replayed as shell input. Returns 1 on success, 0 if the surface
// is invalid or not yet initialized.
int ghostty_gtk_surface_restore_scrollback(
    GtkWidget *surface,
    const char *text,
    size_t text_len
);

void ghostty_gtk_surface_free(GtkWidget *surface);

#ifdef __cplusplus
}
#endif

#endif
