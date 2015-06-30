
Pod::Spec.new do |s|
  s.name             = "PayPointPayments"
  s.version          = "1.0.0-rc1"
  s.summary          = "PayPoint IOS SDK"
  s.description      = <<-DESC
                        # PayPoint IOS SDK 
			Payments SDK For the PayPoint Payment service for use with IOS apps
			DESC
  s.homepage         = "https://github.com/paypoint/PayPointIOSSDK"
  s.screenshots      = "www.example.com/screenshots_1", "www.example.com/screenshots_2"
  s.license = { :type => "Apache License, Version 2.0", :file => "LICENSE" }

  s.author           = { "PayPoint" => "product@paypoint.net"  }
  s.source           = { :git => "https://github.com/paypoint/PayPointIOSSDK.git", :tag => s.version.to_s }

  s.platform     = :ios, '7.0'
  s.requires_arc = true

  s.source_files = ['PaypointSDK/*.[mh]','PaypointSDK/*.h','PaypointSDK/Public/*.h']
  s.resource_bundles = {
    'PayPointPayments' => ['PaypointResources/*','PaypointLibrary/PPOWebViewController.xib','Framework/Info.plist']
  }

  s.public_header_files = ['PaypointSDK/Public/*.h'] 
  s.frameworks = 'UIKit', 'SystemConfiguration', 'CoreGraphics'

end
