#pragma once

#include <QObject>
#include <QProcess>
#include <QUrl>

class VlcTasks final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(bool streaming READ streaming NOTIFY changed)
    Q_PROPERTY(QString status READ status NOTIFY changed)

public:
    explicit VlcTasks(QObject *parent = nullptr);
    ~VlcTasks() override;

    bool busy() const;
    bool streaming() const { return m_mode == Mode::Stream && busy(); }
    QString status() const { return m_status; }

    Q_INVOKABLE bool convert(const QUrl &source, const QUrl &destination, const QString &format,
                             int videoBitrateKbps = 2000, int audioBitrateKbps = 192);
    Q_INVOKABLE bool streamUdp(const QUrl &source, const QString &host, int port,
                               int videoBitrateKbps = 2000, int audioBitrateKbps = 192);
    Q_INVOKABLE bool streamTo(const QUrl &source, const QString &protocol,
                              const QString &host, int port,
                              int videoBitrateKbps = 2000, int audioBitrateKbps = 192,
                              bool includeSubtitles = true, const QUrl &subtitleFile = {},
                              int subtitleTrackId = -1);
    Q_INVOKABLE void stop();

signals:
    void changed();

private:
    enum class Mode { None, Convert, Stream };
    bool start(const QUrl &source, const QString &sout, Mode mode,
               const QString &outputPath = {}, const QString &streamProtocol = {},
               const QString &subtitleFile = {}, int subtitleTrackId = -1,
               bool includeAllSubtitleTracks = true, bool disableSubtitleAutodetect = false);
    void setStatus(const QString &message);
    static QString quoteSout(const QString &value);

    QProcess m_process;
    Mode m_mode = Mode::None;
    QString m_status;
    QString m_outputPath;
    QString m_streamProtocol;
    QString m_lastError;
    bool m_stopping = false;
};
