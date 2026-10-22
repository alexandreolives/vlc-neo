#pragma once

#include <QByteArray>
#include <QString>

#include <cctype>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>

#include <vlc_common.h>
#include <vlc_addons.h>

inline bool parseVlcAddonUuid(const QString &uuid, addon_uuid_t &id)
{
    const QByteArray encoded = uuid.toLatin1();
    if (encoded.size() != ADDON_UUID_PSZ_SIZE)
        return false;

    for (int i = 0; i < encoded.size(); ++i) {
        const bool separator = i == 8 || i == 15 || i == 20 || i == 25;
        if (separator) {
            if (encoded.at(i) != '-')
                return false;
        } else if (!std::isxdigit(static_cast<unsigned char>(encoded.at(i)))) {
            return false;
        }
    }
    return addons_uuid_read(encoded.constData(), &id);
}
