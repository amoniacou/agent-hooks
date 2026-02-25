# frozen_string_literal: true

module AgentHookValidator
  class Error < StandardError; end

  class AgentExecutionError < Error; end

  class AgentTimeoutError < Error; end

  class GitNotAvailable < Error; end

  class ConfigLoadError < Error; end

  class TemplateNotFound < Error; end
end
