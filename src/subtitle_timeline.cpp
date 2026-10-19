#include "subtitle_timeline.hpp"

#include <QFile>
#include <QRegularExpression>
#include <algorithm>

namespace {

const QRegularExpression &timingExpression()
{
    static const QRegularExpression expression(
        QStringLiteral(R"(^\s*(\d{1,2}:)?(\d{1,2}:)?(\d{2}[,.]\d{1,3})\s*-->\s*(\d{1,2}:)?(\d{1,2}:)?(\d{2}[,.]\d{1,3})(?:\s+.*)?\s*$)"));
    return expression;
}

qint64 toMilliseconds(const QString &first, const QString &second, const QString &last)
{
    QStringList parts;
    if (!first.isEmpty()) parts.append(first.left(first.size() - 1));
    if (!second.isEmpty()) parts.append(second.left(second.size() - 1));
    parts.append(last);
    const QStringList secondsAndMillis = parts.takeLast().split(QRegularExpression(QStringLiteral("[,.]")));
    QString millis = secondsAndMillis.value(1);
    while (millis.size() < 3)
        millis.append(QLatin1Char('0'));
    const qint64 seconds = secondsAndMillis.value(0).toLongLong();
    const qint64 minutes = parts.isEmpty() ? 0 : parts.constLast().toLongLong();
    const qint64 hours = parts.size() < 2 ? 0 : parts.first().toLongLong();
    return ((hours * 60 + minutes) * 60 + seconds) * 1000 + millis.toLongLong();
}

QString cleanText(const QStringList &lines)
{
    static const QRegularExpression markup(QStringLiteral("<[^>]*>|\\{\\\\[^}]*\\}"));
    QString text = lines.join(QLatin1Char(' ')).simplified();
    text.replace(QStringLiteral("\\N"), QStringLiteral(" "));
    text.replace(QStringLiteral("\\n"), QStringLiteral(" "));
    text.replace(QStringLiteral("\\h"), QStringLiteral(" "));
    text.remove(markup);
    text.replace(QStringLiteral("&nbsp;"), QStringLiteral(" "), Qt::CaseInsensitive);
    text.replace(QStringLiteral("&amp;"), QStringLiteral("&"), Qt::CaseInsensitive);
    text.replace(QStringLiteral("&lt;"), QStringLiteral("<"), Qt::CaseInsensitive);
    text.replace(QStringLiteral("&gt;"), QStringLiteral(">"), Qt::CaseInsensitive);
    text.replace(QStringLiteral("&quot;"), QStringLiteral("\""), Qt::CaseInsensitive);
    return text.simplified();
}

QList<SubtitleCue> parseAss(const QStringList &lines, qsizetype maxCueCount)
{
    QList<SubtitleCue> cues;
    QStringList fields;
    int startColumn = -1, endColumn = -1, textColumn = -1;
    for (const QString &line : lines) {
        const QString trimmed = line.trimmed();
        if (trimmed.startsWith(QStringLiteral("Format:"), Qt::CaseInsensitive)) {
            fields = trimmed.mid(7).split(QLatin1Char(','));
            for (qsizetype i = 0; i < fields.size(); ++i) {
                const QString field = fields.at(i).trimmed().toLower();
                if (field == QLatin1String("start")) startColumn = int(i);
                else if (field == QLatin1String("end")) endColumn = int(i);
                else if (field == QLatin1String("text")) textColumn = int(i);
            }
            continue;
        }
        if (!trimmed.startsWith(QStringLiteral("Dialogue:"), Qt::CaseInsensitive)
            || startColumn < 0 || endColumn < 0 || textColumn < 0 || cues.size() >= maxCueCount)
            continue;

        const QString payload = trimmed.mid(9).trimmed();
        QStringList columns;
        qsizetype offset = 0;
        const int commaCount = std::max(startColumn, std::max(endColumn, textColumn));
        for (int column = 0; column < commaCount; ++column) {
            const qsizetype comma = payload.indexOf(QLatin1Char(','), offset);
            if (comma < 0)
                break;
            columns.append(payload.mid(offset, comma - offset));
            offset = comma + 1;
        }
        if (columns.size() != commaCount)
            continue;
        columns.append(payload.mid(offset));
        if (columns.size() <= std::max(startColumn, std::max(endColumn, textColumn)))
            continue;

        const auto parseAssTime = [](const QString &value) {
            const QStringList parts = value.trimmed().split(QLatin1Char(':'));
            if (parts.size() != 3)
                return qint64(-1);
            const qint64 hours = parts.at(0).toLongLong();
            const qint64 minutes = parts.at(1).toLongLong();
            const QStringList secondsAndFraction = parts.at(2).split(QLatin1Char('.'));
            if (secondsAndFraction.size() != 2)
                return qint64(-1);
            QString hundredths = secondsAndFraction.at(1);
            while (hundredths.size() < 2)
                hundredths.append(QLatin1Char('0'));
            return ((hours * 60 + minutes) * 60 + secondsAndFraction.at(0).toLongLong()) * 1000
                + hundredths.left(2).toLongLong() * 10;
        };

        const qint64 start = parseAssTime(columns.at(startColumn));
        const qint64 end = parseAssTime(columns.at(endColumn));
        const QString text = cleanText({columns.at(textColumn)});
        if (start >= 0 && end > start && !text.isEmpty())
            cues.append({start, end, text});
    }
    std::stable_sort(cues.begin(), cues.end(), [](const SubtitleCue &a, const SubtitleCue &b) {
        return a.startMs < b.startMs;
    });
    return cues;
}

} // namespace

QList<SubtitleCue> SubtitleTimeline::parse(const QString &contents, qsizetype maxCueCount)
{
    QList<SubtitleCue> cues;
    if (maxCueCount <= 0 || contents.isEmpty())
        return cues;

    QString normalized = contents;
    if (!normalized.isEmpty() && normalized.front() == QChar::ByteOrderMark)
        normalized.remove(0, 1);
    const QStringList lines = normalized.split(QLatin1Char('\n'));
    const bool ass = std::any_of(lines.cbegin(), lines.cend(), [](const QString &line) {
        return line.trimmed().startsWith(QStringLiteral("[Events]"), Qt::CaseInsensitive);
    });
    if (ass)
        return parseAss(lines, maxCueCount);
    const QRegularExpression &timing = timingExpression();

    for (qsizetype i = 0; i < lines.size() && cues.size() < maxCueCount; ++i) {
        const auto match = timing.match(lines.at(i).trimmed());
        if (!match.hasMatch())
            continue;

        const qint64 start = toMilliseconds(match.captured(1), match.captured(2), match.captured(3));
        const qint64 end = toMilliseconds(match.captured(4), match.captured(5), match.captured(6));
        if (end <= start)
            continue;

        QStringList textLines;
        for (++i; i < lines.size() && !lines.at(i).trimmed().isEmpty(); ++i) {
            if (timing.match(lines.at(i).trimmed()).hasMatch()) {
                --i;
                break;
            }
            textLines.append(lines.at(i).trimmed());
        }
        const QString text = cleanText(textLines);
        if (!text.isEmpty())
            cues.append({start, end, text});
    }

    std::stable_sort(cues.begin(), cues.end(), [](const SubtitleCue &a, const SubtitleCue &b) {
        return a.startMs < b.startMs;
    });
    return cues;
}

QList<SubtitleCue> SubtitleTimeline::parseFile(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly) || file.size() > MaxFileBytes)
        return {};
    const QByteArray bytes = file.read(MaxFileBytes + 1);
    if (bytes.size() > MaxFileBytes)
        return {};
    return parse(QString::fromUtf8(bytes));
}
