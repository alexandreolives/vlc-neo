#include "queue_model.hpp"

QVariant QueueModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_entries.size())
        return {};
    const MediaQueueEntry &entry = m_entries.at(index.row());
    switch (role) {
    case IdRole: return entry.id;
    case TitleRole: return entry.title;
    case DurationRole: return entry.durationMs;
    case CurrentRole: return entry.id == m_currentId;
    case UriRole: return entry.uri;
    default: return {};
    }
}

QHash<int, QByteArray> QueueModel::roleNames() const
{
    return {{IdRole, "itemId"}, {TitleRole, "title"}, {DurationRole, "duration"},
            {CurrentRole, "current"}, {UriRole, "uri"}};
}

void QueueModel::reset(QList<MediaQueueEntry> entries, int currentId)
{
    beginResetModel();
    m_entries = std::move(entries);
    m_currentId = currentId;
    endResetModel();
    emit countChanged();
}

void QueueModel::setCurrentId(int id)
{
    if (id == m_currentId)
        return;
    const int oldRow = indexOfId(m_currentId);
    m_currentId = id;
    const int newRow = indexOfId(id);
    if (oldRow >= 0)
        emit dataChanged(index(oldRow), index(oldRow), {CurrentRole});
    if (newRow >= 0)
        emit dataChanged(index(newRow), index(newRow), {CurrentRole});
}

int QueueModel::indexOfId(int id) const
{
    for (int i = 0; i < m_entries.size(); ++i)
        if (m_entries.at(i).id == id)
            return i;
    return -1;
}
