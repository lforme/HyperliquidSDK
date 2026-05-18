Pod::Spec.new do |s|
  s.name             = 'HyperliquidSDK'
  s.version          = '0.1.0'
  s.summary          = 'A Swift SDK for the Hyperliquid decentralized perpetual exchange.'
  s.description      = <<-DESC
HyperliquidSDK provides a native Swift interface to interact with the Hyperliquid
decentralized perpetual exchange. It includes REST API querying, WebSocket
subscriptions for real-time data, EIP-712 signed exchange actions (order placement,
cancellation, leverage updates), and encrypted local storage via MMKV.
                       DESC
  s.homepage         = 'https://github.com/IanWang/HyperliquidSDK'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Ian.Wang' => 'ian.wang@example.com' }
  s.source           = { :git => 'https://github.com/IanWang/HyperliquidSDK.git', :tag => s.version.to_s }

  s.ios.deployment_target = '16.0'
  s.swift_version         = '5.9'

  s.source_files = 'HyperliquidSDK/**/*.{swift,h,c,m}'

  s.public_header_files = 'HyperliquidSDK/secp256k1/include/**/*.h'

  s.dependency 'CryptoSwift', '1.8.4'
  s.dependency 'Starscream', '4.0.8'
  s.dependency 'SmartCodable', '6.0.8'
  s.dependency 'MMKV', '2.4.0'

  s.pod_target_xcconfig = {
    'GCC_PREPROCESSOR_DEFINITIONS' => 'ENABLE_MODULE_RECOVERY=1',
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/HyperliquidSDK/secp256k1/include" "${PODS_TARGET_SRCROOT}/HyperliquidSDK/secp256k1"',
    'CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES' => 'YES',
    'OTHER_CFLAGS' => '-fno-omit-frame-pointer'
  }

  s.user_target_xcconfig = {
    'GCC_PREPROCESSOR_DEFINITIONS' => 'ENABLE_MODULE_RECOVERY=1',
    'HEADER_SEARCH_PATHS' => '"${PODS_ROOT}/HyperliquidSDK/HyperliquidSDK/secp256k1/include" "${PODS_ROOT}/HyperliquidSDK/HyperliquidSDK/secp256k1"'
  }

  s.resource_bundles = {
    'HyperliquidSDK' => ['HyperliquidSDK/**/*.privacy']
  }
end
