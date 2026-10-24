#include "icon_provider.hpp"

#include <QCryptographicHash>
#include <QFile>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QPainter>
#include <QSize>
#include <QSvgRenderer>
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

int visiblePixels(const QImage &image)
{
    int count = 0;
    for (int y = 0; y < image.height(); ++y) {
        for (int x = 0; x < image.width(); ++x) {
            if (image.pixelColor(x, y).alpha() > 0)
                ++count;
        }
    }
    return count;
}

QImage renderSvg(const QByteArray &svg, const QSize &size)
{
    QImage image(size, QImage::Format_ARGB32_Premultiplied);
    image.fill(Qt::transparent);
    QSvgRenderer renderer(svg);
    if (!renderer.isValid())
        return {};
    QPainter painter(&image);
    renderer.render(&painter);
    return image;
}

} // namespace

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    IconProvider provider;
    bool ok = true;
    QSize size;

    QFile figmaIndexFile(QStringLiteral(":/neo/assets/figma-icons/index.json"));
    const bool indexLoaded = figmaIndexFile.open(QIODevice::ReadOnly);
    const QJsonObject figmaIndex = indexLoaded
        ? QJsonDocument::fromJson(figmaIndexFile.readAll()).object() : QJsonObject();
    ok &= expect(indexLoaded && figmaIndex.value(QStringLiteral("count")).toInt() == 206
                     && figmaIndex.value(QStringLiteral("icons")).toArray().size() == 206,
                 "the canonical Figma index contains all 206 exported icons");

    QFile figmaSumsFile(QStringLiteral(":/neo/assets/figma-icons/SHA256SUMS"));
    const bool sumsLoaded = figmaSumsFile.open(QIODevice::ReadOnly);
    ok &= expect(sumsLoaded, "the pinned Figma SHA-256 manifest is bundled with the icons");
    int verifiedFigmaFiles = 0;
    int verifiedFigmaIcons = 0;
    if (sumsLoaded) {
        const QByteArray manifest = figmaSumsFile.readAll();
        ok &= expect(manifest.contains("Source commit: 2c4b704edc49e01b6375de034ff8c85aa592918f"),
                     "the Figma manifest records the pinned upstream export commit");
        for (QByteArray line : manifest.split('\n')) {
            line = line.trimmed();
            if (line.isEmpty() || line.startsWith('#'))
                continue;
            const QList<QByteArray> fields = line.simplified().split(' ');
            if (fields.size() != 2 || fields.at(0).size() != 64
                || !fields.at(1).startsWith("assets/figma-icons/")) {
                ok &= expect(false, "the Figma SHA-256 manifest has valid entries");
                continue;
            }
            const QByteArray relativePath = fields.at(1);
            const QByteArray basename = relativePath.mid(QByteArray("assets/figma-icons/").size());
            if (basename.contains('/') || basename == "." || basename == "..") {
                ok &= expect(false, "the Figma manifest only references files in its asset directory");
                continue;
            }
            QFile assetFile(QStringLiteral(":/neo/") + QString::fromUtf8(relativePath));
            const bool assetLoaded = assetFile.open(QIODevice::ReadOnly);
            if (!assetLoaded) {
                const QByteArray name = basename;
                std::fprintf(stderr, "FAIL: pinned Figma asset '%s' is missing from Qt resources\n", name.constData());
                ok = false;
                continue;
            }
            const QByteArray actual = QCryptographicHash::hash(assetFile.readAll(), QCryptographicHash::Sha256).toHex();
            if (actual != fields.at(0)) {
                const QByteArray name = basename;
                std::fprintf(stderr, "FAIL: pinned Figma asset '%s' does not match its SHA-256\n", name.constData());
                ok = false;
                continue;
            }
            ++verifiedFigmaFiles;
            if (basename.endsWith(".svg"))
                ++verifiedFigmaIcons;
        }
    }
    ok &= expect(verifiedFigmaFiles == 207 && verifiedFigmaIcons == 206,
                 "all 206 Figma SVGs and the icon index match the pinned SHA-256 manifest");

    const QImage figmaPlay = provider.requestImage(QStringLiteral("play?D37918"), &size, QSize(48, 48));
    ok &= expect(!figmaPlay.isNull() && size == QSize(48, 48), "Figma icon loads at the requested size");
    ok &= expect(orangePixels(figmaPlay) > 0, "Figma icon's base gray is recolored from the requested tint");

    for (const QString &name : {QStringLiteral("settings-active"), QStringLiteral("interface-active"),
                                QStringLiteral("privacy-active"), QStringLiteral("hotkeys-active"),
                                QStringLiteral("playback-active"), QStringLiteral("video-active"),
                                QStringLiteral("audio-active"), QStringLiteral("subtitles-active"),
                                QStringLiteral("folder-active"), QStringLiteral("streaming-active"),
                                QStringLiteral("preferences-active"), QStringLiteral("record-active"),
                                QStringLiteral("plugins-active")}) {
        QFile canonicalFile(QStringLiteral(":/neo/assets/figma-icons/%1.svg").arg(name));
        const bool canonicalLoaded = canonicalFile.open(QIODevice::ReadOnly);
        const QImage expected = canonicalLoaded ? renderSvg(canonicalFile.readAll(), QSize(48, 48)) : QImage();
        const QImage actual = provider.requestImage(name + QStringLiteral("?D37918"), &size, QSize(48, 48));
        ok &= expect(canonicalLoaded && !actual.isNull() && visiblePixels(actual) > 0 && actual == expected,
                     "selected settings categories render their exact Figma active-state SVG");
    }

    const QImage lucideFallback = provider.requestImage(QStringLiteral("eye-off?D37918"), &size, QSize(48, 48));
    ok &= expect(!lucideFallback.isNull(), "existing Lucide icon remains available as a fallback");
    ok &= expect(orangePixels(lucideFallback) > 0, "Lucide fallback still accepts a runtime tint");
    for (const QString &name : {QStringLiteral("volume-1"), QStringLiteral("volume-x")}) {
        const QImage image = provider.requestImage(name + QStringLiteral("?D37918"), &size, QSize(48, 48));
        ok &= expect(!image.isNull() && visiblePixels(image) > 0,
                     "a volume state without a matching Figma export remains available from Lucide");
    }

    const QImage figmaCone = provider.requestImage(QStringLiteral("cone?3C3C3C"), &size, QSize(48, 48));
    ok &= expect(orangePixels(figmaCone) > 0, "Figma VLC mark retains its orange brand fills");

    const QImage minusAlias = provider.requestImage(QStringLiteral("minus?8F8F8F"), &size, QSize(48, 48));
    const QImage figmaRemove = provider.requestImage(QStringLiteral("remove?8F8F8F"), &size, QSize(48, 48));
    ok &= expect(!minusAlias.isNull() && minusAlias == figmaRemove,
                 "the minus placeholder renders the exact Figma remove SVG");

    const auto &figmaAliases = IconProvider::figmaAliases();
    ok &= expect(figmaAliases.value(QStringLiteral("refresh-cw")) == QStringLiteral("refresh"),
                 "the refresh-cw callsite points to the exact Figma refresh export");
    ok &= expect(figmaAliases.value(QStringLiteral("video-file")) == QStringLiteral("video-two-tone"),
                 "the video-file alias points to the exported two-tone Figma video asset");
    for (auto it = figmaAliases.cbegin(); it != figmaAliases.cend(); ++it) {
        if (it.key() == QLatin1String("video-file"))
            continue; // Its two-tone source is deliberately recolored for the subtitle-match row.
        const QString tint = QStringLiteral("?8F8F8F");
        const QImage aliasImage = provider.requestImage(it.key() + tint, &size, QSize(48, 48));
        QFile canonicalFile(QStringLiteral(":/neo/assets/figma-icons/%1.svg").arg(it.value()));
        const bool canonicalLoaded = canonicalFile.open(QIODevice::ReadOnly);
        QByteArray canonicalSvg = canonicalLoaded ? canonicalFile.readAll() : QByteArray();
        canonicalSvg.replace("#8f8f8f", "#8F8F8F");
        const QImage canonicalImage = canonicalLoaded ? renderSvg(canonicalSvg, QSize(48, 48)) : QImage();
        if (!canonicalLoaded || aliasImage.isNull() || canonicalImage.isNull()
            || visiblePixels(aliasImage) == 0 || visiblePixels(canonicalImage) == 0
            || aliasImage != canonicalImage) {
            const QByteArray aliasName = it.key().toUtf8();
            const QByteArray sourceName = it.value().toUtf8();
            std::fprintf(stderr, "FAIL: Figma alias '%s' must render the present canonical '%s.svg' SVG\n",
                         aliasName.constData(), sourceName.constData());
            ok = false;
        }
    }

    const QImage monochromeVideo = provider.requestImage(QStringLiteral("video-file?8F8F8F"), &size, QSize(48, 48));
    QFile videoSvgFile(QStringLiteral(":/neo/assets/figma-icons/video-two-tone.svg"));
    QByteArray videoSvg;
    const bool videoSvgLoaded = videoSvgFile.open(QIODevice::ReadOnly);
    if (videoSvgLoaded) {
        videoSvg = videoSvgFile.readAll();
        videoSvg.replace("#D37918", "#8F8F8F");
        videoSvg.replace("#d37918", "#8f8f8f");
    }
    const QImage expectedMonochromeVideo = videoSvgLoaded ? renderSvg(videoSvg, QSize(48, 48)) : QImage();
    ok &= expect(!monochromeVideo.isNull() && visiblePixels(monochromeVideo) > 0,
                 "the subtitle match row renders the exported Figma video icon");
    ok &= expect(expectedMonochromeVideo == monochromeVideo,
                 "the video-file alias renders the exact two-tone export with Figma gray recoloring");
    ok &= expect(orangePixels(monochromeVideo) == 0,
                 "the video-file icon tint matches the gray Figma state");

    for (const QString &name : {QStringLiteral("favorite"), QStringLiteral("home"),
                                QStringLiteral("thumbnail"), QStringLiteral("sidebar-right"),
                                QStringLiteral("replay"), QStringLiteral("bookmarks"),
                                QStringLiteral("quit"), QStringLiteral("divider"),
                                QStringLiteral("ui"), QStringLiteral("file"),
                                QStringLiteral("folder"), QStringLiteral("video"),
                                QStringLiteral("minimize")}) {
        const QImage image = provider.requestImage(name + QStringLiteral("?8F8F8F"), &size, QSize(48, 48));
        ok &= expect(visiblePixels(image) > 0, "a Figma control icon renders visible SVG pixels");
    }

    return ok ? 0 : 1;
}
