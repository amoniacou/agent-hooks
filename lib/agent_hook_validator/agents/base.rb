# frozen_string_literal: true

require 'open3'
require 'timeout'
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
        stdout = stderr = nil
        status = nil

        Timeout.timeout(@timeout) do
          stdout, stderr, status = Open3.capture3(*cmd, stdin_data: stdin_data)
        end

        unless status.success?
          raise AgentExecutionError,
                "#{self.class.name.split('::').last} CLI error (exit #{status.exitstatus}): #{stderr.to_s.strip}"
        end

        stdout.strip
      rescue Timeout::Error
        raise AgentTimeoutError, "#{self.class.name.split('::').last} timed out after #{@timeout}s"
      end
    end
  end
end
