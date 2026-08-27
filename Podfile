platform :ios, '15.0'

source 'https://cdn.cocoapods.org/'

# TopOn 聚合建议静态链接，避免与三方广告 SDK 动态库冲突
# 注：Meta Audience Network 6.22.0+ 官方改为推荐 Dynamic xcframework（CocoaPods 已按 Dynamic 分发）
use_frameworks! :linkage => :static

target 'neoball' do
  # TopOn 核心库
  pod 'TPNiOS', '6.5.75'

  # TopOn ADX
  pod 'TPNMediationAdxSmartdigimktAdapter', '6.5.75.2.2'

  # Facebook / Meta Audience Network（TopOn 中介广告源）
  # https://developers.facebook.com/documentation/audience-network/setting-up/platform-setup/ios/add-sdk
  pod 'FBAudienceNetwork', '6.22.0'
  pod 'TPNMediationFacebookAdapter', '6.22.0.2.0'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
      config.build_settings['CLANG_WARN_DOCUMENTATION_COMMENTS'] = 'NO'
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
      config.build_settings['SWIFT_VERSION'] = '5.0'
      # CI Manual signing: Pods must not inherit app provisioning profile
      config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
      config.build_settings['CODE_SIGNING_REQUIRED'] = 'NO'
      config.build_settings['EXPANDED_CODE_SIGN_IDENTITY'] = ''
      config.build_settings['CODE_SIGNING_IDENTITY'] = ''
      config.build_settings['CODE_SIGNING_IDENTITY[sdk=appletvos*]'] = ''
      config.build_settings['CODE_SIGNING_IDENTITY[sdk=iphoneos*]'] = ''
      config.build_settings['CODE_SIGNING_IDENTITY[sdk=watchos*]'] = ''
    end
  end

  installer.aggregate_targets.each do |aggregate_target|
    aggregate_target.user_project.targets.each do |target|
      target.build_configurations.each do |config|
        config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
        config.build_settings['CLANG_WARN_DOCUMENTATION_COMMENTS'] = 'NO'
        config.build_settings['SWIFT_VERSION'] = '5.0'
      end
    end
    aggregate_target.user_project.save
  end
end
