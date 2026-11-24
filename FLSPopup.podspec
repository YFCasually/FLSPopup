Pod::Spec.new do |s|
  s.name = 'FLSPopup'
  s.version = '1.0.0'
  s.summary = 'SwiftUI page and scene-window popups with shared scheduling.'
  s.homepage = 'https://github.com/YFCasually/FLSPopup'
  s.license = { :type => 'MIT', :file => 'LICENSE' }
  s.author = { 'YFCasually' => 'https://github.com/YFCasually' }
  s.source = { :git => 'https://github.com/YFCasually/FLSPopup.git', :tag => s.version.to_s }
  s.ios.deployment_target = '17.0'
  s.swift_version = '5.9'
  s.source_files = 'Sources/FLSPopup/**/*.swift'
  s.frameworks = 'SwiftUI', 'UIKit'
end
