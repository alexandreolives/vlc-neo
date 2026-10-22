#pragma once

#include <QCache>
#include <QImage>
#include <QString>

// The thumbnail service serializes access with its cache mutex. Keeping this
// small wrapper separate makes the memory bound and eviction policy testable.
class BoundedImageCache
{
public:
    static constexpr int kMaxCostKiB = 16 * 1024;

    BoundedImageCache() { m_cache.setMaxCost(kMaxCostKiB); }

    const QImage *object(const QString &key) { return m_cache.object(key); }

    void insert(const QString &key, const QImage &image)
    {
        const int costKiB = qMax(1, int((image.sizeInBytes() + 1023) / 1024));
        m_cache.insert(key, new QImage(image), costKiB);
    }

    bool contains(const QString &key) const { return m_cache.contains(key); }
    int totalCostKiB() const { return m_cache.totalCost(); }
    int maxCostKiB() const { return m_cache.maxCost(); }

private:
    QCache<QString, QImage> m_cache;
};
