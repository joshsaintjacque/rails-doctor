# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |task|
  task.libs << "test"
  task.pattern = "test/**/*_test.rb"
  task.warning = true
end

task :lint do
  sh "rubocop"
end

task :security do
  sh "bundle-audit check --update"
end

task default: :test
