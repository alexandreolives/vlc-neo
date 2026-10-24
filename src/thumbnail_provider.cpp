#include "thumbnail_provider.hpp"
#include "bounded_image_cache.hpp"

#include <QElapsedTimer>
#include <QDir>
#include <QFileInfo>
#include <QFutureWatcher>
#include <QImage>
#include <QPainter>
#include <QProcess>
#include <QProcessEnvironment>
#include <QQuickTextureFactory>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QThreadPool>
#include <QUrlQuery>
#include <QtEndian>
#include <QtConcurrent/QtConcurrentRun>
#include <algorithm>
#include <atomic>
#include <limits>

namespace {

// Bound the complete set of admitted responses, including work waiting in the
// pool. A larger cap than the worker count lets a normal burst of effect and
// timeline requests drain, while overload is rejected instead of retained.
constexpr int kMaxOutstandingResponses = 64;
constexpr int kMaxWorkers = 2;
constexpr int kOutputWidth = 480;
constexpr int kOutputHeight = 270;
constexpr int kWaveformWidth = 768;
constexpr int kWaveformHeight = 28;
constexpr int kWaveformSampleRate = 8000;

QString cacheKey(const QString &path, qint64 timeMs, qint64 durationSeconds,
                 const QString &effect, const QSize &size)
{
    const QFileInfo file(path);
    return QStringLiteral("%1\n%2\n%3\n%4")
        .arg(file.canonicalFilePath(), QString::number(file.size()),
             QString::number(file.lastModified().toMSecsSinceEpoch()),
             durationSeconds > 0 ? QStringLiteral("wave:%1").arg(durationSeconds)
             : !effect.isEmpty() ? QStringLiteral("effect:%1:%2").arg(effect).arg(timeMs)
                                 : QStringLiteral("frame:%1:%2x%3").arg(timeMs).arg(size.width())
                                       .arg(size.height()));
}

QString mediaPath(const QString &id)
{
    const qsizetype queryStart = id.indexOf(QLatin1Char('?'));
    if (queryStart < 0)
        return {};
    const QUrlQuery query(id.mid(queryStart + 1));
    return query.queryItemValue(QStringLiteral("path"), QUrl::FullyDecoded);
}

qint64 timeMilliseconds(const QString &id)
{
    const qsizetype queryStart = id.indexOf(QLatin1Char('?'));
    if (queryStart < 0)
        return -1;
    const QUrlQuery query(id.mid(queryStart + 1));
    bool ok = false;
    if (query.hasQueryItem(QStringLiteral("tms"))) {
        const qint64 milliseconds = query.queryItemValue(QStringLiteral("tms")).toLongLong(&ok);
        return ok && milliseconds >= 0 ? milliseconds : -1;
    }
    const qint64 seconds = query.queryItemValue(QStringLiteral("t")).toLongLong(&ok);
    return ok && seconds >= 0 && seconds <= std::numeric_limits<qint64>::max() / 1000
        ? seconds * 1000 : -1;
}

qint64 waveformDuration(const QString &id)
{
    const qsizetype queryStart = id.indexOf(QLatin1Char('?'));
    if (queryStart < 0)
        return 0;
    bool ok = false;
    const qint64 duration = QUrlQuery(id.mid(queryStart + 1))
                                .queryItemValue(QStringLiteral("duration")).toLongLong(&ok);
    return ok && duration > 0 ? qMin<qint64>(duration, 24 * 60 * 60) : 0;
}

QString videoEffect(const QString &id)
{
    const qsizetype queryStart = id.indexOf(QLatin1Char('?'));
    if (queryStart < 0)
        return {};
    const QString effect = QUrlQuery(id.mid(queryStart + 1))
                               .queryItemValue(QStringLiteral("effect"));
    static const QStringList supported = {QStringLiteral("preview-set"), QStringLiteral("sepia"), QStringLiteral("invert"),
                                          QStringLiteral("posterize"), QStringLiteral("oldmovie"),
                                          QStringLiteral("gaussianblur"), QStringLiteral("sharpen"),
                                          QStringLiteral("vhs"), QStringLiteral("grain")};
    return supported.contains(effect) ? effect : QString();
}

QImage applyVideoEffectPreview(QImage image, const QString &effect)
{
    if (effect.isEmpty())
        return image;

    if (effect == QLatin1String("gaussianblur")) {
        const QSize blurredSize(qMax(1, image.width() / 5), qMax(1, image.height() / 5));
        return image.scaled(blurredSize, Qt::IgnoreAspectRatio, Qt::SmoothTransformation)
            .scaled(image.size(), Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
    }

    if (effect == QLatin1String("sharpen")) {
        image = image.convertToFormat(QImage::Format_ARGB32);
        const QImage source = image.copy();
        for (int y = 1; y + 1 < image.height(); ++y) {
            auto *line = reinterpret_cast<QRgb *>(image.scanLine(y));
            const auto *above = reinterpret_cast<const QRgb *>(source.constScanLine(y - 1));
            const auto *center = reinterpret_cast<const QRgb *>(source.constScanLine(y));
            const auto *below = reinterpret_cast<const QRgb *>(source.constScanLine(y + 1));
            for (int x = 1; x + 1 < image.width(); ++x) {
                const QRgb pixel = center[x];
                const int red = qBound(0, 5 * qRed(pixel) - qRed(center[x - 1]) - qRed(center[x + 1])
                                           - qRed(above[x]) - qRed(below[x]), 255);
                const int green = qBound(0, 5 * qGreen(pixel) - qGreen(center[x - 1]) - qGreen(center[x + 1])
                                             - qGreen(above[x]) - qGreen(below[x]), 255);
                const int blue = qBound(0, 5 * qBlue(pixel) - qBlue(center[x - 1]) - qBlue(center[x + 1])
                                            - qBlue(above[x]) - qBlue(below[x]), 255);
                line[x] = qRgba(red, green, blue, qAlpha(pixel));
            }
        }
        return image;
    }

    image = image.convertToFormat(QImage::Format_ARGB32);
    const QImage source = image.copy();
    for (int y = 0; y < image.height(); ++y) {
        auto *line = reinterpret_cast<QRgb *>(image.scanLine(y));
        for (int x = 0; x < image.width(); ++x) {
            const QRgb pixel = line[x];
            int red = qRed(pixel);
            int green = qGreen(pixel);
            int blue = qBlue(pixel);

            if (effect == QLatin1String("sepia") || effect == QLatin1String("oldmovie")) {
                const int sepiaRed = qMin(255, (393 * red + 769 * green + 189 * blue) / 1000);
                const int sepiaGreen = qMin(255, (349 * red + 686 * green + 168 * blue) / 1000);
                const int sepiaBlue = qMin(255, (272 * red + 534 * green + 131 * blue) / 1000);
                red = sepiaRed;
                green = sepiaGreen;
                blue = sepiaBlue;
                if (effect == QLatin1String("oldmovie")) {
                    const int grain = ((x * 13 + y * 7) % 9) - 4;
                    red = qBound(0, red + grain, 255);
                    green = qBound(0, green + grain, 255);
                    blue = qBound(0, blue + grain, 255);
                    if ((x % 83 == 11) && (y % 17 < 10))
                        red = green = blue = qMin(255, red + 38);
                }
            } else if (effect == QLatin1String("invert")) {
                red = 255 - red;
                green = 255 - green;
                blue = 255 - blue;
            } else if (effect == QLatin1String("posterize")) {
                red = (red / 64) * 85;
                green = (green / 64) * 85;
                blue = (blue / 64) * 85;
            } else if (effect == QLatin1String("grain")) {
                const int noise = ((x * 17 + y * 31 + x * y * 7) % 19) - 9;
                red = qBound(0, red + noise, 255);
                green = qBound(0, green + noise, 255);
                blue = qBound(0, blue + noise, 255);
            } else if (effect == QLatin1String("vhs")) {
                const int shiftedRed = qRed(source.pixel(qMin(x + 2, source.width() - 1), y));
                const int shiftedBlue = qBlue(source.pixel(qMax(0, x - 2), y));
                red = shiftedRed;
                blue = shiftedBlue;
                if (y % 3 == 0) {
                    red = red * 3 / 4;
                    green = green * 3 / 4;
                    blue = blue * 3 / 4;
                }
                if ((y % 41 == 5) && x > image.width() / 3 && x < image.width() * 2 / 3)
                    red = green = blue = 235;
            }
            line[x] = qRgba(red, green, blue, qAlpha(pixel));
        }
    }
    return image;
}

QImage makeVideoEffectPreviewSet(const QImage &source)
{
    static const QStringList effects = {QString(), QStringLiteral("sepia"), QStringLiteral("invert"),
                                        QStringLiteral("posterize"), QStringLiteral("oldmovie"),
                                        QStringLiteral("gaussianblur"), QStringLiteral("sharpen"),
                                        QStringLiteral("vhs"), QStringLiteral("grain")};
    QImage previews(source.width() * effects.size(), source.height(), QImage::Format_ARGB32_Premultiplied);
    previews.fill(Qt::transparent);
    QPainter painter(&previews);
    for (qsizetype i = 0; i < effects.size(); ++i)
        painter.drawImage(QPoint(i * source.width(), 0), applyVideoEffectPreview(source, effects.at(i)));
    return previews;
}

} // namespace

class ThumbnailProvider::Service
{
public:
    Service()
    {
        m_pool.setMaxThreadCount(kMaxWorkers);
        m_pool.setExpiryTimeout(10000);
        m_ffmpeg = QStandardPaths::findExecutable(QStringLiteral("ffmpeg"));
        m_vlc = QStandardPaths::findExecutable(QStringLiteral("cvlc"));
        if (m_vlc.isEmpty())
            m_vlc = QStandardPaths::findExecutable(QStringLiteral("vlc"));
    }

