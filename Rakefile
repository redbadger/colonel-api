require 'rubocop/rake_task'
require 'rspec/core/rake_task'

rspec = RSpec::Core::RakeTask.new(:spec)
rspec.verbose = false

RuboCop::RakeTask.new

task test: [:rubocop, :spec]
