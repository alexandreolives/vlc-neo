#include "vlc_tasks.hpp"

#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTimer>

VlcTasks::VlcTasks(QObject *parent) : QObject(parent)
{
    connect(&m_process, &QProcess::readyReadStandardError, this, [this] {
        const QString chunk = QString::fromLocal8Bit(m_process.readAllStandardError());
        m_lastError += chunk;
        if (m_lastError.size() > 4096)
            m_lastError.remove(0, m_lastError.size() - 4096);
    });
    connect(&m_process, &QProcess::readyReadStandardOutput, this, [this] {
        m_process.readAllStandardOutput();
    });
    connect(&m_process, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), this,
            [this](int exitCode, QProcess::ExitStatus exitStatus) {
        if (m_stopping) {
            setStatus(tr("Operation stopped"));
        } else if (exitStatus == QProcess::NormalExit && exitCode == 0) {
            if (m_mode == Mode::Convert && QFileInfo(m_outputPath).isFile()
                && QFileInfo(m_outputPath).size() > 0)
                setStatus(tr("Conversion complete: %1").arg(m_outputPath));
            else if (m_mode == Mode::Stream)
                setStatus(tr("%1 stream ended").arg(m_streamProtocol.toUpper()));
            else
                setStatus(tr("VLC finished without creating the output file"));
        } else {
            QString message = tr("VLC operation failed");
            const QString detail = m_lastError.trimmed();
            if (!detail.isEmpty())
                message += QStringLiteral(": ") + detail.right(700);
            setStatus(message);
        }
        // A stopped or failed conversion must not leave a partial file that
        // would block a retry at the same destination.
        if (m_mode == Mode::Convert && (m_stopping
            || exitStatus != QProcess::NormalExit || exitCode != 0))
            QFile::remove(m_outputPath);
        m_mode = Mode::None;
        m_outputPath.clear();
        m_streamProtocol.clear();
        m_stopping = false;
        m_lastError.clear();
        emit changed();
    });
    connect(&m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            m_mode = Mode::None;
            m_outputPath.clear();
            m_streamProtocol.clear();
            setStatus(tr("Could not start VLC. Install VLC or check PATH."));
        }
    });
}

VlcTasks::~VlcTasks()
{
    if (busy()) {
        m_stopping = true;
        m_process.terminate();
        if (!m_process.waitForFinished(2000)) {
            m_process.kill();
            m_process.waitForFinished(2000);
        }
    }
}

bool VlcTasks::busy() const
{
    return m_process.state() != QProcess::NotRunning;
}

QString VlcTasks::quoteSout(const QString &value)
{
    QString escaped = value;
    escaped.replace(QLatin1Char('\\'), QStringLiteral("\\\\"));
    escaped.replace(QLatin1Char('\''), QStringLiteral("\\'"));
    return QStringLiteral("'") + escaped + QLatin1Char('\'');
}

