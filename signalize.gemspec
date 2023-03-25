# frozen_string_literal: true

require_relative "lib/signalize/version"

Gem::Specification.new do |spec|
  spec.name = "signalize"
  spec.version = Signalize::VERSION
  spec.authors = ["Jared White", "Preact Team"]
  spec.email = ["jared@whitefusion.studio"]

  spec.summary = "A Ruby port of Signals, providing reactive variables, derived computed state, side effect callbacks, and batched updates."
  spec.description = spec.summary
  spec.homepage = "https://github.com/whitefusionhq/signalize"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:bin|test|spec|features)/|\.(?:git|travis|circleci)|appveyor)})
    end
  end
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  spec.add_dependency "concurrent-ruby", "~> 1.2"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
