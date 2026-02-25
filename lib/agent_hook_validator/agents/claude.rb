# frozen_string_literal: true

require_relative 'base'

module AgentHookValidator
  module Agents
    class Claude < Base
      def call(prompt)
        execute_command(['claude', '-p', '-'], stdin_data: prompt)
      end
    end
  end
end
