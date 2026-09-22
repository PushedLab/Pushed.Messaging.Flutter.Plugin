#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_pushed_messaging.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_pushed_messaging'
  s.version          = '0.0.1'
  s.summary          = 'A new Flutter plugin project.'
  s.description      = <<-DESC
A new Flutter plugin project.
                       DESC
  s.homepage         = 'https://multifactor.ru'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'MultiFactor' => 'sales@multifactor.ru' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.dependency 'PushedMessagingiOSLibrary', '~> 1.2.0'

  # Меняем минимальную платформу обратно на iOS 12.0
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
