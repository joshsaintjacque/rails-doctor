# frozen_string_literal: true

module RailsDoctor
  class Project
    attr_reader :root, :runner

    def initialize(root:, runner: nil)
      @root = File.expand_path(root)
      @runner = runner || CommandRunner.new(project_root: @root)
    end

    def rails_app?
      File.exist?(join("config/application.rb")) || File.exist?(join("bin/rails")) || gem_declared?("rails")
    end

    def gem_declared?(name)
      [join("Gemfile"), join("Gemfile.lock")].any? do |path|
        next false unless File.exist?(path)

        content = File.read(path)
        content.include?(%("#{name}")) ||
          content.include?(%('#{name}')) ||
          content.match?(/^\s{4}#{Regexp.escape(name)}\s/) ||
          content.match?(/^\s{2}#{Regexp.escape(name)}\s/)
      end
    end

    def command_available?(name)
      runner.executable?(name) || File.executable?(join("bin/#{name}"))
    end

    def current_branch
      result = runner.run("git rev-parse --abbrev-ref HEAD", timeout_seconds: 5)
      return nil unless result.exit_status == 0

      result.stdout.strip
    end

    def dirty_worktree?
      result = runner.run("git status --porcelain", timeout_seconds: 5)
      result.exit_status == 0 && !result.stdout.strip.empty?
    end

    def changed_files
      names = []
      ["git diff --name-only", "git diff --cached --name-only"].each do |command|
        result = runner.run(command, timeout_seconds: 10)
        names.concat(result.stdout.lines.map(&:strip)) if result.exit_status == 0
      end
      names.uniq.reject(&:empty?)
    end

    def churn(window_days:)
      since = (Time.now - window_days.to_i * 86_400).strftime("%Y-%m-%d")
      command = "git log --since=#{since} --name-only --pretty=format:"
      result = runner.run(command, timeout_seconds: 20)
      return {} unless result.exit_status == 0

      result.stdout.lines.map(&:strip).reject(&:empty?).each_with_object(Hash.new(0)) do |file, counts|
        counts[file] += 1
      end
    end

    def files(pattern)
      Dir.glob(join(pattern)).select { |path| File.file?(path) }
    end

    def relative(path)
      path.to_s.delete_prefix("#{root}/")
    end

    def join(*parts)
      File.join(root, *parts)
    end
  end
end