    QImage image(const QString &path, qint64 timeMs, qint64 durationSeconds, const QSize &requestedSize,
                 const QString &effect, const std::shared_ptr<std::atomic<bool>> &cancelled)
    {
        if (m_stopping.load(std::memory_order_relaxed) || cancelled->load(std::memory_order_relaxed))
            return {};
        const bool waveform = durationSeconds > 0;
        if ((waveform && m_vlc.isEmpty()) || (!waveform && m_vlc.isEmpty() && m_ffmpeg.isEmpty())
            || (!waveform && timeMs < 0))
            return {};

        const QFileInfo info(path);
        if (!info.isFile() || !info.isReadable())
            return {};

        QSize outputSize(kOutputWidth, kOutputHeight);
        if (durationSeconds <= 0 && effect.isEmpty() && requestedSize.isValid()
            && requestedSize.width() > 0 && requestedSize.height() > 0) {
            outputSize = requestedSize;
            outputSize.scale(kOutputWidth, kOutputHeight, Qt::KeepAspectRatio);
            outputSize.setWidth(qMax(1, outputSize.width()));
            outputSize.setHeight(qMax(1, outputSize.height()));
        }
        const QString key = cacheKey(path, timeMs, durationSeconds, effect, outputSize);
        {
            QMutexLocker locker(&m_cacheMutex);
            if (const QImage *cached = m_cache.object(key))
                return *cached;
        }

        if (waveform)
            return makeWaveform(info.absoluteFilePath(), key, durationSeconds, cancelled);

        const auto finishFrame = [&](QImage decoded) {
            if (decoded.isNull() || decoded.width() > kOutputWidth || decoded.height() > kOutputHeight)
                return QImage();
            if (effect == QLatin1String("preview-set"))
                decoded = makeVideoEffectPreviewSet(decoded);
            else
                decoded = applyVideoEffectPreview(std::move(decoded), effect);
            if (cancelled->load(std::memory_order_relaxed))
                return QImage();
            QMutexLocker locker(&m_cacheMutex);
            m_cache.insert(key, decoded);
            return decoded;
        };

        // Timeline hover can request several frames in quick succession. FFmpeg's
        // image pipe avoids VLC's scene-filter startup and temporary-file overhead;
        // VLC remains the fallback for systems without FFmpeg or unsupported media.
        if (!m_ffmpeg.isEmpty()) {
            QProcess process;
            QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
            environment.remove(QStringLiteral("VLC_PLUGIN_PATH"));
            process.setProcessEnvironment(environment);
            process.setProgram(m_ffmpeg);
            process.setArguments({QStringLiteral("-hide_banner"), QStringLiteral("-loglevel"),
                                  QStringLiteral("error"), QStringLiteral("-ss"),
                                  QString::number(timeMs / 1000.0, 'f', 3),
                                  QStringLiteral("-i"), info.absoluteFilePath(), QStringLiteral("-frames:v"),
                                  QStringLiteral("1"), QStringLiteral("-vf"),
                                  QStringLiteral("scale=%1:%2:force_original_aspect_ratio=decrease")
                                      .arg(outputSize.width()).arg(outputSize.height()),
                                  QStringLiteral("-f"), QStringLiteral("image2pipe"),
                                  QStringLiteral("-vcodec"), QStringLiteral("mjpeg"), QStringLiteral("pipe:1")});
            process.setProcessChannelMode(QProcess::SeparateChannels);
            process.start();
            if (process.waitForStarted(1500)) {
                QByteArray encoded;
                QElapsedTimer frameTimer;
                frameTimer.start();
                while (process.state() != QProcess::NotRunning && frameTimer.elapsed() < 5000
                       && !m_stopping.load(std::memory_order_relaxed)
                       && !cancelled->load(std::memory_order_relaxed)) {
                    process.waitForReadyRead(80);
                    encoded += process.readAllStandardOutput();
                    process.readAllStandardError();
                    if (encoded.size() > 2 * 1024 * 1024)
                        break;
                }
                encoded += process.readAllStandardOutput();
                process.readAllStandardError();
                if (m_stopping.load(std::memory_order_relaxed) || cancelled->load(std::memory_order_relaxed)
                    || encoded.size() > 2 * 1024 * 1024) {
                    process.kill();
                    process.waitForFinished(1000);
                    return {};
                }
                if (process.state() != QProcess::NotRunning) {
                    process.kill();
                    process.waitForFinished(1000);
                } else if (process.exitStatus() == QProcess::NormalExit && process.exitCode() == 0) {
                    const QImage decoded = QImage::fromData(encoded, "JPEG");
                    if (!decoded.isNull())
                        return finishFrame(decoded);
                }
            }
        }

        QTemporaryDir outputDir;
        if (!outputDir.isValid())
            return {};

        QProcess process;
        QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
        environment.remove(QStringLiteral("VLC_PLUGIN_PATH"));
        process.setProcessEnvironment(environment);
        process.setProgram(m_vlc);
        process.setArguments({QStringLiteral("--no-one-instance"), QStringLiteral("--intf=dummy"),
                              QStringLiteral("--quiet"), QStringLiteral("--no-audio"),
                              QStringLiteral("--no-video-title-show"), QStringLiteral("--play-and-exit"),
                              QStringLiteral("--vout=dummy"), QStringLiteral("--video-filter=scene"),
                              // The caller only needs one representative frame. Capturing the
                              // first few frames avoids scene-ratio's 30-frame delay and keeps
                              // startup and temporary image writes short.
                              QStringLiteral("--scene-ratio=1"),
                              QStringLiteral("--scene-width=%1").arg(outputSize.width()),
                              QStringLiteral("--scene-height=%1").arg(outputSize.height()),
                              QStringLiteral("--scene-prefix=frame"),
                              QStringLiteral("--scene-path=%1").arg(outputDir.path()),
                              QStringLiteral("--scene-format=jpg"),
                              QStringLiteral("--start-time=%1").arg(QString::number(timeMs / 1000.0, 'f', 3)),
                              QStringLiteral("--stop-time=%1").arg(QString::number((timeMs + 200) / 1000.0, 'f', 3)),
                              QStringLiteral("--run-time=2"), info.absoluteFilePath()});
        process.setProcessChannelMode(QProcess::SeparateChannels);
        process.start();
        if (!process.waitForStarted(1500))
            return {};
        QElapsedTimer frameTimer;
        frameTimer.start();
        while (process.state() != QProcess::NotRunning && frameTimer.elapsed() < 8000
               && !m_stopping.load(std::memory_order_relaxed)
               && !cancelled->load(std::memory_order_relaxed))
            process.waitForFinished(100);
        if (m_stopping.load(std::memory_order_relaxed) || cancelled->load(std::memory_order_relaxed)) {
            process.kill();
            process.waitForFinished(1000);
            return {};
        }
        if (process.state() != QProcess::NotRunning) {
            process.kill();
            process.waitForFinished(1000);
            return {};
        }

        if (process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0)
            return {};

        const QStringList frames = QDir(outputDir.path()).entryList({QStringLiteral("frame*.jpg")},
                                                                    QDir::Files, QDir::Name);
        if (frames.isEmpty())
            return {};
        QFile frameFile(QDir(outputDir.path()).filePath(frames.constFirst()));
        if (!frameFile.open(QIODevice::ReadOnly) || frameFile.size() <= 0
            || frameFile.size() > 2 * 1024 * 1024)
            return {};
        const QByteArray encoded = frameFile.readAll();
        QImage decoded = QImage::fromData(encoded, "JPEG");
        return finishFrame(std::move(decoded));
    }

