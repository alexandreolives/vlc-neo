// Queue data shared by the player backend and the QML list model.
#pragma once

#include <QString>

struct MediaQueueEntry {
    int id = -1;
    QString title;
    qint64 durationMs = 0;
    QString uri;
};
