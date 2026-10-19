#pragma once

#include <QList>
#include <QString>

struct SubtitleCue
{
    qint64 startMs = 0;
    qint64 endMs = 0;
    QString text;
};

namespace SubtitleTimeline {

// Limits keep malformed or unusually large subtitle files from consuming
// unbounded memory. Parsing itself is pure and can run on a worker thread.
constexpr qint64 MaxFileBytes = 16 * 1024 * 1024;
constexpr qsizetype MaxCueCount = 100000;

QList<SubtitleCue> parse(const QString &contents, qsizetype maxCueCount = MaxCueCount);
QList<SubtitleCue> parseFile(const QString &path);

} // namespace SubtitleTimeline
