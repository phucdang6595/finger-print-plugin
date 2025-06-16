#include "include/fingerprint/fingerprint_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "fingerprint_plugin.h"

void FingerprintPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  fingerprint::FingerprintPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
