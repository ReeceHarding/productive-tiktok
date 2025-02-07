# Uncomment the next line to define a global platform for your project
platform :ios, '12.0'

target 'TikTok' do
  # Comment the next line if you don't want to use dynamic frameworks
  use_frameworks!

  # Pods for TikTok
  pod 'Firebase'
  pod 'FirebaseAuth'
  pod 'FirebaseDatabase'
  pod 'FirebaseStorage'
  pod 'FirebaseMessaging'
  pod 'Kingfisher'
  pod 'SVProgressHUD'
  pod 'SwiftVideoGenerator'
  pod 'EasyTipView'
  pod 'PryntTrimmerView'
  pod 'lottie-ios'
  pod 'PanModal'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '12.0'
      if target.name == 'GoogleDataTransport'
        config.build_settings['GCC_WARN_ABOUT_MISSING_PROTOTYPES'] = 'NO'
        config.build_settings['GCC_WARN_STRICT_PROTOTYPES'] = 'NO'
      end
    end
  end
end
