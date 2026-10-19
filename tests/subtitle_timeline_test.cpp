#include "../src/subtitle_timeline.hpp"

#include <QTemporaryFile>
#include <cstdio>

namespace {

bool expect(bool condition, const char *caseName)
{
    if (condition)
        return true;
    std::fprintf(stderr, "failed: %s\n", caseName);
    return false;
}

} // namespace

int main()
{
    const QString srt = QString::fromUtf8(
        "\xEF\xBB\xBF" "1\r\n00:00:01,2 --> 00:00:03,450\r\n<b>Hello</b> &amp; welcome\r\nthere\r\n\r\n"
        "2\r\n00:00:02.000 --> 00:00:04.000\r\nSecond cue\r\n\r\n"
        "3\r\n00:00:04,000 --> 00:00:04,000\r\nInvalid duration\r\n");
    const auto parsed = SubtitleTimeline::parse(srt);
    bool ok = expect(parsed.size() == 2, "parses valid cues and skips non-positive duration");
    ok &= expect(parsed.at(0).startMs == 1200 && parsed.at(0).endMs == 3450,
                 "normalizes decimal timestamps and CRLF");
    ok &= expect(parsed.at(0).text == QStringLiteral("Hello & welcome there"),
                 "strips markup and decodes common entities");
    const auto overlap = SubtitleTimeline::parse(QStringLiteral(
        "00:00:00,000 --> 00:00:10,000\nLong cue\n\n"
        "00:00:02,000 --> 00:00:03,000\nShort cue\n"));
    ok &= expect(overlap.size() == 2 && overlap.at(0).startMs < overlap.at(1).startMs,
                 "keeps overlapping cues in stable timeline order");

    const auto vtt = SubtitleTimeline::parse(QStringLiteral(
        "WEBVTT\n\nintro\n01:02.050 --> 01:04.9 align:start\nA <i>WebVTT</i> cue\n"));
    ok &= expect(vtt.size() == 1 && vtt.first().startMs == 62050 && vtt.first().endMs == 64900,
                 "parses WebVTT timestamps and cue settings");
    ok &= expect(vtt.size() == 1 && vtt.first().text == QStringLiteral("A WebVTT cue"),
                 "cleans WebVTT inline markup");

    const auto ass = SubtitleTimeline::parse(QStringLiteral(
        "[Script Info]\nTitle: Example\n[Events]\n"
        "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n"
        "Dialogue: 0,0:00:01.20,0:00:02.50,Default,,0,0,0,,{\\i1}Hello, world\\Nagain\n"));
    ok &= expect(ass.size() == 1 && ass.first().startMs == 1200 && ass.first().endMs == 2500,
                 "parses ASS event timing");
    ok &= expect(ass.size() == 1 && ass.first().text == QStringLiteral("Hello, world again"),
                 "preserves commas and cleans ASS dialogue tags");

    const auto limited = SubtitleTimeline::parse(QStringLiteral(
        "00:00:00,000 --> 00:00:01,000\nOne\n\n00:00:01,000 --> 00:00:02,000\nTwo\n"), 1);
    ok &= expect(limited.size() == 1, "respects the cue-count cap");
    ok &= expect(SubtitleTimeline::parse(QString(), 100).isEmpty(), "empty subtitles produce no cues");

    QTemporaryFile oversized;
    const bool oversizedFileReady = oversized.open() && oversized.resize(SubtitleTimeline::MaxFileBytes + 1);
    ok &= expect(oversizedFileReady && SubtitleTimeline::parseFile(oversized.fileName()).isEmpty(),
                 "rejects subtitle files above the byte cap");
    return ok ? 0 : 1;
}
