# frozen_string_literal: true

require 'json'
require 'open3'
require_relative 'agent_hook_validator/errors'
require_relative 'agent_hook_validator/config'
require_relative 'agent_hook_validator/agent_factory'
require_relative 'agent_hook_validator/template_renderer'

module AgentHookValidator
  class Runner
    GREEN = "\e[32m"
    RED = "\e[31m"
    RESET = "\e[0m"

    def initialize(options, stdin: $stdin, stdout: $stdout, stderr: $stderr)
      @config = Config.load(options[:config])
      @agent_name = options[:agent] || @config.dig('agent', 'name')
      @template_path = options[:template] || default_template_path
      @timeout = @config.dig('agent', 'timeout_seconds') || 120
      @stdin = stdin
      @stdout = stdout
      @stderr = stderr
    end

    def run
      input_data = @stdin.read
      return if input_data.nil? || input_data.empty?

      JSON.parse(input_data)

      raise GitNotAvailable, 'Not inside a git work tree' unless git_available?

      diff, changed_files = prepare_diff
      return output_decision('allow') if diff.empty?

      validate_with_agent(diff, changed_files)
    rescue GitNotAvailable
      log 'Not in a git repository, allowing.', RED
      output_decision('allow')
    rescue TemplateNotFound => e
      log e.message, RED
      output_decision('allow')
    rescue AgentExecutionError, AgentTimeoutError => e
      handle_agent_error(e)
    rescue StandardError => e
      log "Fatal error: #{e.message}", RED
      @stderr.puts e.backtrace
      output_decision('allow', system_message: "Validator error: #{e.message}")
    end

    private

    def prepare_diff
      diff = fetch_diff
      return ['', []] if diff.empty?

      changed_files = fetch_changed_files
      diff = filter_diff(diff, changed_files)
      return ['', []] if diff.empty?

      changed_files = filter_changed_files(changed_files)
      [diff, changed_files]
    end

    def validate_with_agent(diff, changed_files)
      raise TemplateNotFound, "Template not found: #{@template_path}" unless File.exist?(@template_path)

      log "Using agent: #{@agent_name}"
      log 'Rendering prompt...'
      prompt = TemplateRenderer.render(@template_path, diff, changed_files)

      agent = AgentFactory.build(@agent_name, timeout: @timeout)

      log "Validating with #{@agent_name}..."
      summary = agent.call(prompt)

      output_agent_result(summary)
    end

    def output_agent_result(summary)
      if summary.start_with?('CRITICAL:')
        log 'Critical issues found!', RED
        output_decision('retry', reason: "AgentHookValidator (#{@agent_name}) found issues:\n\n#{summary}")
      else
        log 'Validation successful.'
        output_decision('allow', system_message: "#{@agent_name.capitalize} Review Summary:\n\n#{summary}")
      end
    end

    def handle_agent_error(error)
      log "Agent error: #{error.message}", RED
      if @config.dig('decision', 'block_on_agent_failure')
        output_decision('retry', reason: "Agent error: #{error.message}")
      else
        output_decision('allow', system_message: "Validator error: #{error.message}")
      end
    end

    def default_template_path
      File.expand_path('../templates/validation.erb', __dir__)
    end

    def git_available?
      _, _, status = Open3.capture3('git', 'rev-parse', '--is-inside-work-tree')
      status.success?
    end

    def fetch_diff
      diff_mode = @config.dig('git', 'diff_mode') || 'head'
      max_lines = @config.dig('git', 'max_diff_lines') || 2000

      diff = case diff_mode
             when 'cached'
               out, = Open3.capture3('git', 'diff', '--cached')
               out
             when 'combined'
               head_out, = Open3.capture3('git', 'diff', 'HEAD')
               cached_out, = Open3.capture3('git', 'diff', '--cached')
               "#{head_out}#{cached_out}"
             else
               out, = Open3.capture3('git', 'diff', 'HEAD')
               out
             end

      diff = diff.strip
      lines = diff.lines
      lines.length > max_lines ? lines.first(max_lines).join : diff
    end

    def fetch_changed_files
      diff_mode = @config.dig('git', 'diff_mode') || 'head'

      case diff_mode
      when 'cached'
        o, = Open3.capture3('git', 'diff', '--name-only', '--cached')
      else
        o, = Open3.capture3('git', 'diff', '--name-only', 'HEAD')
      end
      out = o

      out.split("\n")
    end

    def filter_changed_files(changed_files)
      patterns = @config.dig('git', 'exclude_patterns') || []
      return changed_files if patterns.empty?

      changed_files.reject do |file|
        patterns.any? { |pattern| File.fnmatch(pattern, file, File::FNM_PATHNAME) }
      end
    end

    def filter_diff(diff, _changed_files)
      patterns = @config.dig('git', 'exclude_patterns') || []
      return diff if patterns.empty?

      sections = diff.split(/(?=^diff --git )/)

      filtered = sections.reject do |section|
        match = section.match(%r{^diff --git a/.+ b/(.+)$})
        next false unless match

        file = match[1]
        patterns.any? { |pattern| File.fnmatch(pattern, file, File::FNM_PATHNAME) }
      end

      filtered.join
    end

    def output_decision(decision, reason: nil, system_message: nil)
      result = { 'decision' => decision }
      result['reason'] = reason if reason
      result['systemMessage'] = system_message if system_message
      @stdout.print JSON.generate(result)
    end

    def log(msg, color = GREEN)
      @stderr.puts "#{color}[Agent Validator] #{msg}#{RESET}"
    end
  end
end
