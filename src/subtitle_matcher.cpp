#include "subtitle_matcher.hpp"

#include <QCryptographicHash>
#include <QFileInfo>
#include <QRegularExpression>

namespace SubtitleMatcher {

QString episodeKey(const QString &fileName)
{
    static const QRegularExpression seasonEpisode(QStringLiteral("[Ss](\\d{1,2})[ ._-]?[Ee](\\d{1,3})"));
    static const QRegularExpression crossed(QStringLiteral("(\\d{1,2})x(\\d{1,3})"));
    static const QRegularExpression noise(QStringLiteral("(\\d{3,4}p|[xh]\\.?26[45]|\\b(19|20)\\d{2}\\b|\\d+bit)"),
                                          QRegularExpression::CaseInsensitiveOption);
    static const QRegularExpression number(QStringLiteral("(\\d{1,3})"));

    const QString base = QFileInfo(fileName).completeBaseName();
    QRegularExpressionMatch match = seasonEpisode.match(base);
    if (!match.hasMatch())
        match = crossed.match(base);
    if (match.hasMatch())
        return QStringLiteral("%1:%2").arg(match.captured(1).toInt()).arg(match.captured(2).toInt());

    QString cleaned = base;
    cleaned.remove(noise);
    QString last;
    auto it = number.globalMatch(cleaned);
    while (it.hasNext())
        last = it.next().captured(1);
    return last.isEmpty() ? QString() : QString::number(last.toInt());
}

QString bestMatch(const QString &mediaFileName, const QStringList &subtitleFileNames)
{
    const QString wanted = episodeKey(mediaFileName);
    const QString mediaBase = QFileInfo(mediaFileName).completeBaseName();
    QString best;
    for (const QString &fileName : subtitleFileNames) {
        if (QFileInfo(fileName).completeBaseName().startsWith(mediaBase, Qt::CaseInsensitive))
            return fileName;
        if (best.isEmpty() && !wanted.isEmpty() && episodeKey(fileName) == wanted)
            best = fileName;
    }
    return best;
}

QString folderSettingsKey(const QString &folder)
{
    return QStringLiteral("subfolders/")
        + QString::fromLatin1(QCryptographicHash::hash(folder.toUtf8(), QCryptographicHash::Md5).toHex());
}

} // namespace SubtitleMatcher
