#include "vlc_addon_uuid.hpp"

#include <QCoreApplication>

#include <cstdio>
#include <cstdlib>

namespace {

bool expect(bool condition, const char *name)
{
    if (condition)
        return true;
    std::fprintf(stderr, "failed: %s\n", name);
    return false;
}

} // namespace

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    bool ok = true;

    const QString repositoryId = QStringLiteral("0aed47f9-5f32ed-f8cc-344b-a07d344dfc");
    addon_uuid_t id{};
    ok &= expect(parseVlcAddonUuid(repositoryId, id), "parses a VLC repository add-on identifier");
    char *formatted = addons_uuid_to_psz(&id);
    ok &= expect(formatted && repositoryId == QString::fromLatin1(formatted),
                 "round-trips an identifier using VLC's 8-6-4-4-10 group sizes");
    std::free(formatted);

    addon_uuid_t invalid{};
    ok &= expect(!parseVlcAddonUuid(QStringLiteral("0aed47f9-5f32-f8cc-344b-a07d344dfc"), invalid),
                 "rejects separators in standard UUID positions");
    ok &= expect(!parseVlcAddonUuid(QStringLiteral("0aed47f9-5f32ed-f8cc-344b-a07d344dfg"), invalid),
                 "rejects non-hexadecimal digits");
    ok &= expect(!parseVlcAddonUuid(repositoryId + QLatin1Char('0'), invalid),
                 "rejects trailing characters");

    return ok ? 0 : 1;
}
