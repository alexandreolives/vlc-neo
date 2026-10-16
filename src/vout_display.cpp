// "vout display" submodule: receives decoded RGB32 pictures from the VLC core
// (subtitles and OSD already blended) and hands them to the QML VideoItem.
#include "vlc_headers.hpp"
#include "frame_store.hpp"
#include "neo.hpp"

#include <cstring>

struct vout_display_sys_t
{
    picture_pool_t *pool = nullptr;
};

static picture_pool_t *Pool(vout_display_t *vd, unsigned count)
{
    vout_display_sys_t *sys = vd->sys;
    if (sys->pool == nullptr)
        sys->pool = picture_pool_NewFromFormat(&vd->fmt, count);
    return sys->pool;
}

static void Display(vout_display_t *vd, picture_t *pic, subpicture_t *subpic)
{
    const plane_t &plane = pic->p[0];

    // Respect user crop when the picture is not rotated (source == fmt geometry).
    const video_format_t &src = vd->source;
    const bool useSourceGeometry = src.orientation == ORIENT_NORMAL
        && src.i_width == vd->fmt.i_width && src.i_height == vd->fmt.i_height;
    const video_format_t &geo = useSourceGeometry ? src : vd->fmt;

    const int x = geo.i_x_offset;
    const int y = geo.i_y_offset;
    const int w = geo.i_visible_width;
    const int h = geo.i_visible_height;

    if (w > 0 && h > 0 && x + w <= plane.i_pitch / 4 && y + h <= plane.i_lines)
    {
        QImage frame(w, h, QImage::Format_RGB32);
        const int rowBytes = w * 4;
        for (int row = 0; row < h; ++row)
        {
            const uint8_t *in = plane.p_pixels + (size_t)(y + row) * plane.i_pitch + (size_t)x * 4;
            std::memcpy(frame.scanLine(row), in, rowBytes);
        }
        double sar = 1.0;
        if (geo.i_sar_num > 0 && geo.i_sar_den > 0)
            sar = (double)geo.i_sar_num / (double)geo.i_sar_den;
        FrameStore::instance().publish(std::move(frame), sar);
    }

    picture_Release(pic);
    if (subpic)
        subpicture_Delete(subpic);
}

static int Control(vout_display_t *, int query, va_list)
{
    switch (query)
    {
    case VOUT_DISPLAY_RESET_PICTURES:
        return VLC_EGENERIC;
    default:
        // Size, zoom, aspect and crop are handled when presenting the frame.
        return VLC_SUCCESS;
    }
}

int NeoVoutOpen(vlc_object_t *obj)
{
    vout_display_t *vd = (vout_display_t *)obj;

    if (!FrameStore::instance().uiActive.load())
        return VLC_EGENERIC;

    video_format_t fmt;
    video_format_ApplyRotation(&fmt, &vd->fmt);
    fmt.i_chroma = VLC_CODEC_RGB32;
    fmt.i_rmask = 0xff0000;
    fmt.i_gmask = 0x00ff00;
    fmt.i_bmask = 0x0000ff;

    vout_display_sys_t *sys = new (std::nothrow) vout_display_sys_t;
    if (!sys)
        return VLC_ENOMEM;

    vd->sys = sys;
    vd->fmt = fmt;
    vd->pool = Pool;
    vd->prepare = nullptr;
    vd->display = Display;
    vd->control = Control;

    vout_display_SendEventDisplaySize(vd, fmt.i_visible_width, fmt.i_visible_height);
    vout_display_DeleteWindow(vd, nullptr);
    msg_Dbg(vd, "neo video output ready (%ux%u)", fmt.i_visible_width, fmt.i_visible_height);
    return VLC_SUCCESS;
}

void NeoVoutClose(vlc_object_t *obj)
{
    vout_display_t *vd = (vout_display_t *)obj;
    vout_display_sys_t *sys = vd->sys;
    if (sys->pool)
        picture_pool_Release(sys->pool);
    delete sys;
    FrameStore::instance().clear();
}
