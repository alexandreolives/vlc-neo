#include "../src/subtitle_matcher.hpp"

#include <cstdio>

namespace {

bool expect(const QString &actual, const QString &expected, const char *caseName)
{
    if (actual == expected)
        return true;
    std::fprintf(stderr, "%s: expected '%s', got '%s'\n", caseName,
                 qPrintable(expected), qPrintable(actual));
    return false;
}

} // namespace

int main()
{
    using SubtitleMatcher::bestMatch;
    using SubtitleMatcher::episodeKey;
    using SubtitleMatcher::folderSettingsKey;

    bool ok = true;
    ok &= expect(episodeKey(QStringLiteral("My.Show.S01E05.1080p.mkv")), QStringLiteral("1:5"),
                 "season/episode key");
    ok &= expect(episodeKey(QStringLiteral("myshow_1x05_ar.srt")), QStringLiteral("1:5"),
                 "crossed season/episode key");
    ok &= expect(episodeKey(QStringLiteral("Show - 05 - 720p.srt")), QStringLiteral("5"),
                 "episode number without season");
    ok &= expect(episodeKey(QStringLiteral("Movie.2024.1080p.mkv")), QString(),
                 "resolution and year are ignored");

    ok &= expect(bestMatch(QStringLiteral("My.Show.S01E02.1080p.mkv"),
                           {QStringLiteral("myshow_1x01_ar.srt"), QStringLiteral("myshow_1x02_ar.srt")}),
                 QStringLiteral("myshow_1x02_ar.srt"), "episode-specific match");
    ok &= expect(bestMatch(QStringLiteral("Film.S01E05.mkv"),
                           {QStringLiteral("episode_1x05.srt"), QStringLiteral("Film.S01E05.en.srt")}),
                 QStringLiteral("Film.S01E05.en.srt"), "filename match outranks generic episode match");
    ok &= expect(bestMatch(QStringLiteral("Film.S01E05.mkv"), {QStringLiteral("subtitles.srt")}),
                 QString(), "unmatched subtitle");

    const QString key = folderSettingsKey(QStringLiteral("/home/test/Show"));
    ok &= key.startsWith(QStringLiteral("subfolders/"))
        && expect(folderSettingsKey(QStringLiteral("/home/test/Show")), key, "stable folder settings key");
    return ok ? 0 : 1;
}
