// Shared hand-off point between the VLC video thread (vout display) and the
// Qt render thread (VideoItem). Only the newest frame is kept.
#pragma once

#include <QImage>
#include <QMutex>
#include <QObject>
#include <QPointer>
#include <atomic>

class FrameStore
{
public:
    static FrameStore &instance()
    {
        static FrameStore store;
        return store;
    }

    // Called from the VLC vout thread.
    void publish(QImage &&frame, double sampleAspect)
    {
        QPointer<QObject> sink;
        {
            QMutexLocker locker(&m_lock);
            m_frame = std::move(frame);
            m_sampleAspect = sampleAspect > 0.0 ? sampleAspect : 1.0;
            ++m_serial;
            sink = m_sink;
        }
        requestUpdate(sink);
    }

    void clear()
    {
        QPointer<QObject> sink;
        {
            QMutexLocker locker(&m_lock);
            m_frame = QImage();
            ++m_serial;
            sink = m_sink;
        }
        requestUpdate(sink);
    }

    // Called from the render thread. Returns false when nothing changed.
    bool take(quint64 &serial, QImage &frame, double &sampleAspect)
    {
        QMutexLocker locker(&m_lock);
        if (serial == m_serial)
            return false;
        serial = m_serial;
        frame = m_frame; // implicit sharing, cheap
        sampleAspect = m_sampleAspect;
        return true;
    }

    void setSink(QObject *sink)
    {
        QMutexLocker locker(&m_lock);
        m_sink = sink;
    }

    std::atomic<bool> uiActive{false};

private:
    FrameStore() = default;

    static void requestUpdate(const QPointer<QObject> &sink)
    {
        if (sink)
            QMetaObject::invokeMethod(sink.data(), "update", Qt::QueuedConnection);
    }

    QMutex m_lock;
    QImage m_frame;
    double m_sampleAspect = 1.0;
    quint64 m_serial = 0;
    QPointer<QObject> m_sink;
};
