# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new(:lint) do |t|
  t.formatters = %w[simple]
  t.options = ["--parallel"]
end

namespace :lint do
  desc "Lint safe fix (Rubocop)"
  task fix: :autocorrect

  desc "Lint all fix (Rubocop)"
  task fixall: :autocorrect_all
end

namespace :rbs do
  desc "Install RBS Collection"
  task :install do
    require "rbs"
    require "rbs/cli"
    RBS::CLI.new(stdout: $stdout, stderr: $stderr).run("collection install --frozen".split)
  end

  desc "Update RBS Collection"
  task :update do
    require "rbs"
    require "rbs/cli"
    RBS::CLI.new(stdout: $stdout, stderr: $stderr).run("collection update".split)
  end

  desc "Generated RBS files from rbs-inline"
  task :inline do
    require "rbs/inline"
    require "rbs/inline/cli"
    FileUtils.rm_r(File.expand_path("sig/generated", __dir__), secure: true)
    RBS::Inline::CLI.new.run(%w[lib --output --opt-out])
  end
end

desc "Typecheck Run (Steep)"
task typecheck: %i[rbs:inline] do
  require "steep"
  require "steep/cli"
  steep_options = { stdout: $stdout, stderr: $stderr, stdin: $stdin }
  Steep::CLI.new(argv: ["check", "-j2"], **steep_options).run.zero? || exit(1)
end

task default: %i[lint typecheck spec]
