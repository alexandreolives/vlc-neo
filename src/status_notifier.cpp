#include "status_notifier.hpp"

#include <QCoreApplication>
#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusReply>
#include <QFile>
#include <QImage>
#include <QPainter>
#include <QSvgRenderer>

namespace {
StatusNotifierPixmap trayPixmap(int size)
{
    QFile icon(QStringLiteral(":/neo/icons/cone.svg"));
    if (!icon.open(QIODevice::ReadOnly))
        return {};
    QSvgRenderer renderer(icon.readAll());
    if (!renderer.isValid())
        return {};

    QImage image(size, size, QImage::Format_ARGB32);
    image.fill(Qt::transparent);
    QPainter painter(&image);
    renderer.render(&painter);
    return {size, size, QByteArray(reinterpret_cast<const char *>(image.constBits()),
                                   qsizetype(image.sizeInBytes()))};
}

QList<StatusNotifierPixmap> trayPixmaps()
{
    static const QList<StatusNotifierPixmap> pixmaps{trayPixmap(32), trayPixmap(64)};
    return pixmaps;
}
} // namespace

QDBusArgument &operator<<(QDBusArgument &argument, const StatusNotifierPixmap &pixmap)
{
    argument.beginStructure();
    argument << pixmap.width << pixmap.height << pixmap.data;
    argument.endStructure();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument, StatusNotifierPixmap &pixmap)
{
    argument.beginStructure();
    argument >> pixmap.width >> pixmap.height >> pixmap.data;
    argument.endStructure();
    return argument;
}

QDBusArgument &operator<<(QDBusArgument &argument, const StatusNotifierToolTip &toolTip)
{
    argument.beginStructure();
    argument << toolTip.iconName << toolTip.iconPixmap << toolTip.title << toolTip.description;
    argument.endStructure();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument, StatusNotifierToolTip &toolTip)
{
    argument.beginStructure();
    argument >> toolTip.iconName >> toolTip.iconPixmap >> toolTip.title >> toolTip.description;
    argument.endStructure();
    return argument;
}

StatusNotifier::StatusNotifier(QObject *parent)
    : QObject(parent), m_adaptor(new StatusNotifierItemAdaptor(this))
{
    qDBusRegisterMetaType<StatusNotifierPixmap>();
    qDBusRegisterMetaType<QList<StatusNotifierPixmap>>();
    qDBusRegisterMetaType<StatusNotifierToolTip>();

    QDBusConnection bus = QDBusConnection::sessionBus();
    const auto *busInterface = bus.interface();
    if (!bus.isConnected() || !busInterface)
        return;

    const QDBusReply<bool> watcherPresent = busInterface->isServiceRegistered(
        QStringLiteral("org.kde.StatusNotifierWatcher"));
    m_available = watcherPresent.isValid() && watcherPresent.value();
    m_serviceName = QStringLiteral("org.kde.StatusNotifierItem-%1-1")
                        .arg(QCoreApplication::applicationPid());
}

StatusNotifier::~StatusNotifier()
{
    if (m_serviceName.isEmpty() || !m_registered)
        return;
    QDBusConnection bus = QDBusConnection::sessionBus();
    bus.unregisterObject(QStringLiteral("/StatusNotifierItem"));
    bus.unregisterService(m_serviceName);
}

bool StatusNotifier::setVisible(bool visible)
{
    if (visible == m_visible)
        return true;
    if (!m_available)
        return false;

    QDBusConnection bus = QDBusConnection::sessionBus();
    if (visible && !m_registered) {
        if (!bus.registerService(m_serviceName))
            return false;
        if (!bus.registerObject(QStringLiteral("/StatusNotifierItem"), this,
                                QDBusConnection::ExportAdaptors)) {
            bus.unregisterService(m_serviceName);
            return false;
        }
        m_registered = true;

        QDBusInterface watcher(QStringLiteral("org.kde.StatusNotifierWatcher"),
                               QStringLiteral("/StatusNotifierWatcher"),
                               QStringLiteral("org.kde.StatusNotifierWatcher"), bus);
        const QDBusMessage reply = watcher.call(QStringLiteral("RegisterStatusNotifierItem"), m_serviceName);
        if (reply.type() == QDBusMessage::ErrorMessage) {
            bus.unregisterObject(QStringLiteral("/StatusNotifierItem"));
            bus.unregisterService(m_serviceName);
            m_registered = false;
            return false;
        }
    } else if (!visible && m_registered) {
        bus.unregisterObject(QStringLiteral("/StatusNotifierItem"));
        bus.unregisterService(m_serviceName);
        m_registered = false;
    }

    m_visible = visible;
    emit visibleChanged();
    if (m_registered)
        emit m_adaptor->NewStatus(visible ? QStringLiteral("Active") : QStringLiteral("Passive"));
    return true;
}

bool StatusNotifier::showNotification(const QString &title, const QString &body) const
{
    if (!notificationServiceAvailable())
        return false;
    const QDBusConnection bus = QDBusConnection::sessionBus();
    QDBusMessage message = QDBusMessage::createMethodCall(
        QStringLiteral("org.freedesktop.Notifications"),
        QStringLiteral("/org/freedesktop/Notifications"),
        QStringLiteral("org.freedesktop.Notifications"), QStringLiteral("Notify"));
    message << QStringLiteral("VLC Neo") << quint32(0) << QStringLiteral("vlc")
            << title << body << QStringList{} << QVariantMap{} << qint32(4000);
    bus.asyncCall(message);
    return true;
}

bool StatusNotifier::notificationServiceAvailable() const
{
    const QDBusConnection bus = QDBusConnection::sessionBus();
    const auto *busInterface = bus.interface();
    if (!bus.isConnected() || !busInterface)
        return false;
    const QDBusReply<bool> servicePresent = busInterface->isServiceRegistered(
        QStringLiteral("org.freedesktop.Notifications"));
    return servicePresent.isValid() && servicePresent.value();
}

StatusNotifierItemAdaptor::StatusNotifierItemAdaptor(StatusNotifier *parent)
    : QDBusAbstractAdaptor(parent)
{
    setAutoRelaySignals(false);
}

QString StatusNotifierItemAdaptor::status() const
{
    const auto *item = qobject_cast<const StatusNotifier *>(parent());
    return item && item->visible() ? QStringLiteral("Active") : QStringLiteral("Passive");
}

QList<StatusNotifierPixmap> StatusNotifierItemAdaptor::iconPixmap() const
{
    return trayPixmaps();
}

StatusNotifierToolTip StatusNotifierItemAdaptor::toolTip() const
{
    return {iconName(), iconPixmap(), title(), QStringLiteral("Show VLC Neo")};
}

void StatusNotifierItemAdaptor::Activate(int, int)
{
    if (auto *item = qobject_cast<StatusNotifier *>(parent()))
        emit item->activated();
}

void StatusNotifierItemAdaptor::SecondaryActivate(int, int)
{
    Activate(0, 0);
}

void StatusNotifierItemAdaptor::ContextMenu(int, int)
{
}

void StatusNotifierItemAdaptor::Scroll(int, const QString &)
{
}
