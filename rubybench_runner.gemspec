# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'rubybench_runner/version'

Gem::Specification.new do |spec|
  spec.name          = 'rubybench_runner'
  spec.version       = RubybenchRunner::VERSION

  spec.summary       = 'CLI tool to run rubybench.org benchmarks locally'
  spec.homepage      = 'https://github.com/ruby-bench/rubybench_runner'
  spec.license       = 'MIT'
  spec.authors       = ['Osama Sayegh']

  spec.files         = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`
      .split("\x0")
      .reject { |f| f.match(%r{^(test|spec|features)/}) }
  end

  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_development_dependency 'byebug'
  spec.add_development_dependency 'minitest', '~> 5.0'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'rubocop', '~> 0.70'
end
