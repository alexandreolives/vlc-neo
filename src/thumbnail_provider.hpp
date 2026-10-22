#pragma once

#include <QQuickAsyncImageProvider>
#include <memory>

class ThumbnailProvider final : public QQuickAsyncImageProvider
{
public:
    class Service;

    ThumbnailProvider();
    ~ThumbnailProvider() override;

    QQuickImageResponse *requestImageResponse(const QString &id, const QSize &requestedSize) override;
    void waitForJobs();

private:
    std::shared_ptr<Service> m_service;
};
