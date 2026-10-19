cmake_minimum_required(VERSION 3.21)
project(vlc_neo VERSION 0.1.0 LANGUAGES CXX)

include(CTest)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE RelWithDebInfo)
endif()

find_package(PkgConfig REQUIRED)
pkg_check_modules(VLCPLUGIN REQUIRED IMPORTED_TARGET vlc-plugin>=3.0.0)
find_package(Qt6 6.6 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 Svg)

file(GLOB NEO_QML RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} qml/*.qml qml/singletons/*.qml)
file(GLOB NEO_ICONS RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} icons/*.svg)
file(GLOB NEO_FIGMA_ICONS RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} assets/figma-icons/*.svg)

add_library(neo_plugin MODULE
  src/module.cpp
  src/vout_display.cpp
  src/video_item.cpp
  src/player.cpp
  src/player_state_store.cpp
  src/vlc3_player_backend.cpp
  src/queue_model.cpp
  src/subtitle_matcher.cpp
  src/ui.cpp
  src/frame_store.hpp
  src/neo.hpp
  src/platform.hpp
  src/player.hpp
  src/player_state_store.hpp
  src/player_backend.hpp
  src/vlc3_player_backend.hpp
  src/media_queue_entry.hpp
  src/queue_model.hpp
  src/subtitle_matcher.hpp
  src/video_item.hpp
  src/vlc_headers.hpp
)

qt_add_resources(neo_plugin neo_assets
  PREFIX /neo
  FILES ${NEO_QML} ${NEO_ICONS} ${NEO_FIGMA_ICONS}
)

target_compile_definitions(neo_plugin PRIVATE
  MODULE_STRING="neo"
)
target_compile_options(neo_plugin PRIVATE -Wall -Wno-deprecated-declarations)
target_link_libraries(neo_plugin PRIVATE
  PkgConfig::VLCPLUGIN
  Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::QuickControls2 Qt6::Svg
)
set_target_properties(neo_plugin PROPERTIES PREFIX "lib" OUTPUT_NAME "neo_plugin")

if(BUILD_TESTING)
  add_executable(subtitle_matcher_test
    tests/subtitle_matcher_test.cpp
    src/subtitle_matcher.cpp
    src/subtitle_matcher.hpp
  )
  target_link_libraries(subtitle_matcher_test PRIVATE Qt6::Core)
  add_test(NAME subtitle_matcher COMMAND subtitle_matcher_test)

  add_executable(player_facade_test
    tests/player_facade_test.cpp
    src/player.cpp
    src/player_state_store.cpp
    src/queue_model.cpp
    src/subtitle_matcher.cpp
    src/player.hpp
    src/player_state_store.hpp
    src/player_backend.hpp
    src/queue_model.hpp
    src/subtitle_matcher.hpp
  )
  target_include_directories(player_facade_test PRIVATE src)
  target_link_libraries(player_facade_test PRIVATE Qt6::Core)
  add_test(NAME player_facade COMMAND player_facade_test)
  set_tests_properties(player_facade PROPERTIES
    ENVIRONMENT "XDG_CONFIG_HOME=${CMAKE_CURRENT_BINARY_DIR}/player-facade-test-config")

  add_executable(player_state_store_test
    tests/player_state_store_test.cpp
    src/player_state_store.cpp
    src/subtitle_matcher.cpp
    src/player_state_store.hpp
    src/subtitle_matcher.hpp
  )
  target_include_directories(player_state_store_test PRIVATE src)
  target_link_libraries(player_state_store_test PRIVATE Qt6::Core)
  add_test(NAME player_state_store COMMAND player_state_store_test)
  set_tests_properties(player_state_store PROPERTIES
    ENVIRONMENT "XDG_CONFIG_HOME=${CMAKE_CURRENT_BINARY_DIR}/player-state-store-test-config")

  add_executable(icon_provider_test tests/icon_provider_test.cpp)
  qt_add_resources(icon_provider_test icon_provider_test_assets
    PREFIX /neo
    BASE ${CMAKE_CURRENT_SOURCE_DIR}
    FILES ${NEO_ICONS} ${NEO_FIGMA_ICONS}
  )
  target_include_directories(icon_provider_test PRIVATE src)
  target_link_libraries(icon_provider_test PRIVATE Qt6::Core Qt6::Gui Qt6::Quick Qt6::Svg)
  add_test(NAME icon_provider COMMAND icon_provider_test)
  set_tests_properties(icon_provider PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
endif()

set(NEO_PLUGIN_DIR "$ENV{HOME}/.local/lib/vlc-neo/plugins/gui" CACHE PATH "Where libneo_plugin.so is installed")
install(TARGETS neo_plugin LIBRARY DESTINATION ${NEO_PLUGIN_DIR})
