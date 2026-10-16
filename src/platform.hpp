// Small desktop helpers exposed to QML (clipboard, compositor tricks).
#pragma once

#include <QClipboard>
#include <QDir>
#include <QGuiApplication>
#include <QObject>
#include <QProcess>
#include <QUrl>

class Platform : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool hyprland READ hyprland CONSTANT)

public:
    using QObject::QObject;

    bool hyprland() const { return qEnvironmentVariableIsSet("HYPRLAND_INSTANCE_SIGNATURE"); }

    Q_INVOKABLE QString clipboardText() const { return QGuiApplication::clipboard()->text().trimmed(); }

    // Picture-in-picture: Wayland apps cannot pin themselves, so ask Hyprland.
    Q_INVOKABLE void setPinned(bool pinned)
    {
        if (!hyprland())
            return;
        const QString window = QStringLiteral("pid:%1").arg(QCoreApplication::applicationPid());
        if (pinned) {
            QProcess::startDetached(QStringLiteral("hyprctl"),
                {QStringLiteral("--batch"),
                 QStringLiteral("dispatch setfloating %1 ; dispatch resizewindowpixel exact 480 270,%1 ; "
                                "dispatch movewindowpixel exact 70% 68%,%1 ; dispatch pin %1").arg(window)});
        } else {
            QProcess::startDetached(QStringLiteral("hyprctl"),
                {QStringLiteral("--batch"),
                 QStringLiteral("dispatch pin %1 ; dispatch settiled %1").arg(window)});
        }
    }

    Q_INVOKABLE QString localPath(const QUrl &url) const { return url.toLocalFile(); }
    Q_INVOKABLE QString homePath() const { return QDir::homePath(); }
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
};
