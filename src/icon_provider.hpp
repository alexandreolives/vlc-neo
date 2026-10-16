// Renders the bundled monochrome SVG icons in any colour:
//   image://icon/play?#D9822B
#pragma once

#include <QFile>
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

        QFile file(QStringLiteral(":/neo/icons/%1.svg").arg(name));
        QByteArray svg;
        if (file.open(QIODevice::ReadOnly))
            svg = file.readAll();
        if (name != QLatin1String("cone"))
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
