// UI-facing playlist model, kept separate from the VLC player bridge.
#pragma once

#include <QAbstractListModel>

class QueueModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    enum Roles { IdRole = Qt::UserRole + 1, TitleRole, DurationRole, CurrentRole, UriRole };

    struct Entry {
        int id;
        QString title;
        qint64 durationMs;
        QString uri;
    };

    explicit QueueModel(QObject *parent = nullptr) : QAbstractListModel(parent) {}
    int rowCount(const QModelIndex & = QModelIndex()) const override { return m_entries.size(); }
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const { return m_entries.size(); }
    void reset(QList<Entry> entries, int currentId);
    void setCurrentId(int id);
    int indexOfId(int id) const;
    const QList<Entry> &entries() const { return m_entries; }

signals:
    void countChanged();

private:
    QList<Entry> m_entries;
    int m_currentId = -1;
};
