#ifndef GHOSTTY_GTK_H
#define GHOSTTY_GTK_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct _GtkWidget GtkWidget;
typedef struct ghostty_gtk_context_s ghostty_gtk_context_t;

ghostty_gtk_context_t *ghostty_gtk_context_new(void);
void ghostty_gtk_context_free(ghostty_gtk_context_t *context);
int ghostty_gtk_context_register(ghostty_gtk_context_t *context);
int ghostty_gtk_context_tick(ghostty_gtk_context_t *context);

GtkWidget *ghostty_gtk_surface_new(ghostty_gtk_context_t *context);
void ghostty_gtk_surface_free(GtkWidget *surface);

#ifdef __cplusplus
}
#endif

#endif
