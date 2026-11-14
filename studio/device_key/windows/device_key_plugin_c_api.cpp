#include "include/device_key/device_key_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "device_key_plugin.h"

void DeviceKeyPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  device_key::DeviceKeyPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
