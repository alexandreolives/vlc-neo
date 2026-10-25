// Qt application lifetime for the interface thread.
#include <QFont>
#include <QFontDatabase>
#include <QFileInfo>
#include <QGuiApplication>
#include <QLibraryInfo>
#include <QDragEnterEvent>
#include <QDropEvent>
#include <QMimeData>
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
#include <QUrl>
#include <functional>
#include <memory>
#include <QQuickStyle>
#include <QQuickItem>
#include <QQuickWindow>
#include <QCursor>

#include "icon_provider.hpp"
#include "media_library.hpp"
#include "neo.hpp"
#include "open_subtitles_client.hpp"
#include "platform.hpp"
#include "player.hpp"
#include "status_notifier.hpp"
#include "thumbnail_provider.hpp"
#include "vlc_tasks.hpp"
#include "video_item.hpp"
#include "vlc3_player_backend.hpp"

namespace {
QMutex g_appLock;
QPointer<QGuiApplication> g_app;
constexpr const char *kPreferredFont = "thmanyah sans";

// QML cursor shapes can be replaced by cursors set by hovered child items.
// Apply the fullscreen idle cursor on the window itself so it wins after all
// scene-graph hover handling has run; any mouse input restores it immediately.
class FullscreenCursorAutoHide final : public QObject
{
public:
    explicit FullscreenCursorAutoHide(QQuickWindow *window)
        : QObject(window), m_window(window)
    {
        m_timer.setSingleShot(true);
        m_timer.setInterval(2000);
        connect(&m_timer, &QTimer::timeout, this, [this] {
            if (m_window && m_window->visibility() == QWindow::FullScreen)
                m_window->setCursor(QCursor(Qt::BlankCursor));
        });
        if (window) {
            window->installEventFilter(this);
            connect(window, &QWindow::visibilityChanged, this, [this](QWindow::Visibility visibility) {
                if (!m_window)
                    return;
                m_window->setCursor(QCursor(Qt::ArrowCursor));
                if (visibility == QWindow::FullScreen)
                    m_timer.start();
                else
                    m_timer.stop();
            });
            if (window->visibility() == QWindow::FullScreen)
                m_timer.start();
        }
    }

protected:
    bool eventFilter(QObject *watched, QEvent *event) override
    {
        if (watched == m_window && m_window) {
            switch (event->type()) {
            case QEvent::MouseMove:
            case QEvent::MouseButtonPress:
            case QEvent::MouseButtonRelease:
            case QEvent::Wheel:
                if (m_window->visibility() == QWindow::FullScreen) {
                    m_window->setCursor(QCursor(Qt::ArrowCursor));
                    m_timer.start();
                }
                break;
            case QEvent::Leave:
                m_timer.stop();
                m_window->setCursor(QCursor(Qt::ArrowCursor));
                break;
            default:
                break;
            }
        }
        return QObject::eventFilter(watched, event);
    }

private:
    QPointer<QQuickWindow> m_window;
    QTimer m_timer;
};

QUrl openSubtitlesApiBaseUrl()
{
    if (!qEnvironmentVariableIsEmpty("NEO_TEST_STEPS")) {
        const QUrl testUrl(qEnvironmentVariable("NEO_TEST_OPENSUBTITLES_API_URL"));
        if (testUrl.scheme() == QLatin1String("http")
            && testUrl.host() == QLatin1String("127.0.0.1") && testUrl.port() > 0)
            return testUrl;
    }
    return QUrl(QStringLiteral("https://api.opensubtitles.com/api/v1"));
}

// Developer hooks for headless verification (QT_QPA_PLATFORM=offscreen):
//   NEO_TEST_STEPS="1500:js expression|3000:drag-item:source:target:x,y|4000:quit"
// Steps run strictly in order. "N:" is an absolute time since start;
// "+N:" waits N ms after the previous step finished (use it for screenshots,
// where grabs are slow and absolute timings would bunch up).
QQuickItem *findVisualItem(QQuickItem *parent, const QString &objectName)
{
    if (!parent)
        return nullptr;
    if (parent->objectName() == objectName)
        return parent;
    for (QQuickItem *child : parent->childItems()) {
        if (QQuickItem *match = findVisualItem(child, objectName))
            return match;
    }
    return nullptr;
}

void runTestStep(QObject *root, QQuickWindow *window, const QString &action)
{
    if (action == QLatin1String("quit")) {
        window->close();
    } else if (action.startsWith(QLatin1String("focus-item:"))) {
        const QString objectName = action.mid(11);
        QQuickItem *target = window ? findVisualItem(window->contentItem(), objectName) : nullptr;
        if (!target) {
            qWarning("neo test: invalid focus item: %s", qPrintable(objectName));
            return;
        }
        target->forceActiveFocus(Qt::TabFocusReason);
        qInfo("neo test: focused %s (%d)", qPrintable(objectName), int(target->hasActiveFocus()));
    } else if (action.startsWith(QLatin1String("move:")) || action.startsWith(QLatin1String("move-item:"))) {
        if (!window)
            return;
        QPointF local;
        if (action.startsWith(QLatin1String("move-item:"))) {
            const QString objectName = action.mid(10);
            QQuickItem *target = findVisualItem(window->contentItem(), objectName);
            if (!target) {
                qWarning("neo test: invalid move item: %s", qPrintable(objectName));
                return;
            }
            local = target->mapToScene(QPointF(target->width() / 2, target->height() / 2));
        } else {
            const QStringList coordinates = action.mid(5).split(QLatin1Char(','));
            if (coordinates.size() != 2) {
                qWarning("neo test: invalid move target: %s", qPrintable(action));
                return;
            }
            local = QPointF(coordinates.at(0).toDouble(), coordinates.at(1).toDouble());
        }
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
            if (QQuickItem *target = findVisualItem(window->contentItem(), objectName)) {
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
    } else if (action.startsWith(QLatin1String("drop-urls:"))) {
        const QString payload = action.mid(10);
        const qsizetype separator = payload.indexOf(QLatin1Char(':'));
        QQuickItem *target = separator > 0 ? root->findChild<QQuickItem *>(payload.left(separator)) : nullptr;
        const QStringList values = separator > 0
                ? payload.mid(separator + 1).split(QLatin1Char(';'), Qt::SkipEmptyParts)
                : QStringList{};
        QList<QUrl> urls;
        for (const QString &value : values)
            urls.append(QUrl(value));
        if (!window || !target || urls.isEmpty()) {
            qWarning("neo test: invalid URL drop target: %s", qPrintable(action));
            return;
        }
        QMimeData mimeData;
        mimeData.setUrls(urls);
        const QPointF position = target->mapToScene(QPointF(target->width() / 2, target->height() / 2));
        const QPoint integerPosition = position.toPoint();
        QDragEnterEvent enter(integerPosition, Qt::CopyAction, &mimeData, Qt::LeftButton, Qt::NoModifier);
        QCoreApplication::sendEvent(window, &enter);
        QDropEvent drop(position, Qt::CopyAction, &mimeData, Qt::LeftButton, Qt::NoModifier);
        QCoreApplication::sendEvent(window, &drop);
        qInfo("neo test: dropped %d URL(s) on %s (enter=%d drop=%d)", int(urls.size()),
              qPrintable(payload.left(separator)), int(enter.isAccepted()), int(drop.isAccepted()));
    } else if (action.startsWith(QLatin1String("drag-item:"))) {
        const QStringList parts = action.mid(10).split(QLatin1Char(':'));
        const auto findVisualItem = [](QQuickItem *parent, const QString &name, const auto &self) -> QQuickItem * {
            if (!parent)
                return nullptr;
            if (parent->objectName() == name)
                return parent;
            for (QQuickItem *child : parent->childItems()) {
                if (QQuickItem *found = self(child, name, self))
                    return found;
            }
            return nullptr;
        };
        QQuickItem *source = nullptr;
        QQuickItem *target = nullptr;
        if (parts.size() == 3) {
            for (QWindow *candidate : QGuiApplication::allWindows()) {
                auto *quickWindow = qobject_cast<QQuickWindow *>(candidate);
                if (!quickWindow)
                    continue;
                if (!source)
                    source = findVisualItem(quickWindow->contentItem(), parts.at(0), findVisualItem);
                if (!target)
                    target = findVisualItem(quickWindow->contentItem(), parts.at(1), findVisualItem);
                if (source && target)
                    break;
            }
        }
        const QStringList offset = parts.size() == 3 ? parts.at(2).split(QLatin1Char(',')) : QStringList{};
        if (!window || !source || !target || offset.size() != 2) {
            qWarning("neo test: invalid drag target: %s (window=%d source=%d target=%d offset=%d)",
                     qPrintable(action), int(window != nullptr), int(source != nullptr),
                     int(target != nullptr), int(offset.size()));
            return;
        }
        QStringList miniPlayerControlNames;
        const QString cardName = target->objectName();
        if (cardName == QLatin1String("home-mini-player")) {
            miniPlayerControlNames = {
                QStringLiteral("home-mini-player-close"), QStringLiteral("home-mini-player-expand"),
                QStringLiteral("home-mini-player-previous"), QStringLiteral("home-mini-player-toggle"),
                QStringLiteral("home-mini-player-next"), QStringLiteral("home-mini-player-queue")
            };
        } else if (cardName == QLatin1String("mini-player")) {
            miniPlayerControlNames = {
                QStringLiteral("mini-player-close"), QStringLiteral("mini-player-expand"),
                QStringLiteral("mini-player-previous"), QStringLiteral("mini-player-play"),
                QStringLiteral("mini-player-next"), QStringLiteral("mini-player-queue")
            };
        }
        QList<QQuickItem *> miniPlayerControls;
        QList<QPointF> miniPlayerControlOffsets;
        for (const QString &name : miniPlayerControlNames) {
            QQuickItem *control = findVisualItem(target, name, findVisualItem);
            if (!control) {
                miniPlayerControls.clear();
                break;
            }
            miniPlayerControls.append(control);
            miniPlayerControlOffsets.append(control->mapToItem(
                target, QPointF(control->width() / 2, control->height() / 2)));
        }
        int miniPlayerDragStepsWithAttachedControls = 0;
        bool miniPlayerControlsFollowedCard = !miniPlayerControlNames.isEmpty()
                                              && miniPlayerControls.size() == miniPlayerControlNames.size();
        const QPointF from = source->mapToScene(QPointF(source->width() / 2, source->height() / 2));
        const QPointF to = target->mapToScene(QPointF(offset.at(0).toDouble(), offset.at(1).toDouble()));
        const auto sendMouse = [window](QEvent::Type type, const QPointF &position,
                                        Qt::MouseButton button, Qt::MouseButtons buttons) {
            const QPointF global(window->mapToGlobal(position.toPoint()));
            QMouseEvent event(type, position, position, global, button, buttons, Qt::NoModifier);
            QCoreApplication::sendEvent(window, &event);
        };
        sendMouse(QEvent::MouseButtonPress, from, Qt::LeftButton, Qt::LeftButton);
        for (int i = 1; i <= 6; ++i) {
            sendMouse(QEvent::MouseMove, from + (to - from) * (double(i) / 6.0),
                      Qt::NoButton, Qt::LeftButton);
            if (miniPlayerControlsFollowedCard) {
                bool attachedAtThisStep = true;
                for (qsizetype controlIndex = 0; controlIndex < miniPlayerControls.size(); ++controlIndex) {
                    const QQuickItem *control = miniPlayerControls.at(controlIndex);
                    const QPointF center = control->mapToItem(
                        target, QPointF(control->width() / 2, control->height() / 2));
                    const QPointF expected = miniPlayerControlOffsets.at(controlIndex);
                    if (qAbs(center.x() - expected.x()) > 1.0 || qAbs(center.y() - expected.y()) > 1.0) {
                        attachedAtThisStep = false;
                        break;
                    }
                }
                miniPlayerControlsFollowedCard = attachedAtThisStep;
                if (attachedAtThisStep)
                    ++miniPlayerDragStepsWithAttachedControls;
            }
        }
        sendMouse(QEvent::MouseButtonRelease, to, Qt::LeftButton, Qt::NoButton);
        if (!miniPlayerControlNames.isEmpty()) {
            const char *viewName = cardName == QLatin1String("home-mini-player") ? "Home" : "Library";
            if (miniPlayerControlsFollowedCard && miniPlayerDragStepsWithAttachedControls == 6)
                qInfo("neo test: %s mini-player controls followed card throughout drag (6/6 steps)", viewName);
            else
                qWarning("neo test: %s mini-player control tracking failed (%d/6 drag steps)", viewName,
                         miniPlayerDragStepsWithAttachedControls);
        }
        qInfo("neo test: dragged %s to %s", qPrintable(parts.at(0)), qPrintable(parts.at(1)));
    } else if (action.startsWith(QLatin1String("key:"))) {
        const QString keyName = action.mid(4);
        const QHash<QString, int> keys = {
            {QStringLiteral("Tab"), Qt::Key_Tab},
            {QStringLiteral("Left"), Qt::Key_Left}, {QStringLiteral("Right"), Qt::Key_Right},
            {QStringLiteral("Up"), Qt::Key_Up}, {QStringLiteral("Down"), Qt::Key_Down},
            {QStringLiteral("Home"), Qt::Key_Home}, {QStringLiteral("End"), Qt::Key_End},
            {QStringLiteral("Space"), Qt::Key_Space}, {QStringLiteral("Return"), Qt::Key_Return},
            {QStringLiteral("Esc"), Qt::Key_Escape}, {QStringLiteral("F11"), Qt::Key_F11},
            {QStringLiteral("MediaPlay"), Qt::Key_MediaPlay}, {QStringLiteral("MediaPause"), Qt::Key_MediaPause},
            {QStringLiteral("MediaTogglePlayPause"), Qt::Key_MediaTogglePlayPause},
            {QStringLiteral("MediaNext"), Qt::Key_MediaNext}, {QStringLiteral("MediaPrevious"), Qt::Key_MediaPrevious},
            {QStringLiteral("MediaStop"), Qt::Key_MediaStop}
        };
        Qt::KeyboardModifiers modifiers = Qt::NoModifier;
        QString baseKey;
        const QStringList parts = keyName.split(QLatin1Char('+'), Qt::SkipEmptyParts);
        for (const QString &part : parts) {
            if (part == QLatin1String("Ctrl")) modifiers |= Qt::ControlModifier;
            else if (part == QLatin1String("Alt")) modifiers |= Qt::AltModifier;
            else if (part == QLatin1String("Shift")) modifiers |= Qt::ShiftModifier;
            else if (part == QLatin1String("Meta")) modifiers |= Qt::MetaModifier;
            else baseKey = part;
        }
        int key = keys.value(baseKey, 0);
        if (!key && baseKey.size() == 1) key = baseKey.at(0).toUpper().unicode();
        QQuickItem *focusItem = window ? window->activeFocusItem() : nullptr;
        if (key && focusItem) {
            const QString text = (modifiers & Qt::ShiftModifier) ? baseKey.toUpper() : baseKey.toLower();
            QKeyEvent event(QEvent::KeyPress, key, modifiers, text);
            event.setAccepted(false);
            QCoreApplication::sendEvent(focusItem, &event);
            QKeyEvent releaseEvent(QEvent::KeyRelease, key, modifiers, text);
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

#ifdef Q_OS_LINUX
    // Qt's generic X11 theme reports Light on Cinnamon even when the desktop
    // is using a dark GTK theme. Load Qt's GTK platform theme when available
    // so System mode starts with the real desktop color scheme and follows
    // changes while Neo is open. Keep explicit user/platform overrides intact.
    const QString desktops = qEnvironmentVariable("XDG_CURRENT_DESKTOP").toLower();
    const QString qpaPlatform = qEnvironmentVariable("QT_QPA_PLATFORM").toLower();
    const bool gtkDesktop = desktops.contains(QStringLiteral("cinnamon"))
            || desktops.contains(QStringLiteral("gnome"))
            || desktops.contains(QStringLiteral("unity"));
    const bool windowedPlatform = qpaPlatform.isEmpty()
            || qpaPlatform == QLatin1String("xcb")
            || qpaPlatform == QLatin1String("wayland");
    const QString gtkThemePlugin = QLibraryInfo::path(QLibraryInfo::PluginsPath)
            + QStringLiteral("/platformthemes/libqgtk3.so");
    if (!qEnvironmentVariableIsSet("QT_QPA_PLATFORMTHEME") && gtkDesktop
            && windowedPlatform && QFileInfo::exists(gtkThemePlugin)) {
        qputenv("QT_QPA_PLATFORMTHEME", "gtk3");
    }
#endif

    QGuiApplication app(argc, argv);
    app.setApplicationVersion(QStringLiteral(NEO_VERSION));
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
    StatusNotifier systemTray;
    MediaLibrary mediaLibrary;
    VlcTasks vlcTasks;
    OpenSubtitlesClient openSubtitles(nullptr, openSubtitlesApiBaseUrl());

    QQmlApplicationEngine engine;
    engine.addImageProvider(QStringLiteral("icon"), new IconProvider);
    auto *thumbnailProvider = new ThumbnailProvider;
    engine.addImageProvider(QStringLiteral("thumbnail"), thumbnailProvider);
    engine.rootContext()->setContextProperty(QStringLiteral("player"), &player);
    engine.rootContext()->setContextProperty(QStringLiteral("platform"), &platform);
    engine.rootContext()->setContextProperty(QStringLiteral("systemTray"), &systemTray);
    engine.rootContext()->setContextProperty(QStringLiteral("mediaLibrary"), &mediaLibrary);
    engine.rootContext()->setContextProperty(QStringLiteral("vlcTasks"), &vlcTasks);
    engine.rootContext()->setContextProperty(QStringLiteral("openSubtitles"), &openSubtitles);
    engine.load(QUrl(QStringLiteral("qrc:/neo/qml/Main.qml")));

    ready(readyData);

    if (!engine.rootObjects().isEmpty()) {
        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        FullscreenCursorAutoHide cursorAutoHide(window);
        installTestHooks(engine.rootObjects().first());
        app.exec();
    }

    // VLC can close the interface while thumbnail/waveform jobs are still
    // decoding. Drain them before the Qt application and its image plugins
    // start tearing down.
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
