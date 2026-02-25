# frozen_string_literal: true

require 'json'
require 'fileutils'

module AgentHookValidator
  class Installer
    GREEN = "\e[32m"
    RED = "\e[31m"
    BLUE = "\e[34m"
    RESET = "\e[0m"

    attr_reader :options

    def initialize(options, stdout: $stdout)
      @options = options
      @stdout = stdout
      @gem_root = File.expand_path('../..', __dir__)
      @hook_cmd = "bundle exec ruby #{File.join(@gem_root, 'bin', 'agent-hook-validator')}"
    end

    def run
      targets = options[:target] == 'all' ? %w[claude gemini openai] : [options[:target]]

      targets.each do |target|
        agent_name = options[:agent] || target
        case target
        when 'claude' then install_claude(options[:project_dir], agent_name)
        when 'gemini' then install_gemini(agent_name)
        when 'openai' then install_openai(agent_name)
        end
      end

      log 'Done. Run your agent session to test the hook.', BLUE
    end

    def read_json_settings(path)
      return {} unless File.exist?(path)

      JSON.parse(File.read(path))
    rescue JSON::ParserError
      {}
    end

    def write_json_settings(path, settings)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate(settings))
    end

    def install_claude(project_dir, agent_name)
      settings_path = File.join(project_dir, '.claude', 'settings.json')
      settings = read_json_settings(settings_path)

      settings['hooks'] ||= {}
      settings['hooks']['Stop'] ||= []

      settings['hooks']['Stop'].reject! do |entry|
        hooks = entry['hooks'] || []
        hooks.any? { |h| h['command']&.include?('agent-hook-validator') }
      end

      settings['hooks']['Stop'] << {
        'hooks' => [{
          'type' => 'command',
          'command' => "#{@hook_cmd} -a #{agent_name}",
          'timeout' => 180
        }]
      }

      write_json_settings(settings_path, settings)
      log "Registered Claude Code Stop hook in #{settings_path}"
    end

    def install_gemini(agent_name)
      settings_path = File.expand_path('~/.gemini/settings.json')
      settings = read_json_settings(settings_path)

      settings['hooks'] ||= {}
      settings['hooks']['AfterAgent'] ||= []
      settings['hooks']['AfterAgent'].reject! { |h| h['name'] == 'agent-hook-validator' }

      settings['hooks']['AfterAgent'] << {
        'name' => 'agent-hook-validator',
        'type' => 'command',
        'command' => "#{@hook_cmd} -a #{agent_name}"
      }

      write_json_settings(settings_path, settings)
      log "Registered Gemini AfterAgent hook in #{settings_path}"
    end

    def install_openai(_agent_name)
      log 'OpenAI hook installation is not yet supported. Configure manually.', BLUE
    end

    private

    def log(msg, color = GREEN)
      @stdout.puts "#{color}#{msg}#{RESET}"
    end
  end
end
