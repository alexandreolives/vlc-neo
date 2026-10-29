#include "platform.hpp"

#include <QCoreApplication>
#include <QDBusConnection>

#include <cstdio>

class FakeMateSessionManager : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.mate.SessionManager")

public slots:
    uint Inhibit(const QString &, uint, const QString &, uint flags)
    {
        inhibitFlags.append(flags);
        return nextCookie++;
    }

    void Uninhibit(uint cookie) { uninhibitCookies.append(cookie); }

public:
    QList<uint> inhibitFlags;
    QList<uint> uninhibitCookies;
    uint nextCookie = 41;
};

static bool expect(bool condition, const char *message)
{
    std::fprintf(condition ? stdout : stderr, "%s  %s\n", condition ? "PASS" : "FAIL", message);
    return condition;
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected())
        return expect(false, "private D-Bus session is connected") ? 0 : 1;

    FakeMateSessionManager mateSessionManager;
    bool ok = true;
    ok &= expect(bus.registerService(QStringLiteral("org.mate.SessionManager")),
                 "private D-Bus session can register a MATE session manager");
    ok &= expect(bus.registerObject(QStringLiteral("/org/mate/SessionManager"),
                                    &mateSessionManager, QDBusConnection::ExportAllSlots),
                 "private D-Bus session exports the MATE inhibition API");

    Platform platform;
    platform.setPlaybackInhibition(true, false, true);
    ok &= expect(mateSessionManager.inhibitFlags == QList<uint>{4},
                 "audio playback inhibits suspend only");

    platform.setPlaybackInhibition(true, true, true);
    ok &= expect(mateSessionManager.inhibitFlags == (QList<uint>{4, 12})
                     && mateSessionManager.uninhibitCookies == QList<uint>{41},
                 "video playback also inhibits display idle and releases the replaced cookie");

    platform.setPlaybackInhibition(false, false, true);
    ok &= expect(mateSessionManager.uninhibitCookies == (QList<uint>{41, 42}),
                 "playback stop releases the session-manager inhibitor");

    bus.unregisterObject(QStringLiteral("/org/mate/SessionManager"));
    bus.unregisterService(QStringLiteral("org.mate.SessionManager"));
    return ok ? 0 : 1;
}

#include "platform_inhibit_test.moc"
