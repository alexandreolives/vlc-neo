#pragma once

#include <memory>

#include "player_backend.hpp"
#include "vlc_headers.hpp"

std::unique_ptr<PlayerBackend> makeVlc3PlayerBackend(intf_thread_t *intf, playlist_t *playlist);
