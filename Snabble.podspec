#
# Be sure to run `pod lib lint Snabble.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'Snabble'
  s.version          = '0.3.8'
  s.summary          = 'The snabble iOS SDK'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
  snabble - the self-scanning and checkout platform
  The SDK provides scanning, checkout and payment services and UI components based on the snabble SaaS platform.
  DESC

  s.homepage         = 'https://snabble.io/'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'snabble GmbH' => 'info@snabble.io' }
  s.source           = { :git => 'https://github.com/snabble/iOS-SDK.git', :tag => "#{s.version}" }
  s.social_media_url = 'https://twitter.com/snabble_io'

  s.ios.deployment_target = '10.0'
  s.swift_version = '4.1'

  s.subspec 'Core' do |core|
    core.source_files = 'Snabble/Core/{Products,EAN,Cart,Metadata}/*.swift'
    core.dependency 'GRDB.swift', '~> 2'
    core.dependency 'Zip', '~> 1'
  end

  s.subspec 'UI' do |ui|
    ui.source_files = 'Snabble/UI/{Utilities,EAN,Scanner,ShoppingCart,Payment}/*.{swift,xib}'
    ui.dependency 'Snabble/Core'
    ui.dependency 'DZNEmptyDataSet'
    ui.dependency 'SwiftMessages'

    ui.resource_bundles = {
      "Snabble" => [ 'Snabble.xcassets', 'Snabble/UI/*.lproj/*.strings', 'Snabble/UI/*.twine' ]
    }

    ui.script_phase = { 
      :name => "Run twine", 
      :script => <<-SCRIPT
      if which twine >/dev/null; then
        cd $PODS_TARGET_SRCROOT
        twine generate-localization-file Snabble/UI/Snabble.twine --lang en --format apple Snabble/UI/en.lproj/SnabbleLocalizable.strings
      fi
      SCRIPT
    }
  end

end
