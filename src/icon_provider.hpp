// Renders the bundled monochrome SVG icons in any colour:
//   image://icon/play?#D9822B
#pragma once

#include <QFile>
#include <QHash>
#include <QPainter>
#include <QQuickImageProvider>
#include <QSvgRenderer>

class IconProvider : public QQuickImageProvider
{
public:
    IconProvider() : QQuickImageProvider(QQuickImageProvider::Image) {}

    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override
    {
        constexpr int kDefaultSize = 48;
        const int sep = id.indexOf(QLatin1Char('?'));
        const QString name = sep < 0 ? id : id.left(sep);
        const QString color = sep < 0 ? QStringLiteral("#ffffff") : QStringLiteral("#") + id.mid(sep + 1);

        static const QHash<QString, QString> figmaAliases = {
            {QStringLiteral("audio-lines"), QStringLiteral("audio")},
            {QStringLiteral("camera"), QStringLiteral("snapshot")},
            {QStringLiteral("captions"), QStringLiteral("subtitles")},
            {QStringLiteral("check"), QStringLiteral("check-selected")},
            {QStringLiteral("circle-dot"), QStringLiteral("record")},
            {QStringLiteral("cone"), QStringLiteral("vlc")},
            {QStringLiteral("fast-forward"), QStringLiteral("forward-10-sec")},
            {QStringLiteral("film"), QStringLiteral("video")},
            {QStringLiteral("gauge"), QStringLiteral("speed")},
            {QStringLiteral("history"), QStringLiteral("recent")},
            {QStringLiteral("keyboard"), QStringLiteral("hotkeys")},
            {QStringLiteral("list-video"), QStringLiteral("playlist")},
            {QStringLiteral("maximize"), QStringLiteral("maximize")},
            {QStringLiteral("minimize-2"), QStringLiteral("minimize")},
            {QStringLiteral("monitor"), QStringLiteral("interface")},
            {QStringLiteral("panel-left"), QStringLiteral("sidebar-left")},
            {QStringLiteral("picture-in-picture-2"), QStringLiteral("pip")},
            {QStringLiteral("plus"), QStringLiteral("add")},
            {QStringLiteral("rewind"), QStringLiteral("backward-10-sec")},
            {QStringLiteral("shuffle"), QStringLiteral("shuffle-right")},
            {QStringLiteral("skip-back"), QStringLiteral("previous")},
            {QStringLiteral("skip-forward"), QStringLiteral("next")},
            {QStringLiteral("sliders-horizontal"), QStringLiteral("playback-settings")},
            {QStringLiteral("square"), QStringLiteral("stop")},
            {QStringLiteral("volume-1"), QStringLiteral("volume-low")},
            {QStringLiteral("volume-2"), QStringLiteral("volume-high")},
            {QStringLiteral("x"), QStringLiteral("close")},
        };

        const QString figmaName = figmaAliases.value(name, name);
        QFile figmaFile(QStringLiteral(":/neo/assets/figma-icons/%1.svg").arg(figmaName));
        QByteArray svg;
        const bool isFigmaIcon = figmaFile.open(QIODevice::ReadOnly);
        if (isFigmaIcon) {
            svg = figmaFile.readAll();
            svg.replace("#8F8F8F", color.toLatin1());
            svg.replace("#8f8f8f", color.toLatin1());
        } else {
            QFile legacyFile(QStringLiteral(":/neo/icons/%1.svg").arg(name));
            if (legacyFile.open(QIODevice::ReadOnly))
                svg = legacyFile.readAll();
        }
        if (!isFigmaIcon && name != QLatin1String("cone"))
            svg.replace("#ffffff", color.toLatin1());

        const QSize out(requestedSize.width() > 0 ? requestedSize.width() : kDefaultSize,
                        requestedSize.height() > 0 ? requestedSize.height() : kDefaultSize);
        QImage image(out, QImage::Format_ARGB32_Premultiplied);
        image.fill(Qt::transparent);
        QSvgRenderer renderer(svg);
        if (renderer.isValid()) {
            QPainter painter(&image);
            painter.setRenderHint(QPainter::Antialiasing);
            renderer.render(&painter);
        }
        if (size)
            *size = out;
        return image;
    }
};
