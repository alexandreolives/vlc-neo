// Qt application lifetime for the interface thread.
#include <QFont>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QHash>
#include <QMouseEvent>
#include <QKeyEvent>
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
#include <QQuickItem>
#include <QQuickWindow>

#include "icon_provider.hpp"
#include "neo.hpp"
#include "platform.hpp"
#include "player.hpp"
#include "thumbnail_provider.hpp"
#include "video_item.hpp"
#include "vlc3_player_backend.hpp"

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
    } else if (action.startsWith(QLatin1String("move:"))) {
        if (!window)
            return;
        const QStringList coordinates = action.mid(5).split(QLatin1Char(','));
        if (coordinates.size() != 2) {
            qWarning("neo test: invalid move target: %s", qPrintable(action));
            return;
        }
        const QPointF local(coordinates.at(0).toDouble(), coordinates.at(1).toDouble());
        const QPointF global(window->mapToGlobal(local.toPoint()));
        QMouseEvent move(QEvent::MouseMove, local, local, global,
                         Qt::NoButton, Qt::NoButton, Qt::NoModifier);
        QCoreApplication::sendEvent(window, &move);
        qInfo("neo test: moved pointer to %d,%d", int(local.x()), int(local.y()));
    } else if (action.startsWith(QLatin1String("click:")) || action.startsWith(QLatin1String("click-item:"))) {
        QPointF local;
        bool validTarget = false;
        if (action.startsWith(QLatin1String("click:"))) {
            const QStringList coordinates = action.mid(6).split(QLatin1Char(','));
            if (coordinates.size() == 2) {
                local = QPointF(coordinates.at(0).toDouble(), coordinates.at(1).toDouble());
                validTarget = true;
            }
        } else if (window) {
            const QString objectName = action.mid(11);
            if (QQuickItem *target = root->findChild<QQuickItem *>(objectName);
                target && target->window() == window) {
                local = target->mapToScene(QPointF(target->width() / 2, target->height() / 2));
                validTarget = true;
            }
        }
        if (window && validTarget) {
            const QPointF global(window->mapToGlobal(local.toPoint()));
            QMouseEvent press(QEvent::MouseButtonPress, local, local, global,
                              Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
            QCoreApplication::sendEvent(window, &press);
            QMouseEvent release(QEvent::MouseButtonRelease, local, local, global,
                                Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
            QCoreApplication::sendEvent(window, &release);
            qInfo("neo test: click target at %d,%d delivered", int(local.x()), int(local.y()));
        } else {
            qWarning("neo test: invalid click target: %s", qPrintable(action));
        }
    } else if (action.startsWith(QLatin1String("key:"))) {
        const QString keyName = action.mid(4);
        const QHash<QString, int> keys = {
            {QStringLiteral("Left"), Qt::Key_Left}, {QStringLiteral("Right"), Qt::Key_Right},
            {QStringLiteral("Home"), Qt::Key_Home}, {QStringLiteral("End"), Qt::Key_End},
            {QStringLiteral("Space"), Qt::Key_Space}, {QStringLiteral("Return"), Qt::Key_Return}
        };
        QQuickItem *focusItem = window ? window->activeFocusItem() : nullptr;
        if (keys.contains(keyName) && focusItem) {
            QKeyEvent event(QEvent::KeyPress, keys.value(keyName), Qt::NoModifier);
            event.setAccepted(false);
            QCoreApplication::sendEvent(focusItem, &event);
            QKeyEvent releaseEvent(QEvent::KeyRelease, keys.value(keyName), Qt::NoModifier);
            releaseEvent.setAccepted(false);
            QCoreApplication::sendEvent(focusItem, &releaseEvent);
            qInfo("neo test: key %s delivered (%d)", qPrintable(keyName), event.isAccepted());
        } else {
            qWarning("neo test: key %s not delivered (no focus item or unknown key)", qPrintable(keyName));
        }
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

    Player player(makeVlc3PlayerBackend(intf, pl_Get(intf)));
    Platform platform;

    QQmlApplicationEngine engine;
    engine.addImageProvider(QStringLiteral("icon"), new IconProvider);
    auto *thumbnailProvider = new ThumbnailProvider;
    engine.addImageProvider(QStringLiteral("thumbnail"), thumbnailProvider);
    engine.rootContext()->setContextProperty(QStringLiteral("player"), &player);
    engine.rootContext()->setContextProperty(QStringLiteral("platform"), &platform);
    engine.load(QUrl(QStringLiteral("qrc:/neo/qml/Main.qml")));

    ready(readyData);

    if (!engine.rootObjects().isEmpty()) {
        installTestHooks(engine.rootObjects().first());
        app.exec();
    }
    // Drain asynchronous VLC/FFmpeg jobs before Qt image plugins tear down.
    thumbnailProvider->waitForJobs();

    QMutexLocker locker(&g_appLock);
    g_app = nullptr;
}

void NeoQuitUi()
{
    QMutexLocker locker(&g_appLock);
    if (g_app)
        QMetaObject::invokeMethod(g_app.data(), "quit", Qt::QueuedConnection);
}
