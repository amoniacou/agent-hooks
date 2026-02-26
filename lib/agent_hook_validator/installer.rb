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
    end

    def run
      targets = options[:target] == 'all' ? %w[claude gemini openai] : [options[:target]]

      targets.each do |target|
        case target
        when 'claude' then install_claude(options[:project_dir])
        when 'gemini' then install_gemini
        when 'openai' then install_openai
        else log("Unknown target: #{target}, skipping.", RED)
        end
      end

      log 'Done. Use /validate <agent-name> in your agent session.', BLUE
    end

    private

    def install_claude(project_dir)
      project_dir ||= Dir.pwd
      commands_dir = File.join(project_dir, '.claude', 'commands')
      source = File.join(@gem_root, 'commands', 'claude', 'validate.md')

      unless File.exist?(source)
        log "Source command file not found: #{source}", RED
        return
      end

      FileUtils.mkdir_p(commands_dir)
      FileUtils.cp(source, File.join(commands_dir, 'validate.md'))
      log "Installed /validate command in #{commands_dir}/validate.md"
    end

    def install_gemini
      commands_dir = File.expand_path('~/.gemini/commands')
      source = File.join(@gem_root, 'commands', 'gemini', 'validate.toml')

      unless File.exist?(source)
        log "Source command file not found: #{source}", RED
        return
      end

      FileUtils.mkdir_p(commands_dir)
      FileUtils.cp(source, File.join(commands_dir, 'validate.toml'))
      log "Installed /validate command in #{commands_dir}/validate.toml"
    end

    def install_openai
      log 'OpenAI Codex custom commands are not yet supported. Configure manually.', BLUE
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

    def log(msg, color = GREEN)
      @stdout.puts "#{color}#{msg}#{RESET}"
    end
  end
end
