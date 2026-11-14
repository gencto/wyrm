// Device keys on Windows (ADR 0050).
//
// Windows Hello's `KeyCredentialManager` makes RSA-2048 keys only, so the key
// is `alg: rs256`: the public key goes out as PKCS#1 `RSAPublicKey` DER, the
// signature is RSASSA-PKCS1-v1_5 with SHA-256 as `RequestSignAsync` returns
// it. Hello asks with its own text (face, finger or the Hello PIN), so the
// `reason` and `allowDeviceCredential` of the Dart side do not apply here.
//
// The calls are C++/WinRT coroutines started on the platform thread (an STA,
// COM initialised by the runner): awaiting a WinRT operation resumes on that
// same apartment, so every `MethodResult` is answered on the platform thread.

#include "device_key_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Security.Credentials.h>
#include <winrt/Windows.Security.Cryptography.Core.h>
#include <winrt/Windows.Security.Cryptography.h>
#include <winrt/Windows.Storage.Streams.h>

#include <chrono>
#include <cstdint>
#include <memory>
#include <string>
#include <thread>
#include <vector>

namespace device_key {

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using winrt::Windows::Security::Credentials::KeyCredentialCreationOption;
using winrt::Windows::Security::Credentials::KeyCredentialManager;
using winrt::Windows::Security::Credentials::KeyCredentialStatus;
using winrt::Windows::Security::Cryptography::CryptographicBuffer;
using winrt::Windows::Security::Cryptography::Core::
    CryptographicPublicKeyBlobType;
using winrt::Windows::Storage::Streams::IBuffer;

using Result = std::unique_ptr<flutter::MethodResult<EncodableValue>>;

constexpr char kChannel[] = "uk.gencto.device_key";
constexpr char kPrefix[] = "uk.gencto.device_key.";

winrt::hstring KeyName(const std::string &alias) {
  return winrt::to_hstring(std::string(kPrefix) + alias);
}

std::vector<uint8_t> Bytes(const IBuffer &buffer) {
  winrt::com_array<uint8_t> out;
  CryptographicBuffer::CopyToByteArray(buffer, out);
  return std::vector<uint8_t>(out.begin(), out.end());
}

// The result word of a status that is not Success.
const char *Code(KeyCredentialStatus status) {
  switch (status) {
    case KeyCredentialStatus::UserCanceled:
    case KeyCredentialStatus::UserPrefersPassword:
      return "cancelled";
    case KeyCredentialStatus::SecurityDeviceLocked:
      return "lockout";
    case KeyCredentialStatus::NotFound:
      return "invalidated";
    default:
      return "failed";
  }
}

std::string StatusText(KeyCredentialStatus status) {
  return "KeyCredentialStatus " + std::to_string(static_cast<int>(status));
}

// Hello's dialog of a desktop app can open behind the app's window; bring it
// forward for a few seconds. Best effort, never needed for correctness.
void RaiseHelloDialog() {
  std::thread([] {
    for (int i = 0; i < 30; ++i) {
      HWND dialog = ::FindWindowW(L"Credential Dialog Xaml Host", nullptr);
      if (dialog != nullptr) {
        ::SetForegroundWindow(dialog);
        return;
      }
      std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }
  }).detach();
}

const std::string *StringArg(const EncodableMap *args, const char *name) {
  if (args == nullptr) return nullptr;
  auto it = args->find(EncodableValue(name));
  if (it == args->end()) return nullptr;
  return std::get_if<std::string>(&it->second);
}

const std::vector<uint8_t> *BytesArg(const EncodableMap *args,
                                     const char *name) {
  if (args == nullptr) return nullptr;
  auto it = args->find(EncodableValue(name));
  if (it == args->end()) return nullptr;
  return std::get_if<std::vector<uint8_t>>(&it->second);
}

EncodableValue SignAnswer(const std::string &code,
                          const std::string &message = "") {
  return EncodableValue(EncodableMap{
      {EncodableValue("result"), EncodableValue(code)},
      {EncodableValue("message"), EncodableValue(message)},
  });
}

winrt::fire_and_forget IsAvailable(Result result) {
  bool supported = false;
  try {
    supported = co_await KeyCredentialManager::IsSupportedAsync();
  } catch (const winrt::hresult_error &) {
    supported = false;
  }
  result->Success(EncodableValue(EncodableMap{
      {EncodableValue("kind"),
       EncodableValue(supported ? "windowsHello" : "none")},
      {EncodableValue("name"), EncodableValue(supported ? "Windows Hello" : "")},
  }));
}

winrt::fire_and_forget Create(std::string alias, Result result) {
  std::string error_code = "failed";
  std::string error_message;
  try {
    if (!co_await KeyCredentialManager::IsSupportedAsync()) {
      result->Error("unavailable", "Windows Hello is not set up");
      co_return;
    }
    auto request = KeyCredentialManager::RequestCreateAsync(
        KeyName(alias), KeyCredentialCreationOption::ReplaceExisting);
    RaiseHelloDialog();
    auto created = co_await request;
    auto status = created.Status();
    if (status == KeyCredentialStatus::Success) {
      auto key = Bytes(created.Credential().RetrievePublicKey(
          CryptographicPublicKeyBlobType::Pkcs1RsaPublicKey));
      result->Success(EncodableValue(EncodableMap{
          {EncodableValue("alg"), EncodableValue("rs256")},
          {EncodableValue("publicKey"), EncodableValue(key)},
      }));
      co_return;
    }
    error_code = Code(status);
    if (error_code == "invalidated") {
      // NotFound at creation: Hello is not set up for this user.
      error_code = "unavailable";
    }
    error_message = StatusText(status);
  } catch (const winrt::hresult_error &e) {
    error_message = winrt::to_string(e.message());
  }
  result->Error(error_code, error_message);
}

winrt::fire_and_forget Sign(std::string alias, std::vector<uint8_t> bytes,
                            Result result) {
  std::string message;
  try {
    if (!co_await KeyCredentialManager::IsSupportedAsync()) {
      result->Success(SignAnswer("unavailable", "Windows Hello is not set up"));
      co_return;
    }
    auto opened = co_await KeyCredentialManager::OpenAsync(KeyName(alias));
    if (opened.Status() != KeyCredentialStatus::Success) {
      result->Success(
          SignAnswer(Code(opened.Status()), StatusText(opened.Status())));
      co_return;
    }
    auto data = CryptographicBuffer::CreateFromByteArray(
        winrt::array_view<const uint8_t>(bytes));
    auto request = opened.Credential().RequestSignAsync(data);
    RaiseHelloDialog();
    auto signed_ = co_await request;
    if (signed_.Status() != KeyCredentialStatus::Success) {
      result->Success(
          SignAnswer(Code(signed_.Status()), StatusText(signed_.Status())));
      co_return;
    }
    result->Success(EncodableValue(EncodableMap{
        {EncodableValue("result"), EncodableValue("signed")},
        {EncodableValue("signature"), EncodableValue(Bytes(signed_.Result()))},
    }));
    co_return;
  } catch (const winrt::hresult_error &e) {
    message = winrt::to_string(e.message());
  }
  result->Success(SignAnswer("failed", message));
}

winrt::fire_and_forget Delete(std::string alias, Result result) {
  try {
    co_await KeyCredentialManager::DeleteAsync(KeyName(alias));
  } catch (const winrt::hresult_error &) {
    // No such key: nothing to delete.
  }
  result->Success();
}

}  // namespace

