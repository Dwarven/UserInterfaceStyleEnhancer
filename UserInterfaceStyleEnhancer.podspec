Pod::Spec.new do |s|

  s.name             = 'UserInterfaceStyleEnhancer'
  s.version          = '0.0.1'
  s.summary          = 'A utility that enhances and manages handling of UIUserInterfaceStyle.'
  s.homepage         = 'https://github.com/Dwarven/UserInterfaceStyleEnhancer'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Dwarven' => 'prison.yang@gmail.com' }
  s.platform         = :ios, '13.0'
  s.swift_versions   = '5'
  s.source           = { :git => 'https://github.com/Dwarven/UserInterfaceStyleEnhancer.git', :tag => s.version }
  s.requires_arc     = true
  s.framework        = 'UIKit', 'CoreGraphics', 'QuartzCore'
  s.source_files     = 'UserInterfaceStyleEnhancer/*.swift'
  s.module_name      = 'UserInterfaceStyleEnhancer'

end