bool VlcTasks::convert(const QUrl &source, const QUrl &destination, const QString &format,
                       int videoBitrateKbps, int audioBitrateKbps, bool burnSubtitles,
                       const QUrl &subtitleFile, int subtitleTrackId)
{
    const QString path = destination.toLocalFile();
    if (!destination.isLocalFile() || path.isEmpty()) {
        setStatus(tr("Choose a local output file"));
        return false;
    }
    const QString type = format.trimmed().toLower();
    const QString extension = QFileInfo(path).suffix().toLower();
    if (type != QLatin1String("mp4") && type != QLatin1String("mp3") && type != QLatin1String("webm")) {
        setStatus(tr("Choose MP4, MP3 or WebM"));
        return false;
    }
    if (burnSubtitles && type != QLatin1String("mp4")) {
        setStatus(tr("Subtitles can only be burned into MP4 video"));
        return false;
    }
    if (extension != type) {
        setStatus(tr("The output filename must end in .%1").arg(type));
        return false;
    }
    const QFileInfo output(path);
    if (!output.dir().exists()) {
        setStatus(tr("The output folder does not exist"));
        return false;
    }
    if (output.exists()) {
        setStatus(tr("The output file already exists"));
        return false;
    }
    videoBitrateKbps = qBound(250, videoBitrateKbps, 20000);
    audioBitrateKbps = qBound(64, audioBitrateKbps, 512);

    QString transcode;
    QString mux;
    if (type == QLatin1String("mp3")) {
        transcode = QStringLiteral("vcodec=none,acodec=mp3,ab=%1,channels=2,samplerate=44100")
                        .arg(audioBitrateKbps);
        mux = QStringLiteral("raw");
    } else if (type == QLatin1String("webm")) {
        transcode = QStringLiteral("vcodec=VP80,vb=%1,acodec=vorb,ab=%2")
                        .arg(videoBitrateKbps).arg(audioBitrateKbps);
        mux = QStringLiteral("webm");
    } else {
        transcode = QStringLiteral("vcodec=h264,vb=%1,acodec=mp4a,ab=%2%3")
                        .arg(videoBitrateKbps).arg(audioBitrateKbps)
                        .arg(burnSubtitles ? QStringLiteral(",soverlay") : QString());
        mux = QStringLiteral("mp4");
    }
    const QString sout = QStringLiteral("#transcode{%1}:std{access=file,mux=%2,dst=%3}")
                             .arg(transcode, mux, quoteSout(path));
    QString subtitlePath;
    int selectedSubtitleTrackId = -1;
    if (burnSubtitles) {
        const QFileInfo subtitleInfo(subtitleFile.toLocalFile());
        if (subtitleFile.isLocalFile() && subtitleInfo.isFile())
            subtitlePath = subtitleInfo.absoluteFilePath();
        else if (subtitleTrackId >= 0)
            selectedSubtitleTrackId = subtitleTrackId;
        else {
            setStatus(tr("Select a subtitle track before converting"));
            return false;
        }
    }
    return start(source, sout, Mode::Convert, path, {}, subtitlePath,
                 selectedSubtitleTrackId, false);
}

bool VlcTasks::streamUdp(const QUrl &source, const QString &host, int port,
                         int videoBitrateKbps, int audioBitrateKbps)
{
    return streamTo(source, QStringLiteral("udp"), host, port,
                    videoBitrateKbps, audioBitrateKbps);
}

bool VlcTasks::streamTo(const QUrl &source, const QString &protocol,
                        const QString &host, int port,
                        int videoBitrateKbps, int audioBitrateKbps,
                        bool includeSubtitles, const QUrl &subtitleFile, int subtitleTrackId)
{
    static const QRegularExpression validHost(
        QStringLiteral("^(?:[A-Za-z0-9](?:[A-Za-z0-9.-]{0,251}[A-Za-z0-9])?|\\[[0-9A-Fa-f:]+\\])$"));
    const QString type = protocol.trimmed().toLower();
    if (type != QLatin1String("udp") && type != QLatin1String("rtp")
        && type != QLatin1String("http")) {
        setStatus(tr("Choose UDP, RTP or HTTP streaming"));
        return false;
    }
    const QString address = host.trimmed();
    if (!validHost.match(address).hasMatch() || port < 1024 || port > 65535) {
        setStatus(tr("Enter a valid host and a port from 1024 to 65535"));
        return false;
    }
    videoBitrateKbps = qBound(250, videoBitrateKbps, 20000);
    audioBitrateKbps = qBound(64, audioBitrateKbps, 512);
    QString subtitlePath;
    QString transcode = QStringLiteral("#transcode{vcodec=h264,vb=%1,acodec=mp4a,ab=%2")
                            .arg(videoBitrateKbps).arg(audioBitrateKbps);
    const QFileInfo subtitleInfo(subtitleFile.toLocalFile());
    const bool hasSubtitleFile = includeSubtitles && subtitleFile.isLocalFile() && subtitleInfo.isFile();
    const bool hasSubtitleTrack = includeSubtitles && subtitleTrackId >= 0;
    if (hasSubtitleFile || hasSubtitleTrack) {
        transcode += QStringLiteral(",scodec=dvbs");
    }
    if (hasSubtitleFile)
        subtitlePath = subtitleFile.toLocalFile();
    transcode += QLatin1Char('}');
    QString sout;
    if (type == QLatin1String("rtp")) {
        sout = transcode + QStringLiteral(":rtp{dst=%1,port=%2,mux=ts}").arg(address).arg(port);
    } else {
        const QString access = type == QLatin1String("http") ? QStringLiteral("http")
                                                               : QStringLiteral("udp");
        const QString destination = type == QLatin1String("http")
                ? QStringLiteral("%1:%2/stream.ts").arg(address).arg(port)
                : QStringLiteral("%1:%2").arg(address).arg(port);
        sout = transcode + QStringLiteral(":std{access=%1,mux=ts,dst=%2}")
                              .arg(access, destination);
    }
    return start(source, sout, Mode::Stream, {}, type, subtitlePath,
                 hasSubtitleFile ? -1 : (hasSubtitleTrack ? subtitleTrackId : -1));
}