    QImage makeWaveform(const QString &path, const QString &key, qint64 durationSeconds,
                        const std::shared_ptr<std::atomic<bool>> &cancelled)
    {
        constexpr int kTimeoutMs = 20000;
        if (cancelled->load(std::memory_order_relaxed))
            return {};
        const int binCount = kWaveformWidth;
        const qint64 expectedSamples = durationSeconds * kWaveformSampleRate;
        if (expectedSamples <= 0)
            return {};

        QProcess process;
        QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
        environment.remove(QStringLiteral("VLC_PLUGIN_PATH"));
        process.setProcessEnvironment(environment);
        process.setProcessChannelMode(QProcess::SeparateChannels);
        process.setProgram(m_vlc);
        process.setArguments({QStringLiteral("--no-one-instance"), QStringLiteral("--intf=dummy"),
                              QStringLiteral("--quiet"), QStringLiteral("--play-and-exit"),
                              QStringLiteral("--no-video"),
                              QStringLiteral("--sout=#transcode{vcodec=none,acodec=s16l,channels=1,samplerate=8000}:std{access=file,mux=raw,dst=-}"),
                              QStringLiteral("--stop-time=%1").arg(durationSeconds), path});
        process.start();
        if (!process.waitForStarted(1500))
            return {};

        QVector<quint16> peaks(binCount, 0);
        qint64 sampleIndex = 0;
        char danglingByte = 0;
        bool hasDanglingByte = false;
        QElapsedTimer elapsed;
        elapsed.start();
        while (process.state() != QProcess::NotRunning && elapsed.elapsed() < kTimeoutMs
               && !m_stopping.load(std::memory_order_relaxed)
               && !cancelled->load(std::memory_order_relaxed)) {
            process.waitForReadyRead(100);
            QByteArray chunk = process.readAllStandardOutput();
            process.readAllStandardError();
            if (hasDanglingByte && !chunk.isEmpty()) {
                chunk.prepend(danglingByte);
                hasDanglingByte = false;
            }
            if (chunk.size() % 2) {
                danglingByte = chunk.back();
                hasDanglingByte = true;
                chunk.chop(1);
            }
            const auto *samples = reinterpret_cast<const uchar *>(chunk.constData());
            for (qsizetype offset = 0; offset + 1 < chunk.size(); offset += 2, ++sampleIndex) {
                const qint16 sample = qFromLittleEndian<qint16>(samples + offset);
                const quint16 amplitude = quint16(qAbs(int(sample)));
                const int bin = int(qMin<qint64>(binCount - 1, sampleIndex * binCount / expectedSamples));
                peaks[bin] = qMax(peaks[bin], amplitude);
            }
        }
        if (m_stopping.load(std::memory_order_relaxed) || cancelled->load(std::memory_order_relaxed)) {
            process.kill();
            process.waitForFinished(1000);
            return {};
        }
        if (process.state() != QProcess::NotRunning) {
            process.kill();
            process.waitForFinished(500);
            return {};
        }
        process.readAllStandardError();
        if (process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0 || sampleIndex < binCount)
            return {};

        QImage waveform(kWaveformWidth, kWaveformHeight, QImage::Format_ARGB32_Premultiplied);
        waveform.fill(Qt::transparent);
        QPainter painter(&waveform);
        painter.setRenderHint(QPainter::Antialiasing);
        painter.setPen(QPen(QColor(160, 150, 136, 175), 0.5, Qt::SolidLine, Qt::RoundCap));
        const qreal center = kWaveformHeight / 2.0;
        QVector<quint16> sortedPeaks = peaks;
        std::sort(sortedPeaks.begin(), sortedPeaks.end());
        const int normalizationIndex = (sortedPeaks.size() * 95) / 100;
        const quint16 peakScale = qMax<quint16>(1, sortedPeaks.at(normalizationIndex));
        for (int x = 0; x < binCount; ++x) {
            const qreal amplitude = qMax<qreal>(0.7, qreal(peaks.at(x)) / peakScale * (center - 1));
            painter.drawLine(QPointF(x + 0.5, center - amplitude), QPointF(x + 0.5, center + amplitude));
        }
        painter.end();
        if (cancelled->load(std::memory_order_relaxed))
            return {};
        {
            QMutexLocker locker(&m_cacheMutex);
            m_cache.insert(key, waveform);
        }
        return waveform;
    }

