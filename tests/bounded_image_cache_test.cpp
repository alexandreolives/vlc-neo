#include "bounded_image_cache.hpp"

#include <QImage>
#include <QString>
#include <iostream>

int main()
{
    BoundedImageCache cache;
    const QImage thumbnail(256, 256, QImage::Format_Grayscale8);
    constexpr int costPerImageKiB = 64;
    const int entriesToInsert = cache.maxCostKiB() / costPerImageKiB + 1;

    for (int index = 0; index < entriesToInsert; ++index)
        cache.insert(QStringLiteral("frame-%1").arg(index), thumbnail);

    if (cache.totalCostKiB() > cache.maxCostKiB()) {
        std::cerr << "cache exceeded its configured memory cost\n";
        return 1;
    }
    if (cache.contains(QStringLiteral("frame-0"))) {
        std::cerr << "least-recently-used frame was not evicted\n";
        return 1;
    }
    if (!cache.contains(QStringLiteral("frame-%1").arg(entriesToInsert - 1))) {
        std::cerr << "most recent frame was evicted\n";
        return 1;
    }
    if (cache.totalCostKiB() != cache.maxCostKiB()) {
        std::cerr << "cache did not retain the newest frames up to its limit\n";
        return 1;
    }

    std::cout << "PASS bounded image cache: " << cache.totalCostKiB()
              << " KiB retained; oldest frame evicted\n";
    return 0;
}
