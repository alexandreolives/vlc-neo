#pragma once

#include <QAbstractListModel>
#include <QFutureWatcher>
#include <QObject>
#include <QTimer>
#include <QStringList>
#include <QVariant>
#include <QUrl>

struct LibraryScanResult {
    bool ok = false;
    int indexed = 0;
    QString error;
};

class MediaLibraryModel final : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ itemCount NOTIFY countChanged)
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
    Q_PROPERTY(bool stale READ stale NOTIFY staleChanged)
    Q_PROPERTY(QString loadError READ loadError NOTIFY loadErrorChanged)
    Q_PROPERTY(QString view READ view WRITE setView NOTIFY viewChanged)
    Q_PROPERTY(QString search READ search WRITE setSearch NOTIFY searchChanged)
    Q_PROPERTY(bool grouped READ grouped NOTIFY viewChanged)

public:
    enum Role {
        TitleRole = Qt::UserRole + 1,
        ArtistRole,
        AlbumRole,
        GenreRole,
        PathRole,
        ArtworkRole,
        DurationRole,
        CountRole,
        KindRole,
        GroupRole
    };

    explicit MediaLibraryModel(QObject *parent = nullptr);
    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    QString view() const { return m_view; }
    QString search() const { return m_search; }
    bool grouped() const { return !m_groupColumn.isEmpty(); }
    bool loading() const { return m_loading; }
    bool stale() const { return m_stale; }
    QString loadError() const { return m_loadError; }
    Q_INVOKABLE int itemCount() const { return m_items.size(); }
    Q_INVOKABLE QVariantMap itemAt(int row) const;
    void setDatabasePath(QString path);
    void setView(const QString &view);
    void setSearch(const QString &search);
    Q_INVOKABLE void selectGroup(int row);
    Q_INVOKABLE void clearGroup();
    bool reload();

signals:
    void countChanged();
    void loadingChanged();
    void staleChanged();
    void loadErrorChanged();
    void viewChanged();
    void searchChanged();
    void loadFailed(const QString &message);

private:
    struct Item {
        QString title, artist, album, genre, path, artwork, kind;
        qint64 duration = 0;
        int count = 0;
        bool group = false;
    };
    struct QueryResult {
        QList<Item> items;
        QString error;
        quint64 revision = 0;
    };
    static QueryResult queryDatabase(const QString &databasePath, const QString &view,
                                     const QString &search, const QString &groupColumn,
                                     const QString &groupValue, const QString &groupArtist,
                                     quint64 revision);
    void startReload();
    void setStale(bool stale);
    void setLoadError(const QString &error);
    QString m_databasePath;
    QString m_view = QStringLiteral("tracks");
    QString m_search;
    QString m_groupColumn;
    QString m_groupValue;
    QString m_groupArtist;
    QList<Item> m_items;
    QFutureWatcher<QueryResult> m_queryWatcher;
    QTimer m_queryTimer;
    quint64 m_queryRevision = 0;
    bool m_loading = false;
    bool m_stale = false;
    QString m_loadError;
};

class MediaLibrary final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QObject *model READ model CONSTANT)
    Q_PROPERTY(QStringList roots READ roots NOTIFY rootsChanged)
    Q_PROPERTY(bool scanning READ scanning NOTIFY scanningChanged)
    Q_PROPERTY(int indexedCount READ indexedCount NOTIFY indexedCountChanged)
    Q_PROPERTY(QString databasePath READ databasePath CONSTANT)

public:
    explicit MediaLibrary(QObject *parent = nullptr);
    QObject *model() { return &m_model; }
    QStringList roots() const { return m_roots; }
    bool scanning() const { return m_scanning; }
    int indexedCount() const { return m_indexedCount; }
    QString databasePath() const { return m_databasePath; }

    Q_INVOKABLE bool addFolder(const QUrl &folder);
    Q_INVOKABLE bool removeFolder(const QUrl &folder);
    Q_INVOKABLE bool clearLibrary();
    Q_INVOKABLE void refresh();

signals:
    void rootsChanged();
    void scanningChanged();
    void indexedCountChanged();
    void notify(const QString &message);

private:
    bool initializeDatabase();
    void reloadRoots();
    void startNextScan();
    void scanFinished();
    void cleanupArtwork();

    QString m_databasePath;
    QString m_artworkDirectory;
    QStringList m_roots;
    QStringList m_pendingRoots;
    QString m_activeRoot;
    MediaLibraryModel m_model;
    QFutureWatcher<LibraryScanResult> m_watcher;
    int m_indexedCount = 0;
    bool m_scanning = false;
};
