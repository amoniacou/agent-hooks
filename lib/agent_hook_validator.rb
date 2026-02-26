# frozen_string_literal: true

require 'json'
require_relative 'agent_hook_validator/version'
require 'open3'
require_relative 'agent_hook_validator/errors'
require_relative 'agent_hook_validator/config'
require_relative 'agent_hook_validator/agent_factory'
require_relative 'agent_hook_validator/template_renderer'
require_relative 'agent_hook_validator/response_evaluator'

module AgentHookValidator
  class Runner
    def initialize(options, stdin: $stdin, stdout: $stdout, stderr: $stderr, log: nil)
      @config = Config.load(options[:config])
      @agent_name = options[:agent] || @config.dig('agent', 'name')
      @template_path = options[:template] || default_template_path
      @timeout = @config.dig('agent', 'timeout_seconds') || 120
      @stdin = stdin
      @stdout = stdout
      @stderr = stderr
      @log = log
      @exit_code = 0
    end

    def run
      return @exit_code unless parse_input?

      raise GitNotAvailable, 'Not inside a git work tree' unless git_available?

      changed_files = prepare_changed_files
      return output_allow if changed_files.empty?

      validate_with_agent(changed_files)
      @exit_code
    rescue GitNotAvailable
      log 'Not in a git repository, allowing.'
      output_allow
    rescue TemplateNotFound => e
      log e.message
      output_allow
    rescue AgentExecutionError, AgentTimeoutError => e
      handle_agent_error(e)
    rescue StandardError => e
      log "Fatal error: #{e.message}"
      log e.backtrace.join("\n")
      output_allow("Validator error: #{e.message}")
    ensure
      close_log_file
    end

    private

    def parse_input?
      input_data = @stdin.read
      return false if input_data.nil? || input_data.empty?

      @input = JSON.parse(input_data)
      @cwd = resolve_cwd
      true
    rescue JSON::ParserError => e
      log "Invalid JSON input: #{e.message}"
      false
    end

    def prepare_changed_files
      changed_files = fetch_changed_files
      return [] if changed_files.empty?

      filter_changed_files(changed_files)
    end

    def validate_with_agent(changed_files)
      raise TemplateNotFound, "Template not found: #{@template_path}" unless File.exist?(@template_path)

      log "Using agent: #{@agent_name}"
      prompt = TemplateRenderer.render(@template_path, changed_files)
      summary = AgentFactory.build(@agent_name, timeout: @timeout).call(prompt)

      min_score = @config.dig('decision', 'min_quality_score') || ResponseEvaluator::DEFAULT_MIN_QUALITY_SCORE
      evaluator = ResponseEvaluator.new(summary, min_quality_score: min_score)

      if evaluator.block?
        log "Issues found: #{evaluator.reasons.join(', ')}"
        output_block("AgentHookValidator (#{@agent_name}) found issues:\n\n#{summary}")
      else
        log 'Validation successful.'
        output_allow("#{@agent_name.capitalize} Review Summary:\n\n#{summary}")
      end
    end

    def handle_agent_error(error)
      log "Agent error: #{error.message}"
      if @config.dig('decision', 'block_on_agent_failure')
        output_block("Agent error: #{error.message}")
      else
        output_allow("Validator error: #{error.message}")
      end
      @exit_code
    end

    def default_template_path
      File.expand_path('../templates/validation.erb', __dir__)
    end

    def git_available?
      _, _, status = Open3.capture3('git', 'rev-parse', '--is-inside-work-tree', chdir: @cwd)
      status.success?
    end

    def fetch_changed_files
      diff_mode = @config.dig('git', 'diff_mode') || 'head'

      case diff_mode
      when 'cached'
        out, = Open3.capture3('git', 'diff', '--name-only', '--cached', chdir: @cwd)
        out.split("\n")
      when 'combined'
        cached, = Open3.capture3('git', 'diff', '--name-only', '--cached', chdir: @cwd)
        unstaged, = Open3.capture3('git', 'diff', '--name-only', chdir: @cwd)
        (cached.split("\n") | unstaged.split("\n"))
      else
        out, = Open3.capture3('git', 'diff', '--name-only', 'HEAD', chdir: @cwd)
        out.split("\n")
      end
    end

    def filter_changed_files(changed_files)
      patterns = @config.dig('git', 'exclude_patterns') || []
      return changed_files if patterns.empty?

      changed_files.reject do |file|
        patterns.any? { |pattern| File.fnmatch(pattern, file, File::FNM_PATHNAME) }
      end
    end

    def resolve_cwd
      raw = @input['cwd'] || Dir.pwd
      path = File.realpath(raw)
      File.directory?(path) ? path : Dir.pwd
    rescue Errno::ENOENT, Errno::EACCES
      Dir.pwd
    end

    def output_allow(message = nil)
      result = { 'decision' => 'allow' }
      result['systemMessage'] = message if message
      @stdout.print JSON.generate(result)
      @exit_code = 0
    end

    def output_block(reason)
      result = { 'decision' => 'block', 'reason' => reason }
      @stdout.print JSON.generate(result)
      @exit_code = 0
    end

    def log(msg)
      @log_file ||= @log || open_log_file
      @log_file.puts("[Agent Validator] #{msg}")
    rescue IOError, SystemCallError
      # Logging failure should not crash the validator
      nil
    end

    def open_log_file
      path = File.join(@cwd || Dir.pwd, '.agent-hook-validator.log')
      File.open(path, 'a')
    end

    def close_log_file
      return unless @log_file
      return if @log_file == @log

      @log_file.close unless @log_file.closed?
    end
  end
end
