#pragma once

#include <QDBusAbstractAdaptor>
#include <QDBusArgument>
#include <QDBusObjectPath>
#include <QObject>
#include <QByteArray>
#include <QList>
#include <QString>

struct StatusNotifierPixmap
{
    qint32 width = 0;
    qint32 height = 0;
    QByteArray data;
};

QDBusArgument &operator<<(QDBusArgument &argument, const StatusNotifierPixmap &pixmap);
const QDBusArgument &operator>>(const QDBusArgument &argument, StatusNotifierPixmap &pixmap);

struct StatusNotifierToolTip
{
    QString iconName;
    QList<StatusNotifierPixmap> iconPixmap;
    QString title;
    QString description;
};

QDBusArgument &operator<<(QDBusArgument &argument, const StatusNotifierToolTip &toolTip);
const QDBusArgument &operator>>(const QDBusArgument &argument, StatusNotifierToolTip &toolTip);

Q_DECLARE_METATYPE(StatusNotifierPixmap)
Q_DECLARE_METATYPE(QList<StatusNotifierPixmap>)
Q_DECLARE_METATYPE(StatusNotifierToolTip)

class StatusNotifierItemAdaptor;

// Linux desktop tray/notification bridge that does not require QApplication or Qt Widgets.
class StatusNotifier final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available CONSTANT)
    Q_PROPERTY(bool notificationServiceAvailable READ notificationServiceAvailable CONSTANT)
    Q_PROPERTY(bool visible READ visible NOTIFY visibleChanged)

public:
    explicit StatusNotifier(QObject *parent = nullptr);
    ~StatusNotifier() override;

    bool available() const { return m_available; }
    bool notificationServiceAvailable() const;
    bool visible() const { return m_visible; }

    Q_INVOKABLE bool setVisible(bool visible);
    Q_INVOKABLE bool showNotification(const QString &title, const QString &body) const;

signals:
    void activated();
    void visibleChanged();

private:
    friend class StatusNotifierItemAdaptor;
    bool m_available = false;
    bool m_visible = false;
    bool m_registered = false;
    QString m_serviceName;
    StatusNotifierItemAdaptor *m_adaptor = nullptr;
};

class StatusNotifierItemAdaptor final : public QDBusAbstractAdaptor
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.kde.StatusNotifierItem")
    Q_PROPERTY(QString Category READ category CONSTANT)
    Q_PROPERTY(QString Id READ id CONSTANT)
    Q_PROPERTY(QString Title READ title CONSTANT)
    Q_PROPERTY(quint32 WindowId READ windowId CONSTANT)
    Q_PROPERTY(QString Status READ status)
    Q_PROPERTY(QString IconName READ iconName CONSTANT)
    Q_PROPERTY(QList<StatusNotifierPixmap> IconPixmap READ iconPixmap CONSTANT)
    Q_PROPERTY(QString OverlayIconName READ overlayIconName CONSTANT)
    Q_PROPERTY(QList<StatusNotifierPixmap> OverlayIconPixmap READ overlayIconPixmap CONSTANT)
    Q_PROPERTY(QString AttentionIconName READ attentionIconName CONSTANT)
    Q_PROPERTY(QList<StatusNotifierPixmap> AttentionIconPixmap READ attentionIconPixmap CONSTANT)
    Q_PROPERTY(QString AttentionMovieName READ attentionMovieName CONSTANT)
    Q_PROPERTY(StatusNotifierToolTip ToolTip READ toolTip CONSTANT)
    Q_PROPERTY(bool ItemIsMenu READ itemIsMenu CONSTANT)
    Q_PROPERTY(QDBusObjectPath Menu READ menu CONSTANT)

public:
    explicit StatusNotifierItemAdaptor(StatusNotifier *parent);

    QString category() const { return QStringLiteral("ApplicationStatus"); }
    QString id() const { return QStringLiteral("vlc-neo"); }
    QString title() const { return QStringLiteral("VLC Neo"); }
    quint32 windowId() const { return 0; }
    QString status() const;
    QString iconName() const { return QStringLiteral("vlc"); }
    QList<StatusNotifierPixmap> iconPixmap() const;
    QString overlayIconName() const { return {}; }
    QList<StatusNotifierPixmap> overlayIconPixmap() const { return {}; }
    QString attentionIconName() const { return {}; }
    QList<StatusNotifierPixmap> attentionIconPixmap() const { return {}; }
    QString attentionMovieName() const { return {}; }
    StatusNotifierToolTip toolTip() const;
    bool itemIsMenu() const { return false; }
    QDBusObjectPath menu() const { return QDBusObjectPath(QStringLiteral("/NO_DBUSMENU")); }

public slots:
    void Activate(int x, int y);
    void SecondaryActivate(int x, int y);
    void ContextMenu(int x, int y);
    void Scroll(int delta, const QString &orientation);

signals:
    void NewTitle();
    void NewIcon();
    void NewAttentionIcon();
    void NewOverlayIcon();
    void NewToolTip();
    void NewStatus(const QString &status);
};
