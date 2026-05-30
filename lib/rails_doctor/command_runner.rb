# frozen_string_literal: true

require "open3"
require "shellwords"
require "timeout"

module RailsDoctor
  CommandResult = Struct.new(:command, :stdout, :stderr, :exit_status, :duration_ms, keyword_init: true)

  class CommandRunner
    attr_reader :project_root, :env

    def initialize(project_root:, env: ENV)
      @project_root = File.expand_path(project_root)
      @env = env
    end

    def run(command, timeout_seconds: 120)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      stdout = +""
      stderr = +""
      status_code = nil

      begin
        Timeout.timeout(timeout_seconds) do
          stdout, stderr, status = Open3.capture3(env.to_h, command, chdir: project_root)
          status_code = status.exitstatus
        end
      rescue Timeout::Error
        stderr = "Command timed out after #{timeout_seconds}s"
        status_code = 124
      rescue Errno::ENOENT => error
        stderr = error.message
        status_code = 127
      end

      finished = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      CommandResult.new(
        command: command,
        stdout: stdout,
        stderr: stderr,
        exit_status: status_code,
        duration_ms: ((finished - started) * 1000).round
      )
    end

    def executable?(name)
      path = env.fetch("PATH", "").split(File::PATH_SEPARATOR)
      path.any? do |dir|
        candidate = File.join(dir, name)
        File.file?(candidate) && File.executable?(candidate)
      end
    end
  end
end
