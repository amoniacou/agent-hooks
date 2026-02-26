# frozen_string_literal: true

require_relative 'lib/agent_hook_validator/version'

Gem::Specification.new do |spec|
  spec.name          = 'agent_hook_validator'
  spec.version       = AgentHookValidator::VERSION
  spec.authors       = ['Agent Hooks Contributors']
  spec.summary       = 'AI-powered code review hook for Claude Code, Gemini CLI, and Codex CLI'
  spec.description   = 'A pre-commit / post-action hook that uses an AI agent (Claude, Gemini, or Codex) ' \
                       'to review code changes before they land.'
  spec.homepage      = 'https://github.com/amoniacou/agent-hooks'
  spec.license       = 'MIT'

  spec.required_ruby_version = '>= 3.2'

  spec.files = Dir.glob('{bin,lib,config,templates,commands}/**/*') + %w[README.md]
  spec.bindir        = 'bin'
  spec.executables   = %w[agent-hook-validator agent-hook-install]

  spec.metadata['homepage_uri']    = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['rubygems_mfa_required'] = 'true'
end
