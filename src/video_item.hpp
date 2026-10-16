// QML item that paints the latest frame from FrameStore, letterboxed.
#pragma once

#include <QImage>
#include <QQuickItem>
#include <QSize>

class VideoItem : public QQuickItem
{
    Q_OBJECT
    Q_PROPERTY(bool hasFrame READ hasFrame NOTIFY hasFrameChanged)
    Q_PROPERTY(QSize frameSize READ frameSize NOTIFY frameSizeChanged)
    Q_PROPERTY(bool fill READ fill WRITE setFill NOTIFY fillChanged)

public:
    explicit VideoItem(QQuickItem *parent = nullptr);
    ~VideoItem() override;

    bool hasFrame() const { return m_hasFrame; }
    QSize frameSize() const { return m_frameSize; }
    bool fill() const { return m_fill; }
    void setFill(bool fill);

signals:
    void hasFrameChanged();
    void frameSizeChanged();
    void fillChanged();

protected:
    QSGNode *updatePaintNode(QSGNode *old, UpdatePaintNodeData *) override;
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override
    {
        QQuickItem::geometryChange(newGeometry, oldGeometry);
        update();
    }

private:
    void setFrameInfo(bool hasFrame, QSize size);

    quint64 m_serial = 0;
    QImage m_frame;
    double m_sampleAspect = 1.0;
    bool m_hasFrame = false;
    bool m_fill = false;
    QSize m_frameSize;
};