    QThreadPool *pool()
    {
        return &m_pool;
    }
    bool reserveResponse()
    {
        if (m_stopping.load(std::memory_order_relaxed))
            return false;
        int current = m_responses.load(std::memory_order_relaxed);
        while (current < kMaxOutstandingResponses && !m_stopping.load(std::memory_order_relaxed)) {
            if (m_responses.compare_exchange_weak(current, current + 1, std::memory_order_relaxed))
                return true;
        }
        return false;
    }
    bool reserveJob()
    {
        if (m_stopping.load(std::memory_order_relaxed))
            return false;
        int current = m_jobs.load(std::memory_order_relaxed);
        while (current < kMaxOutstandingResponses && !m_stopping.load(std::memory_order_relaxed)) {
            if (m_jobs.compare_exchange_weak(current, current + 1, std::memory_order_relaxed))
                return true;
        }
        return false;
    }
    void releaseResponse() { m_responses.fetch_sub(1, std::memory_order_relaxed); }
    void releaseJob() { m_jobs.fetch_sub(1, std::memory_order_relaxed); }
    bool stopping() const { return m_stopping.load(std::memory_order_relaxed); }
    void waitForJobs()
    {
        m_stopping.store(true, std::memory_order_relaxed);
        pool()->waitForDone();
    }

private:
    BoundedImageCache m_cache;
    QMutex m_cacheMutex;
    QString m_ffmpeg;
    QString m_vlc;
    QThreadPool m_pool;
    std::atomic<int> m_responses{0};
    std::atomic<int> m_jobs{0};
    std::atomic<bool> m_stopping{false};
};

namespace {

class ThumbnailResponse final : public QQuickImageResponse
{
public:
    ThumbnailResponse(std::shared_ptr<ThumbnailProvider::Service> service,
                      const QString &path, qint64 timeMs, qint64 durationSeconds,
                      const QSize &requestedSize, const QString &effect)
        : m_service(std::move(service)), m_path(path), m_timeMs(timeMs),
          m_durationSeconds(durationSeconds), m_requestedSize(requestedSize), m_effect(effect)
    {
        connect(&m_watcher, &QFutureWatcher<QImage>::finished, this, [this] {
            if (!m_cancelled.load(std::memory_order_relaxed)) {
                m_image = m_watcher.result();
                emit finished();
            }
        });

        if (!m_service->reserveResponse()) {
            // QQuickImageResponse consumers connect to finished after this
            // factory returns, so queue the failure notification.
            QMetaObject::invokeMethod(this, [this] { emit finished(); }, Qt::QueuedConnection);
            return;
        }
        m_reserved = true;
        if (!m_service->reserveJob()) {
            m_service->releaseResponse();
            m_reserved = false;
            QMetaObject::invokeMethod(this, [this] { emit finished(); }, Qt::QueuedConnection);
            return;
        }
        m_jobReserved = true;
        start();
    }

