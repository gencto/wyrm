# The same Swift sources as the Swift package beside it (sharedDarwinSource).
Pod::Spec.new do |s|
  s.name             = 'device_key'
  s.version          = '1.0.0'
  s.summary          = 'A Secure Enclave key behind Touch ID / Face ID (ADR 0050).'
  s.description      = 'Device keys of WYRM Studio: P-256 in the Secure Enclave, signed after LocalAuthentication.'
  s.homepage         = 'https://github.com/gencto/wyrm'
  s.license          = { :type => 'MIT', :file => '../../LICENSE' }
  s.author           = { 'WYRM' => 'noreply@github.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'device_key/Sources/device_key/**/*.swift'
  s.resource_bundles = { 'device_key_privacy' => ['device_key/Sources/device_key/PrivacyInfo.xcprivacy'] }
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '12.0'
  s.frameworks       = 'CryptoKit', 'LocalAuthentication', 'Security'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
