require 'fileutils'

# typst_flutter 3.0.0 computes an absolute vendored_frameworks path, which
# CocoaPods rejects before post_install runs. Build a local spec with relative
# paths and symlink its inputs, leaving the shared pub cache untouched.
module TypstPodspec
  # Intercept Flutter's normal pod declaration so CocoaPods stores the corrected
  # source path, rather than changing a temporary Dependency object afterward.
  def pod(name, *requirements)
    if name == 'typst_flutter'
      options = requirements.last
      raise 'Expected typst_flutter to be a local Flutter plugin pod.' unless options.is_a?(Hash) && options[:path]
      options[:path] = TypstPodspec.prepare(options[:path], __dir__)
    end
    super(name, *requirements)
  end

  def self.prepare(plugin_ios_path, ios_directory)
    plugin_ios = File.expand_path(plugin_ios_path, ios_directory)
    plugin_root = File.expand_path('..', plugin_ios)
    framework = File.join(plugin_root, '.typst_flutter_prebuilt/ios/typst_flutter.xcframework')
    unless File.file?(File.join(framework, 'Info.plist'))
      raise 'Typst iOS libraries missing. Run dart run typst_flutter:setup --force before pod install.'
    end

    spec = Pod::Specification.from_file(File.join(plugin_ios, 'typst_flutter.podspec'))
    spec.vendored_frameworks = 'typst_flutter.xcframework'
    spec.license = { :type => 'Apache-2.0', :file => 'LICENSE' }

    relative_directory = '.symlinks/typst_flutter_pod'
    directory = File.join(ios_directory, relative_directory)
    FileUtils.mkdir_p(directory)
    {
      'Classes' => File.join(plugin_ios, 'Classes'),
      'LICENSE' => File.join(plugin_root, 'LICENSE'),
      'typst_flutter.xcframework' => framework,
    }.each do |name, source|
      link = File.join(directory, name)
      File.unlink(link) if File.symlink?(link)
      File.symlink(source, link)
    end
    File.write(File.join(directory, 'typst_flutter.podspec.json'), spec.to_pretty_json)
    relative_directory
  end
end
