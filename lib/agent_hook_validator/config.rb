# frozen_string_literal: true

require 'yaml'
require_relative 'errors'

module AgentHookValidator
  class Config
    DEFAULTS = {
      'git' => {
        'diff_mode' => 'head',
        'max_diff_lines' => 2000,
        'exclude_patterns' => ['*.lock', '*.min.js', 'vendor/**']
      },
      'agent' => {
        'name' => 'gemini',
        'timeout_seconds' => 120
      },
      'thresholds' => {
        'max_critical_issues' => 0,
        'max_warnings' => 5,
        'require_tests_for_new_code' => true
      },
      'decision' => {
        'block_on_critical' => true,
        'block_on_warning_threshold' => true,
        'block_on_agent_failure' => false
      }
    }.freeze

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

    private_class_method def self.resolve_path(path)
      return path if path

      env_path = ENV.fetch('AGENT_HOOK_CONFIG', nil)
      return env_path if env_path && File.exist?(env_path)

      default_path = File.expand_path('../../config/default.yml', __dir__)
      return default_path if File.exist?(default_path)

      nil
    end

    private_class_method def self.deep_merge(base, override)
      base.each_with_object(base.dup) do |(key, base_val), result|
        next unless override.key?(key)

        result[key] = if base_val.is_a?(Hash) && override[key].is_a?(Hash)
                        deep_merge(base_val, override[key])
                      else
                        override[key]
                      end
      end.merge(override.reject { |k, _| base.key?(k) })
    end
  end
end