bool VlcTasks::start(const QUrl &source, const QString &sout, Mode mode,
                     const QString &outputPath, const QString &streamProtocol,
                     const QString &subtitleFile, int subtitleTrackId,
                     bool includeAllSubtitleTracks, bool disableSubtitleAutodetect)
{
    if (busy()) {
        setStatus(tr("Another VLC operation is already running"));
        return false;
    }
    if (!source.isValid() || source.isEmpty()
        || (source.isLocalFile() && !QFileInfo::exists(source.toLocalFile()))) {
        setStatus(tr("Choose an existing media file first"));
        return false;
    }
    QString executable = QStandardPaths::findExecutable(QStringLiteral("vlc"));
    if (executable.isEmpty())
        executable = QCoreApplication::applicationFilePath();
    if (executable.isEmpty()) {
        setStatus(tr("Could not find VLC"));
        return false;
    }

    m_mode = mode;
    m_outputPath = outputPath;
    m_streamProtocol = streamProtocol;
    m_lastError.clear();
    m_stopping = false;
    setStatus(mode == Mode::Convert ? tr("Starting conversion in VLC…")
                                    : tr("Starting %1 stream in VLC…").arg(streamProtocol.toUpper()));
    QStringList args = {QStringLiteral("--intf=dummy"), QStringLiteral("--ignore-config"),
                        QStringLiteral("--no-one-instance"), QStringLiteral("--no-video-title-show"),
                        QStringLiteral("--play-and-exit")};
    if (disableSubtitleAutodetect)
        args.append(QStringLiteral("--no-sub-autodetect-file"));
    if (!subtitleFile.isEmpty()) {
        if (includeAllSubtitleTracks)
            args.append(QStringLiteral("--sout-all"));
        args.append(QStringLiteral("--sub-file=") + subtitleFile);
    } else if (subtitleTrackId >= 0) {
        if (includeAllSubtitleTracks)
            args.append(QStringLiteral("--sout-all"));
        args.append(QStringLiteral("--sub-track-id=%1").arg(subtitleTrackId));
    }
    args << QStringLiteral("--sout=") + sout
         << source.toString(QUrl::FullyEncoded)
         << QStringLiteral("vlc://quit");
    m_process.start(executable, args, QIODevice::ReadOnly);
    emit changed();
    return true;
}

void VlcTasks::stop()
{
    if (!busy())
        return;
    m_stopping = true;
    setStatus(tr("Stopping VLC operation…"));
    m_process.terminate();
    QTimer::singleShot(2000, this, [this] {
        if (busy())
            m_process.kill();
    });
}

void VlcTasks::setStatus(const QString &message)
{
    m_status = message;
    emit changed();
}