    ~ThumbnailResponse() override
    {
        if (m_reserved)
            m_service->releaseResponse();
    }

    void start()
    {
        if (m_cancelled.load(std::memory_order_relaxed)) {
            if (m_jobReserved) {
                m_service->releaseJob();
                m_jobReserved = false;
            }
            QMetaObject::invokeMethod(this, [this] { emit finished(); }, Qt::QueuedConnection);
            return;
        }

        const auto serviceCopy = m_service;
        m_watcher.setFuture(QtConcurrent::run(serviceCopy->pool(), [serviceCopy, path = m_path,
                                                                    timeMs = m_timeMs,
                                                                    durationSeconds = m_durationSeconds,
                                                                    requestedSize = m_requestedSize,
                                                                    effect = m_effect,
                                                                    cancelSignal = m_cancelSignal] {
            const QImage image = serviceCopy->image(path, timeMs, durationSeconds, requestedSize,
                                                    effect, cancelSignal);
            serviceCopy->releaseJob();
            return image;
        }));
        m_jobReserved = false;
    }

    QQuickTextureFactory *textureFactory() const override
    {
        return m_image.isNull() ? nullptr : QQuickTextureFactory::textureFactoryForImage(m_image);
    }

    QString errorString() const override
    {
        return m_image.isNull() ? QStringLiteral("Thumbnail unavailable") : QString();
    }

