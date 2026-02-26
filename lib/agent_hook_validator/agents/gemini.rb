# frozen_string_literal: true

require_relative 'base'

module AgentHookValidator
  module Agents
    # Gemini CLI agent using `gemini -p` for non-interactive prompt mode
    class Gemini < Base
      def call(prompt)
        execute_command(['gemini', '-p', '-'], stdin_data: prompt)
      end
    end
  end
end
