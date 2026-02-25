# frozen_string_literal: true

require_relative 'base'

module AgentHookValidator
  module Agents
    class Gemini < Base
      def call(prompt)
        execute_command(['gemini', '-p', '-'], stdin_data: prompt)
      end
    end
  end
end
