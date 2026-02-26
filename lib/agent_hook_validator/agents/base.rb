# frozen_string_literal: true

require 'open3'
require_relative '../errors'

module AgentHookValidator
  module Agents
    class Base
      attr_reader :timeout

      def initialize(timeout: 120)
        @timeout = timeout
      end

      def call(prompt)
        raise NotImplementedError, "#{self.class} must implement the 'call' method."
      end

      private

      def execute_command(cmd, stdin_data: nil)
        stdin, stdout, stderr, wait_thr = Open3.popen3(*cmd)
        pid = wait_thr.pid

        stdin.write(stdin_data) if stdin_data
        stdin.close

        stdout_thread = Thread.new { stdout.read }
        stderr_thread = Thread.new { stderr.read }

        unless wait_thr.join(@timeout)
          kill_process(pid)
          stdout_thread.kill
          stderr_thread.kill
          raise AgentTimeoutError, "#{agent_label} timed out after #{@timeout}s"
        end

        stdout_str = stdout_thread.value
        stderr_str = stderr_thread.value
        check_exit_status(wait_thr.value, stderr_str)

        stdout_str.strip
      ensure
        [stdin, stdout, stderr].each { |io| io&.close unless io&.closed? }
      end

      def check_exit_status(status, stderr_str)
        return if status.success?

        raise AgentExecutionError,
              "#{agent_label} CLI error (exit #{status.exitstatus}): #{stderr_str.strip}"
      end

      def agent_label
        self.class.name.split('::').last
      end

      def kill_process(pid)
        return unless pid

        Process.kill('TERM', pid)
        sleep 0.5
        Process.kill('KILL', pid) if process_alive?(pid)
      rescue Errno::ESRCH
        # process already exited
      end

      def process_alive?(pid)
        Process.kill(0, pid)
        true
      rescue Errno::ESRCH
        false
      end
    end
  end
end