    void cancel() override
    {
        m_cancelled.store(true, std::memory_order_relaxed);
        m_cancelSignal->store(true, std::memory_order_relaxed);
    }

private:
    std::shared_ptr<ThumbnailProvider::Service> m_service;
    QFutureWatcher<QImage> m_watcher;
    QString m_path;
    qint64 m_timeMs = -1;
    qint64 m_durationSeconds = 0;
    QSize m_requestedSize;
    QString m_effect;
    QImage m_image;
    std::atomic<bool> m_cancelled{false};
    std::shared_ptr<std::atomic<bool>> m_cancelSignal = std::make_shared<std::atomic<bool>>(false);
    bool m_reserved = false;
    bool m_jobReserved = false;
};

} // namespace

ThumbnailProvider::ThumbnailProvider()
    : QQuickAsyncImageProvider(), m_service(std::make_shared<Service>())
{
}

ThumbnailProvider::~ThumbnailProvider()
{
    // The image engine is torn down before QGuiApplication. Finish worker-side
    // decoding while Qt's image plugins and GUI infrastructure are still alive.
    m_service->waitForJobs();
}

void ThumbnailProvider::waitForJobs()
{
    m_service->waitForJobs();
}

QQuickImageResponse *ThumbnailProvider::requestImageResponse(const QString &id, const QSize &requestedSize)
{
    return new ThumbnailResponse(m_service, mediaPath(id), timeMilliseconds(id), waveformDuration(id),
                                 requestedSize, videoEffect(id));
}
