#include "waveform_decode_policy.hpp"

#include <iostream>

int main()
{
    using WaveformDecodePolicy::timeoutMs;
    if (timeoutMs(0) != 20'000 || timeoutMs(-1) != 20'000) {
        std::cerr << "unknown waveform duration must use the base timeout\n";
        return 1;
    }
    if (timeoutMs(10) != 40'000 || timeoutMs(60) != 140'000) {
        std::cerr << "waveform timeout must scale with media duration\n";
        return 1;
    }
    if (timeoutMs(3600) != 600'000 || timeoutMs(24 * 60 * 60) != 600'000) {
        std::cerr << "waveform timeout must stay within the ten-minute bound\n";
        return 1;
    }
    std::cout << "PASS waveform decode timeout scales with duration and stays bounded\n";
    return 0;
}
