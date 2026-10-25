#pragma once

#include <QtGlobal>

namespace WaveformDecodePolicy {

constexpr int timeoutMs(qint64 durationSeconds)
{
    constexpr int baseTimeoutMs = 20'000;
    constexpr int maxTimeoutMs = 10 * 60'000;
    constexpr qint64 extraMsPerSecond = 2'000;

    if (durationSeconds <= 0)
        return baseTimeoutMs;
    if (durationSeconds >= (maxTimeoutMs - baseTimeoutMs) / extraMsPerSecond)
        return maxTimeoutMs;
    return baseTimeoutMs + int(durationSeconds * extraMsPerSecond);
}

} // namespace WaveformDecodePolicy
