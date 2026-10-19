#include "icon_provider.hpp"

#include <QGuiApplication>
#include <QSize>

#include <cstdio>

namespace {

bool expect(bool condition, const char *message)
{
    if (condition)
        return true;
    std::fprintf(stderr, "FAIL: %s\n", message);
    return false;
}

int orangePixels(const QImage &image)
{
    int count = 0;
    for (int y = 0; y < image.height(); ++y) {
        for (int x = 0; x < image.width(); ++x) {
            const QColor pixel = image.pixelColor(x, y);
            if (pixel.alpha() > 0 && pixel.red() > pixel.green() && pixel.green() > pixel.blue())
                ++count;
        }
    }
    return count;
}

} // namespace

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    IconProvider provider;
    bool ok = true;
    QSize size;

    const QImage figmaPlay = provider.requestImage(QStringLiteral("play?D37918"), &size, QSize(48, 48));
    ok &= expect(!figmaPlay.isNull() && size == QSize(48, 48), "Figma icon loads at the requested size");
    ok &= expect(orangePixels(figmaPlay) > 0, "Figma icon's base gray is recolored from the requested tint");

    const QImage lucideFallback = provider.requestImage(QStringLiteral("eye-off?D37918"), &size, QSize(48, 48));
    ok &= expect(!lucideFallback.isNull(), "existing Lucide icon remains available as a fallback");
    ok &= expect(orangePixels(lucideFallback) > 0, "Lucide fallback still accepts a runtime tint");

    const QImage figmaCone = provider.requestImage(QStringLiteral("cone?3C3C3C"), &size, QSize(48, 48));
    ok &= expect(orangePixels(figmaCone) > 0, "Figma VLC mark retains its orange brand fills");

    return ok ? 0 : 1;
}
