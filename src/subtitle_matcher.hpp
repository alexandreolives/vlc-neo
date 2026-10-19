// Pure filename matching helpers used by the VLC player bridge.
#pragma once

#include <QString>
#include <QStringList>

namespace SubtitleMatcher {

QString episodeKey(const QString &fileName);
QString bestMatch(const QString &mediaFileName, const QStringList &subtitleFileNames);
QString folderSettingsKey(const QString &folder);

} // namespace SubtitleMatcher
