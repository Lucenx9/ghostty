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

typedef enum ghostty_gtk_text_scope_e {
    GHOSTTY_GTK_TEXT_VISIBLE = 0,
    GHOSTTY_GTK_TEXT_ALL = 1,
} ghostty_gtk_text_scope_t;

ghostty_gtk_context_t *ghostty_gtk_context_new(void);
void ghostty_gtk_context_free(ghostty_gtk_context_t *context);
int ghostty_gtk_context_register(ghostty_gtk_context_t *context);
int ghostty_gtk_context_tick(ghostty_gtk_context_t *context);

// Returns a full reference. Callers should unref with ghostty_gtk_surface_free
// after the widget is no longer needed.
GtkWidget *ghostty_gtk_surface_new(ghostty_gtk_context_t *context);
GtkWidget *ghostty_gtk_surface_new_with_working_directory(
    ghostty_gtk_context_t *context,
    const char *working_directory
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
void ghostty_gtk_text_free(ghostty_gtk_text_t *text);

// Writes the child process exit code to *out_code and returns 1 if the
// surface's child has exited; returns 0 (leaving *out_code untouched) if it
// is still running or the surface is invalid.
int ghostty_gtk_surface_exit_code(GtkWidget *surface, uint32_t *out_code);

void ghostty_gtk_surface_free(GtkWidget *surface);

#ifdef __cplusplus
}
#endif

#endif
