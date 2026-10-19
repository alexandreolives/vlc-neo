// UI-facing playlist model, kept separate from the VLC player bridge.
#pragma once

#include <QAbstractListModel>

#include "media_queue_entry.hpp"

class QueueModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    enum Roles { IdRole = Qt::UserRole + 1, TitleRole, DurationRole, CurrentRole, UriRole };

    explicit QueueModel(QObject *parent = nullptr) : QAbstractListModel(parent) {}
    int rowCount(const QModelIndex & = QModelIndex()) const override { return m_entries.size(); }
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const { return m_entries.size(); }
    void reset(QList<MediaQueueEntry> entries, int currentId);
    void setCurrentId(int id);
    int indexOfId(int id) const;
    const QList<MediaQueueEntry> &entries() const { return m_entries; }

signals:
    void countChanged();

private:
    QList<MediaQueueEntry> m_entries;
    int m_currentId = -1;
};
