# frozen_string_literal: true

require_relative 'base'

module AgentHookValidator
  module Agents
    class OpenAI < Base
      def call(prompt)
        execute_command(
          ['codex', 'exec', '-'],
          stdin_data: prompt
        )
      end

      private

      def agent_label
        'Codex'
      end
    end
  end
end
