#include "video_item.hpp"
#include "frame_store.hpp"

#include <QQuickWindow>
#include <QSGImageNode>
#include <QSGTexture>

VideoItem::VideoItem(QQuickItem *parent) : QQuickItem(parent)
{
    setFlag(ItemHasContents, true);
    FrameStore::instance().setSink(this);
}

VideoItem::~VideoItem()
{
    FrameStore::instance().setSink(nullptr);
}

void VideoItem::setFill(bool fill)
{
    if (fill == m_fill)
        return;
    m_fill = fill;
    emit fillChanged();
    update();
}

void VideoItem::setFrameInfo(bool hasFrame, QSize size)
{
    // Called on the render thread; bounce property updates to the GUI thread.
    QMetaObject::invokeMethod(this, [this, hasFrame, size] {
        if (hasFrame != m_hasFrame) {
            m_hasFrame = hasFrame;
            emit hasFrameChanged();
        }
        if (size != m_frameSize) {
            m_frameSize = size;
            emit frameSizeChanged();
        }
    }, Qt::QueuedConnection);
}

QSGNode *VideoItem::updatePaintNode(QSGNode *old, UpdatePaintNodeData *)
{
    auto *node = static_cast<QSGImageNode *>(old);

    bool changed = FrameStore::instance().take(m_serial, m_frame, m_sampleAspect, m_frameRate);
    if (m_frame.isNull()) {
        if (changed) {
            setFrameInfo(false, QSize());
            QMetaObject::invokeMethod(this, [this] {
                if (m_propertyFrameRate != 0.0) {
                    m_propertyFrameRate = 0.0;
                    emit frameRateChanged();
                }
            }, Qt::QueuedConnection);
        }
        delete node;
        return nullptr;
    }

    if (!node) {
        node = window()->createImageNode();
        node->setOwnsTexture(true);
        node->setFiltering(QSGTexture::Linear);
        changed = true;
    }

    if (changed) {
        QSGTexture *texture = window()->createTextureFromImage(m_frame);
        node->setTexture(texture);
        const QSize display(qRound(m_frame.width() * m_sampleAspect), m_frame.height());
        setFrameInfo(true, display);
        QMetaObject::invokeMethod(this, [this, rate = m_frameRate] {
            if (!qFuzzyCompare(m_propertyFrameRate, rate)) {
                m_propertyFrameRate = rate;
                emit frameRateChanged();
            }
        }, Qt::QueuedConnection);
    }

    // Fit (letterbox) or fill (crop) the frame inside the item.
    const double frameW = m_frame.width() * m_sampleAspect;
    const double frameH = m_frame.height();
    const double scaleFit = std::min(width() / frameW, height() / frameH);
    const double scaleFill = std::max(width() / frameW, height() / frameH);
    const double scale = m_fill ? scaleFill : scaleFit;
    const double w = frameW * scale;
    const double h = frameH * scale;
    QRectF target((width() - w) / 2.0, (height() - h) / 2.0, w, h);
    node->setRect(target.intersected(boundingRect()));
    if (m_fill) {
        // Map visible region back to source pixels.
        const QRectF visible = target.intersected(boundingRect());
        const double sx = m_frame.width() / w;
        const double sy = m_frame.height() / h;
        node->setSourceRect(QRectF((visible.x() - target.x()) * sx, (visible.y() - target.y()) * sy,
                                   visible.width() * sx, visible.height() * sy));
    } else {
        node->setSourceRect(QRectF(0, 0, m_frame.width(), m_frame.height()));
    }
    return node;
}
