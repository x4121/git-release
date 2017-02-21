# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'git-release/version'

GEM_VERSION = GitRelease::VERSION

Gem::Specification.new do |spec|
    spec.name        = 'git-release'
    spec.version     = GEM_VERSION
    spec.authors     = ['Armin Grodon']
    spec.email       = ['me@armingrodon.de']

    spec.summary     = "A command line tool to edit existing GitHub releases"
    spec.description = ""
    spec.homepage    = 'https://github.com/x4121/git-release'

    spec.executables = 'git-release'
    spec.date        = '2017-02-21'
    spec.extra_rdoc_files = ['README.md']
    spec.files       = [
        "LICENSE",
        "README.md",
        "lib/git-release.rb",
        "lib/git-release/version.rb"
        # "lib/git-release/common/git.rb",
        # "lib/git-release/common/string.rb",
        # "lib/git-release/common/log.rb"
    ]
    spec.required_ruby_version = '>= 1.9'
    spec.add_runtime_dependency 'octokit', '~> 4.6'
    spec.add_runtime_dependency 'highline', '~> 1.7'
    spec.add_development_dependency 'rake', '~> 0'
    spec.requirements << 'git'
    spec.requirements << 'git'
    spec.license     = 'MIT'
end
