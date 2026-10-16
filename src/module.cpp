// VLC module descriptor: the "neo" interface + its private video output.
#include "vlc_headers.hpp"
#include <vlc_plugin.h>

#include "frame_store.hpp"
#include "neo.hpp"

static int Open(vlc_object_t *);
static void Close(vlc_object_t *);

#define VOUT_NAME "neo_vout"

vlc_module_begin()
    set_shortname("Neo")
    set_description("Neo - modern VLC interface (Qt Quick)")
    set_category(CAT_INTERFACE)
    set_subcategory(SUBCAT_INTERFACE_MAIN)
    set_capability("interface", 0)
    set_callbacks(Open, Close)
    add_shortcut("neo")

    add_submodule()
        set_description("Neo video output")
        set_capability("vout display", 0)
        set_callbacks(NeoVoutOpen, NeoVoutClose)
        add_shortcut(VOUT_NAME)
vlc_module_end()

struct intf_sys_t
{
    vlc_thread_t thread;
    vlc_sem_t ready;
};

static void SignalReady(void *data)
{
    intf_sys_t *sys = (intf_sys_t *)data;
    vlc_sem_post(&sys->ready);
}

static void *UiThread(void *data)
{
    intf_thread_t *intf = (intf_thread_t *)data;
    NeoRunUi(intf, SignalReady, intf->p_sys);
    FrameStore::instance().uiActive = false;
    // UI closed by the user: stop the whole player.
    libvlc_Quit(intf->obj.libvlc);
    return nullptr;
}

static int Open(vlc_object_t *obj)
{
    intf_thread_t *intf = (intf_thread_t *)obj;
    intf_sys_t *sys = new (std::nothrow) intf_sys_t;
    if (!sys)
        return VLC_ENOMEM;
    intf->p_sys = sys;

    playlist_t *pl = pl_Get(intf);
    // Route every video of this playlist to our display.
    var_Create(pl, "vout", VLC_VAR_STRING);
    var_SetString(pl, "vout", VOUT_NAME ",any");
    FrameStore::instance().uiActive = true;

    vlc_sem_init(&sys->ready, 0);
    if (vlc_clone(&sys->thread, UiThread, intf, VLC_THREAD_PRIORITY_LOW))
    {
        vlc_sem_destroy(&sys->ready);
        FrameStore::instance().uiActive = false;
        delete sys;
        return VLC_ENOMEM;
    }
    // Do not let playback start before the UI can show it.
    vlc_sem_wait(&sys->ready);
    vlc_sem_destroy(&sys->ready);
    return VLC_SUCCESS;
}

static void Close(vlc_object_t *obj)
{
    intf_thread_t *intf = (intf_thread_t *)obj;
    intf_sys_t *sys = intf->p_sys;
    playlist_t *pl = pl_Get(intf);

    // Release the video output while the UI still exists.
    playlist_Deactivate(pl);
    FrameStore::instance().uiActive = false;

    NeoQuitUi();
    vlc_join(sys->thread, nullptr);

    var_Destroy(pl, "vout");
    delete sys;
}
