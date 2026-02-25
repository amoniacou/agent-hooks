# frozen_string_literal: true

require_relative 'base'

module AgentHookValidator
  module Agents
    class OpenAI < Base
      def call(prompt)
        execute_command(
          ['openai', 'chat', 'create', '--model', 'gpt-4o', '--message', '-'],
          stdin_data: prompt
        )
      end
    end
  end
end
