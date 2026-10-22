#include "platform.hpp"

#include <QCoreApplication>
#include <QElapsedTimer>
#include <QFile>
#include <QTemporaryDir>
#include <QTextStream>
#include <QThread>

#include <cstdio>

namespace {

bool expect(bool condition, const char *message)
{
    if (!condition)
        std::fprintf(stderr, "FAIL  %s\n", message);
    else
        std::fprintf(stdout, "PASS  %s\n", message);
    return condition;
}

QStringList readCommands(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return {};
    QStringList commands;
    while (!file.atEnd())
        commands.append(QString::fromUtf8(file.readLine()).trimmed());
    return commands;
}

bool waitForCommandCount(const QString &path, qsizetype count)
{
    QElapsedTimer timer;
    timer.start();
    while (timer.elapsed() < 1000) {
        if (readCommands(path).size() >= count)
            return true;
        QThread::msleep(10);
    }
    return false;
}

void setClientState(bool floating, bool pinned, int x, int y, int width, int height)
{
    const QString client = QStringLiteral(
        "[{\"pid\":%1,\"floating\":%2,\"pinned\":%3,\"at\":[%4,%5],\"size\":[%6,%7]}]")
        .arg(QCoreApplication::applicationPid())
        .arg(floating ? QStringLiteral("true") : QStringLiteral("false"))
        .arg(pinned ? QStringLiteral("true") : QStringLiteral("false"))
        .arg(x).arg(y).arg(width).arg(height);
    qputenv("NEO_HYPR_CLIENT_JSON", client.toUtf8());
}

} // namespace

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    QTemporaryDir temp;
    if (!temp.isValid())
        return 1;

    const QString bin = temp.filePath(QStringLiteral("bin"));
    const QString logPath = temp.filePath(QStringLiteral("hyprctl.log"));
    QDir().mkpath(bin);
    QFile stub(QDir(bin).filePath(QStringLiteral("hyprctl")));
    if (!stub.open(QIODevice::WriteOnly | QIODevice::Text))
        return 1;
    QTextStream script(&stub);
    script << "#!/bin/sh\n"
              "if [ \"${1:-}\" = \"-j\" ] && [ \"${2:-}\" = \"clients\" ]; then\n"
              "  printf '%s' \"$NEO_HYPR_CLIENT_JSON\"\n"
              "else\n"
              "  printf '%s\\n' \"$*\" >> \"$NEO_HYPR_LOG\"\n"
              "fi\n";
    stub.close();
    if (!QFile::setPermissions(stub.fileName(), QFileDevice::ReadOwner | QFileDevice::WriteOwner
                                                       | QFileDevice::ExeOwner))
        return 1;

    const QByteArray path = QFile::encodeName(bin) + ':' + qgetenv("PATH");
    qputenv("PATH", path);
    qputenv("HYPRLAND_INSTANCE_SIGNATURE", QByteArrayLiteral("test-instance"));
    qputenv("NEO_HYPR_LOG", QFile::encodeName(logPath));

    Platform platform;
    bool ok = true;

    setClientState(false, false, 11, 22, 1280, 720);
    platform.setPinned(true);
    ok &= expect(waitForCommandCount(logPath, 1), "Hyprland PiP entry dispatches floating geometry");
    platform.setPinned(false);
    ok &= expect(waitForCommandCount(logPath, 2), "Hyprland PiP exit dispatches a restore action");
    QStringList commands = readCommands(logPath);
    ok &= expect(commands.value(0).contains("dispatch setfloating")
                     && commands.value(0).contains("dispatch pin"),
                 "a tiled unpinned window floats and pins for PiP");
    ok &= expect(commands.value(1).contains("dispatch pin")
                     && commands.value(1).contains("dispatch settiled")
                     && !commands.value(1).contains("resizewindowpixel"),
                 "a tiled window returns to tiled state after PiP");

    QFile::remove(logPath);
    setClientState(true, false, 31, 47, 800, 600);
    platform.setPinned(true);
    ok &= expect(waitForCommandCount(logPath, 1), "floating-window PiP entry is dispatched");
    platform.setPinned(false);
    ok &= expect(waitForCommandCount(logPath, 2), "floating-window PiP restore is dispatched");
    commands = readCommands(logPath);
    ok &= expect(commands.value(1).contains("dispatch pin")
                     && commands.value(1).contains("resizewindowpixel exact 800 600")
                     && commands.value(1).contains("movewindowpixel exact 31 47")
                     && !commands.value(1).contains("settiled"),
                 "a previously floating window restores its size and position without being tiled");

    QFile::remove(logPath);
    setClientState(true, true, 50, 60, 900, 650);
    platform.setPinned(true);
    ok &= expect(waitForCommandCount(logPath, 1), "already-pinned floating-window PiP entry is dispatched");
    platform.setPinned(false);
    ok &= expect(waitForCommandCount(logPath, 2), "already-pinned floating-window PiP restore is dispatched");
    commands = readCommands(logPath);
    ok &= expect(!commands.value(0).contains("dispatch pin")
                     && !commands.value(1).contains("dispatch pin")
                     && commands.value(1).contains("resizewindowpixel exact 900 650")
                     && !commands.value(1).contains("settiled"),
                 "PiP preserves an existing pin and the floating layout");

    return ok ? 0 : 1;
}
