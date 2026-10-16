// Qt application lifetime for the interface thread.
#include <QFont>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QMutex>
#include <QPointer>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQmlExpression>
#include <QTimer>
#include <QElapsedTimer>
#include <functional>
#include <memory>
#include <QQuickStyle>
#include <QQuickWindow>

#include "icon_provider.hpp"
#include "neo.hpp"
#include "platform.hpp"
#include "player.hpp"
#include "video_item.hpp"

namespace {
QMutex g_appLock;
QPointer<QGuiApplication> g_app;
constexpr const char *kPreferredFont = "thmanyah sans";

// Developer hooks for headless verification (QT_QPA_PLATFORM=offscreen):
//   NEO_TEST_STEPS="1500:js expression|3000:grab:/tmp/a.png|4000:quit"
// Steps run strictly in order. "N:" is an absolute time since start;
// "+N:" waits N ms after the previous step finished (use it for screenshots,
// where grabs are slow and absolute timings would bunch up).
void runTestStep(QObject *root, QQuickWindow *window, const QString &action)
{
    if (action == QLatin1String("quit")) {
        window->close();
    } else if (action.startsWith(QLatin1String("grab:"))) {
        if (window) {
            const QImage img = window->grabWindow();
            img.save(action.mid(5));
            qInfo("neo test: grab %dx%d window %dx%d dpr %.2f", img.width(), img.height(),
                  window->width(), window->height(), window->devicePixelRatio());
        }
    } else {
        QQmlExpression expr(qmlContext(root), root, action);
        const QVariant result = expr.evaluate();
        if (expr.hasError())
            qWarning("neo test step failed: %s", qPrintable(expr.error().toString()));
        else
            qInfo("neo test: %s => %s", qPrintable(action), qPrintable(result.toString()));
    }
}

void installTestHooks(QObject *root)
{
    const QString steps = qEnvironmentVariable("NEO_TEST_STEPS");
    if (steps.isEmpty())
        return;
    struct Step { bool relative; int ms; QString action; };
    auto queue = std::make_shared<QList<Step>>();
    for (const QString &step : steps.split(QLatin1Char('|'), Qt::SkipEmptyParts)) {
        const int sep = step.indexOf(QLatin1Char(':'));
        if (sep < 0)
            continue;
        const QString when = step.left(sep).trimmed();
        queue->append({when.startsWith(QLatin1Char('+')), when.mid(when.startsWith(QLatin1Char('+')) ? 1 : 0).toInt(),
                       step.mid(sep + 1)});
    }
    auto *window = qobject_cast<QQuickWindow *>(root);
    auto clock = std::make_shared<QElapsedTimer>();
    clock->start();
    auto next = std::make_shared<std::function<void()>>();
    *next = [root, window, queue, clock, next] {
        if (queue->isEmpty())
            return;
        const Step step = queue->takeFirst();
        const int delay = step.relative ? step.ms : int(qMax<qint64>(0, step.ms - clock->elapsed()));
        QTimer::singleShot(delay, root, [root, window, step, next] {
            runTestStep(root, window, step.action);
            (*next)();
        });
    };
    (*next)();
}
} // namespace

void NeoRunUi(intf_thread_t *intf, void (*ready)(void *), void *readyData)
{
    static char arg0[] = "vlc";
    static char *argv[] = {arg0, nullptr};
    int argc = 1;

    QCoreApplication::setOrganizationName(QStringLiteral("vlc-neo"));
    QCoreApplication::setApplicationName(QStringLiteral("neo"));
    QGuiApplication::setDesktopFileName(QStringLiteral("vlc-neo"));
    QQuickStyle::setStyle(QStringLiteral("Basic"));

    QGuiApplication app(argc, argv);
    app.setQuitOnLastWindowClosed(true);
    {
        QMutexLocker locker(&g_appLock);
        g_app = &app;
    }

    if (QFontDatabase::families().contains(QString::fromLatin1(kPreferredFont), Qt::CaseInsensitive)) {
        QFont font(QString::fromLatin1(kPreferredFont));
        font.setPixelSize(13);
        app.setFont(font);
    }

    qmlRegisterType<VideoItem>("Neo", 1, 0, "VideoOutput");
    qmlRegisterSingletonType(QUrl(QStringLiteral("qrc:/neo/qml/singletons/NeoTheme.qml")), "Neo", 1, 0, "Theme");

    Player player(intf);
    Platform platform;

    QQmlApplicationEngine engine;
    engine.addImageProvider(QStringLiteral("icon"), new IconProvider);
    engine.rootContext()->setContextProperty(QStringLiteral("player"), &player);
    engine.rootContext()->setContextProperty(QStringLiteral("platform"), &platform);
    engine.load(QUrl(QStringLiteral("qrc:/neo/qml/Main.qml")));

    ready(readyData);

    if (!engine.rootObjects().isEmpty()) {
        installTestHooks(engine.rootObjects().first());
        app.exec();
    }

    QMutexLocker locker(&g_appLock);
    g_app = nullptr;
}

void NeoQuitUi()
{
    QMutexLocker locker(&g_appLock);
    if (g_app)
        QMetaObject::invokeMethod(g_app.data(), "quit", Qt::QueuedConnection);
}
