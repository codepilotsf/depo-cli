# frozen_string_literal: true
Gem::Specification.new do |spec|
  spec.name          = "depo-cli"
  spec.version       = "0.1.0"
  spec.authors       = ["Your Name"]
  spec.email         = ["your.email@example.com"]

  spec.summary       = "A simple CLI tool for depo."
  spec.description   = "A simple CLI tool that provides the 'depo' command."
  spec.homepage      = "https://example.com"
  spec.license       = "MIT"

  spec.files         = Dir["lib/**/*.rb"] + ["bin/depo"]
  spec.executables   = ["depo"]
  spec.bindir        = "bin"
  spec.require_paths = ["lib"]

  spec.add_dependency "net-ssh"
  spec.metadata["allowed_push_host"] = "https://rubygems.org"
end
