# frozen_string_literal: true

require_relative 'agents/claude'
require_relative 'agents/openai'
require_relative 'agents/gemini'

module AgentHookValidator
  class AgentFactory
    SUPPORTED_AGENTS = %w[claude openai gemini].freeze

    def self.build(agent_name, timeout: 120)
      case agent_name.downcase
      when 'claude'
        Agents::Claude.new(timeout: timeout)
      when 'openai'
        Agents::OpenAI.new(timeout: timeout)
      when 'gemini'
        Agents::Gemini.new(timeout: timeout)
      else
        raise ArgumentError, "Unsupported agent: #{agent_name}. Choose from: #{SUPPORTED_AGENTS.join(', ')}."
      end
    end
  end
end