// static
void DeviceKeyPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      registrar->messenger(), kChannel,
      &flutter::StandardMethodCodec::GetInstance());
  auto plugin = std::make_unique<DeviceKeyPlugin>(std::move(channel));
  registrar->AddPlugin(std::move(plugin));
}

DeviceKeyPlugin::DeviceKeyPlugin(
    std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel)
    : channel_(std::move(channel)) {
  channel_->SetMethodCallHandler([this](const auto &call, auto result) {
    HandleMethodCall(call, std::move(result));
  });
}

DeviceKeyPlugin::~DeviceKeyPlugin() {}

void DeviceKeyPlugin::HandleMethodCall(
    const flutter::MethodCall<EncodableValue> &call, Result result) {
  const auto *args = std::get_if<EncodableMap>(call.arguments());
  const std::string &method = call.method_name();
  if (method == "isAvailable") {
    IsAvailable(std::move(result));
    return;
  }
  const std::string *alias = StringArg(args, "alias");
  if (method == "create") {
    if (alias == nullptr) {
      result->Error("failed", "alias missing");
      return;
    }
    Create(*alias, std::move(result));
  } else if (method == "sign") {
    const std::vector<uint8_t> *bytes = BytesArg(args, "bytes");
    if (alias == nullptr || bytes == nullptr) {
      result->Success(SignAnswer("failed", "alias or bytes missing"));
      return;
    }
    Sign(*alias, *bytes, std::move(result));
  } else if (method == "delete") {
    if (alias == nullptr) {
      result->Success();
      return;
    }
    Delete(*alias, std::move(result));
  } else {
    result->NotImplemented();
  }
}

}  // namespace device_key
