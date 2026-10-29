// Small desktop helpers exposed to QML (clipboard, compositor tricks).
#pragma once

#include <QClipboard>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QObject>
#include <QPoint>
#include <QProcess>
#include <QScreen>
#include <QSize>
#include <QStandardPaths>
#include <QUrl>
#include <QVariantList>
#include <QWindow>

class Platform : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool hyprland READ hyprland CONSTANT)
    Q_PROPERTY(QString applicationVersion READ applicationVersion CONSTANT)
    Q_PROPERTY(QString platformName READ platformName CONSTANT)

public:
    using QObject::QObject;

    ~Platform() override { setPlaybackInhibition(false, false, false); }

    bool hyprland() const { return qEnvironmentVariableIsSet("HYPRLAND_INSTANCE_SIGNATURE"); }
    QString applicationVersion() const { return QCoreApplication::applicationVersion(); }
    QString platformName() const { return QGuiApplication::platformName(); }

    Q_INVOKABLE QString clipboardText() const { return QGuiApplication::clipboard()->text().trimmed(); }

    // Match VLC's inhibition policy: audio keeps the computer awake, while
    // video can also inhibit display idle when the VLC preference allows it.
    Q_INVOKABLE void setPlaybackInhibition(bool playing, bool hasVideo, bool disableScreensaver)
    {
        const QDBusConnection bus = QDBusConnection::sessionBus();
        if (!bus.isConnected())
            return;

        const bool inhibitSuspend = playing;
        const bool inhibitDisplay = playing && hasVideo && disableScreensaver;
        const uint gnomeFlags = inhibitSuspend ? (4u | (inhibitDisplay ? 8u : 0u)) : 0u;

        const auto cookieCall = [&bus](const QString &service, const QString &path,
                                       const QString &interface, const QString &method,
                                       const QVariantList &arguments) -> uint {
            const auto *busInterface = bus.interface();
            if (!busInterface || !busInterface->isServiceRegistered(service).value())
                return 0;
            QDBusInterface target(service, path, interface, bus);
            const QDBusMessage reply = target.callWithArgumentList(QDBus::Block, method, arguments);
            if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().isEmpty())
                return 0;
            return reply.arguments().constFirst().toUInt();
        };
        const auto releaseCookie = [&bus](const QString &service, const QString &path,
                                          const QString &interface, const QString &method,
                                          uint cookie) {
            if (!cookie)
                return;
            const auto *busInterface = bus.interface();
            if (!busInterface || !busInterface->isServiceRegistered(service).value())
                return;
            QDBusInterface target(service, path, interface, bus);
            target.callWithArgumentList(QDBus::Block, method, {QVariant::fromValue(cookie)});
        };

        if (gnomeFlags != m_gnomeInhibitFlags) {
            releaseCookie(QStringLiteral("org.gnome.SessionManager"),
                          QStringLiteral("/org/gnome/SessionManager"),
                          QStringLiteral("org.gnome.SessionManager"), QStringLiteral("Uninhibit"),
                          m_gnomeInhibitCookie);
            m_gnomeInhibitCookie = 0;
            m_gnomeInhibitFlags = 0;
            if (gnomeFlags) {
                m_gnomeInhibitCookie = cookieCall(
                    QStringLiteral("org.gnome.SessionManager"),
                    QStringLiteral("/org/gnome/SessionManager"),
                    QStringLiteral("org.gnome.SessionManager"), QStringLiteral("Inhibit"),
                    {QStringLiteral("org.VideoLAN.VLC"), 0u,
                     QStringLiteral("Playing media"), gnomeFlags});
                if (m_gnomeInhibitCookie)
                    m_gnomeInhibitFlags = gnomeFlags;
            }
        }

        if (inhibitDisplay && !m_screenSaverInhibitCookie) {
            m_screenSaverInhibitCookie = cookieCall(
                QStringLiteral("org.freedesktop.ScreenSaver"), QStringLiteral("/ScreenSaver"),
                QStringLiteral("org.freedesktop.ScreenSaver"), QStringLiteral("Inhibit"),
                {QStringLiteral("VLC Neo"), QStringLiteral("Playing video")});
        } else if (!inhibitDisplay && m_screenSaverInhibitCookie) {
            releaseCookie(QStringLiteral("org.freedesktop.ScreenSaver"), QStringLiteral("/ScreenSaver"),
                          QStringLiteral("org.freedesktop.ScreenSaver"), QStringLiteral("UnInhibit"),
                          m_screenSaverInhibitCookie);
            m_screenSaverInhibitCookie = 0;
        }

        if (inhibitSuspend && !m_kdeInhibitCookie) {
            const QString reason = QStringLiteral("Media playback");
            m_kdeInhibitCookie = cookieCall(
                QStringLiteral("org.freedesktop.PowerManagement"),
                QStringLiteral("/org/freedesktop/PowerManagement/Inhibit"),
                QStringLiteral("org.freedesktop.PowerManagement.Inhibit"), QStringLiteral("Inhibit"),
                {QStringLiteral("VLC Neo"), reason});
        } else if (!inhibitSuspend && m_kdeInhibitCookie) {
            releaseCookie(QStringLiteral("org.freedesktop.PowerManagement"),
                          QStringLiteral("/org/freedesktop/PowerManagement/Inhibit"),
                          QStringLiteral("org.freedesktop.PowerManagement.Inhibit"), QStringLiteral("UnInhibit"),
                          m_kdeInhibitCookie);
            m_kdeInhibitCookie = 0;
        }
    }

    Q_INVOKABLE QVariantList fullscreenScreenChoices() const
    {
        QVariantList choices;
        choices.append(QVariantMap{{QStringLiteral("label"), QStringLiteral("Current screen")},
                                   {QStringLiteral("value"), -1}});
        const auto screens = QGuiApplication::screens();
        for (qsizetype i = 0; i < screens.size(); ++i) {
            const QString name = screens.at(i)->name().isEmpty()
                                     ? QStringLiteral("Display %1").arg(i + 1)
                                     : QStringLiteral("Display %1 — %2").arg(i + 1).arg(screens.at(i)->name());
            choices.append(QVariantMap{{QStringLiteral("label"), name},
                                       {QStringLiteral("value"), i}});
        }
        return choices;
    }

    Q_INVOKABLE bool selectFullscreenScreen(QObject *target, int screenIndex) const
    {
        auto *window = qobject_cast<QWindow *>(target);
        if (!window)
            return false;
        if (screenIndex < 0)
            return true;
        const auto screens = QGuiApplication::screens();
        if (screenIndex >= screens.size())
            return false;
        window->setScreen(screens.at(screenIndex));
        return window->screen() == screens.at(screenIndex);
    }

    Q_INVOKABLE int fullscreenScreenIndex(QObject *target) const
    {
        auto *window = qobject_cast<QWindow *>(target);
        if (!window || !window->screen())
            return -1;
        return QGuiApplication::screens().indexOf(window->screen());
    }

    Q_INVOKABLE QVariantMap availableGeometry(QObject *target) const
    {
        auto *window = qobject_cast<QWindow *>(target);
        QScreen *screen = window ? window->screen() : nullptr;
        if (!screen)
            screen = QGuiApplication::primaryScreen();
        if (!screen)
            return {};
        const QRect area = screen->availableGeometry();
        return {{QStringLiteral("x"), area.x()}, {QStringLiteral("y"), area.y()},
                {QStringLiteral("width"), area.width()}, {QStringLiteral("height"), area.height()}};
    }

    // Picture-in-picture: Wayland apps cannot pin themselves, so ask Hyprland.
    Q_INVOKABLE void setPinned(bool pinned)
    {
        if (!hyprland())
            return;
        const QString window = QStringLiteral("pid:%1").arg(QCoreApplication::applicationPid());
        if (pinned) {
            if (m_hyprlandPipStateCaptured)
                return;
            QProcess query;
            query.start(QStringLiteral("hyprctl"), {QStringLiteral("-j"), QStringLiteral("clients")});
            if (!query.waitForStarted(500) || !query.waitForFinished(1000)
                || query.exitStatus() != QProcess::NormalExit || query.exitCode() != 0)
                return;

            const QJsonDocument document = QJsonDocument::fromJson(query.readAllStandardOutput());
            if (!document.isArray())
                return;
            const qint64 processId = QCoreApplication::applicationPid();
            for (const QJsonValue &value : document.array()) {
                const QJsonObject client = value.toObject();
                if (client.value(QStringLiteral("pid")).toVariant().toLongLong() != processId)
                    continue;
                const QJsonArray at = client.value(QStringLiteral("at")).toArray();
                const QJsonArray size = client.value(QStringLiteral("size")).toArray();
                if (at.size() < 2 || size.size() < 2)
                    return;
                m_hyprlandPipStateCaptured = true;
                m_hyprlandWasFloating = client.value(QStringLiteral("floating")).toBool();
                m_hyprlandWasPinned = client.value(QStringLiteral("pinned")).toBool();
                m_hyprlandPosition = QPoint(qRound(at.at(0).toDouble()), qRound(at.at(1).toDouble()));
                m_hyprlandSize = QSize(qRound(size.at(0).toDouble()), qRound(size.at(1).toDouble()));
                break;
            }
            if (!m_hyprlandPipStateCaptured)
                return;

            QStringList commands = {
                QStringLiteral("dispatch setfloating %1").arg(window),
                QStringLiteral("dispatch resizewindowpixel exact 480 270,%1").arg(window),
                QStringLiteral("dispatch movewindowpixel exact 70% 68%,%1").arg(window)
            };
            if (!m_hyprlandWasPinned)
                commands.append(QStringLiteral("dispatch pin %1").arg(window));
            QProcess::startDetached(QStringLiteral("hyprctl"),
                                    {QStringLiteral("--batch"), commands.join(QStringLiteral(" ; "))});
        } else {
            if (!m_hyprlandPipStateCaptured)
                return;
            QStringList commands;
            if (!m_hyprlandWasPinned)
                commands.append(QStringLiteral("dispatch pin %1").arg(window));
            if (m_hyprlandWasFloating) {
                commands.append(QStringLiteral("dispatch resizewindowpixel exact %1 %2,%3")
                                    .arg(m_hyprlandSize.width()).arg(m_hyprlandSize.height()).arg(window));
                commands.append(QStringLiteral("dispatch movewindowpixel exact %1 %2,%3")
                                    .arg(m_hyprlandPosition.x()).arg(m_hyprlandPosition.y()).arg(window));
            } else {
                commands.append(QStringLiteral("dispatch settiled %1").arg(window));
            }
            QProcess::startDetached(QStringLiteral("hyprctl"),
                                    {QStringLiteral("--batch"), commands.join(QStringLiteral(" ; "))});
            m_hyprlandPipStateCaptured = false;
        }
    }

    Q_INVOKABLE QString localPath(const QUrl &url) const { return url.toLocalFile(); }
    Q_INVOKABLE QString homePath() const { return QDir::homePath(); }
    Q_INVOKABLE QString playlistLibraryDirectory() const
    {
        const QString path = QDir(QStandardPaths::writableLocation(QStandardPaths::AppDataLocation))
                                 .filePath(QStringLiteral("Playlists"));
        QDir().mkpath(path);
        return path;
    }
    Q_INVOKABLE QUrl playlistCoverUrl(const QUrl &playlist) const
    {
        const QFileInfo info(playlist.toLocalFile());
        QDir dir(info.absolutePath());
        const QStringList covers = dir.entryList({info.completeBaseName() + QStringLiteral(".cover.*")}, QDir::Files, QDir::Name);
        return covers.isEmpty() ? QUrl() : QUrl::fromLocalFile(dir.filePath(covers.first()));
    }
    // "/home/me/Videos/x.mkv" -> "~/Videos/x.mkv"; remote URLs unchanged.
    Q_INVOKABLE QString displayPath(const QUrl &url) const
    {
        if (!url.isLocalFile())
            return url.toDisplayString();
        const QString path = url.toLocalFile();
        const QString home = QDir::homePath();
        return path.startsWith(home + QLatin1Char('/')) ? QLatin1Char('~') + path.mid(home.size()) : path;
    }
    Q_INVOKABLE QUrl fileUrl(const QString &path) const { return QUrl::fromLocalFile(path); }

private:
    uint m_gnomeInhibitCookie = 0;
    uint m_gnomeInhibitFlags = 0;
    uint m_screenSaverInhibitCookie = 0;
    uint m_kdeInhibitCookie = 0;
    bool m_hyprlandPipStateCaptured = false;
    bool m_hyprlandWasFloating = false;
    bool m_hyprlandWasPinned = false;
    QPoint m_hyprlandPosition;
    QSize m_hyprlandSize;
};
