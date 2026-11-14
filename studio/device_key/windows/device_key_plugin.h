#ifndef FLUTTER_PLUGIN_DEVICE_KEY_PLUGIN_H_
#define FLUTTER_PLUGIN_DEVICE_KEY_PLUGIN_H_

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace device_key {

// Device keys on Windows (ADR 0050): a Windows Hello key credential
// (`KeyCredentialManager`, RSA-2048 in the TPM or Hello's software store).
class DeviceKeyPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  explicit DeviceKeyPlugin(
      std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel);

  virtual ~DeviceKeyPlugin();

  // Disallow copy and assign.
  DeviceKeyPlugin(const DeviceKeyPlugin &) = delete;
  DeviceKeyPlugin &operator=(const DeviceKeyPlugin &) = delete;

 private:
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace device_key

#endif  // FLUTTER_PLUGIN_DEVICE_KEY_PLUGIN_H_
