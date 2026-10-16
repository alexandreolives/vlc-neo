#pragma once

struct vlc_object_t;
struct intf_thread_t;

int NeoVoutOpen(vlc_object_t *obj);
void NeoVoutClose(vlc_object_t *obj);

// Runs the whole Qt/QML UI. Blocks until the UI quits.
// `ready` is invoked once the UI can accept video (before the event loop).
void NeoRunUi(intf_thread_t *intf, void (*ready)(void *), void *readyData);
void NeoQuitUi();
