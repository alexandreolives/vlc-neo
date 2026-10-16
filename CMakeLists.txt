cmake_minimum_required(VERSION 3.21)
project(vlc_neo VERSION 0.1.0 LANGUAGES CXX)

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

add_library(neo_plugin MODULE
  src/module.cpp
  src/vout_display.cpp
  src/video_item.cpp
  src/player.cpp
  src/ui.cpp
  src/frame_store.hpp
  src/neo.hpp
  src/platform.hpp
  src/player.hpp
  src/video_item.hpp
  src/vlc_headers.hpp
)

qt_add_resources(neo_plugin neo_assets
  PREFIX /neo
  FILES ${NEO_QML} ${NEO_ICONS}
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

set(NEO_PLUGIN_DIR "$ENV{HOME}/.local/lib/vlc-neo/plugins/gui" CACHE PATH "Where libneo_plugin.so is installed")
install(TARGETS neo_plugin LIBRARY DESTINATION ${NEO_PLUGIN_DIR})
