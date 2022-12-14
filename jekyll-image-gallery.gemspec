# frozen_string_literal: true

require_relative 'lib/gallery/version'

Gem::Specification.new do |spec|
  spec.name = 'jekyll-image-gallery'
  spec.version = ImageGallery::VERSION
  spec.authors = ['Jacob Essex']
  spec.email = ['ruby_gems@JacobEssex.com']

  spec.summary = 'Gallery generator for Jekyll'
  spec.homepage = 'https://github.com/Yacoby/jekyll-image-gallery'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 2.6.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/master/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:bin|test|spec|features)/|\.(?:git|travis|circleci)|appveyor)})
    end
  end
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'jekyll', '~> 4.0'
  spec.add_dependency 'mini_magick', '~> 4.1'
  spec.add_dependency 'toml', '~> 0.3.0'

  spec.add_development_dependency 'rubocop'
end
