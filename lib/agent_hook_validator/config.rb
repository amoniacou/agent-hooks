# frozen_string_literal: true

require 'yaml'
require_relative 'errors'

module AgentHookValidator
  class Config
    DEFAULTS = {
      'git' => {
        'diff_mode' => 'head',
        'exclude_patterns' => ['*.lock', '*.min.js', 'vendor/**']
      },
      'agent' => {
        'name' => 'gemini',
        'timeout_seconds' => 300
      },
      'decision' => {
        'block_on_agent_failure' => false,
        'min_quality_score' => 9
      }
    }.freeze

    PROJECT_CONFIG_NAME = '.agent-hook-validator.yml'

    attr_reader :data

    def initialize(data)
      @data = data
    end

    def self.load(path = nil)
      path = resolve_path(path)
      raw = if path && File.exist?(path)
              begin
                YAML.safe_load_file(path) || {}
              rescue Psych::SyntaxError => e
                raise ConfigLoadError, "Invalid YAML config: #{e.message}"
              end
            else
              {}
            end

      new(deep_merge(DEFAULTS, raw))
    end

    def dig(*keys)
      @data.dig(*keys)
    end

    def [](key)
      @data[key]
    end

    def agent_entries
      agents = @data['agents']
      default_timeout = dig('agent', 'timeout_seconds') || 120

      if agents.is_a?(Array) && !agents.empty?
        agents.map do |a|
          { name: a['name'], timeout: a['timeout_seconds'] || default_timeout }
        end
      else
        name = dig('agent', 'name') || 'gemini'
        [{ name: name, timeout: default_timeout }]
      end
    end

    def agent_names
      agent_entries.map { |e| e[:name] }
    end

    def merge_project_config(cwd)
      project_path = File.join(cwd, PROJECT_CONFIG_NAME)
      return self unless File.exist?(project_path)

      raw = YAML.safe_load_file(project_path) || {}
      self.class.new(self.class.deep_merge(@data, raw))
    rescue Psych::SyntaxError => e
      raise ConfigLoadError, "Invalid project YAML config: #{e.message}"
    end

    private_class_method def self.resolve_path(path)
      return path if path

      env_path = ENV.fetch('AGENT_HOOK_CONFIG', nil)
      return env_path if env_path && File.exist?(env_path)

      default_path = File.expand_path('../../config/default.yml', __dir__)
      return default_path if File.exist?(default_path)

      nil
    end

    protected

    def self.deep_merge(base, override)
      base.each_with_object({}) do |(key, base_val), result|
        result[key] = if override.key?(key)
                        if base_val.is_a?(Hash) && override[key].is_a?(Hash)
                          deep_merge(base_val, override[key])
                        elsif base_val.is_a?(Array) && override[key].is_a?(Array)
                          (base_val | override[key])
                        else
                          override[key]
                        end
                      elsif base_val.is_a?(Array)
                        base_val.dup
                      else
                        base_val
                      end
      end.merge(override.reject { |k, _| base.key?(k) })
    end
  end
end
