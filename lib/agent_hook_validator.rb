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
      @options = options
      @config = Config.load(options[:config])
      @agent_entries = if options[:agent]
                         timeout = @config.dig('agent', 'timeout_seconds') || 120
                         options[:agent].split(',').map(&:strip).map do |name|
                           { name: name, timeout: timeout }
                         end
                       else
                         @config.agent_entries
                       end
      @template_path = options[:template] || default_template_path
      @stdin = stdin
      @stdout = stdout
      @stderr = stderr
      @log = log
      @verbose = options[:verbose] || false
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
      input_data = read_stdin
      if input_data.nil? || input_data.empty?
        @input = {}
        @cwd = resolve_cwd
        apply_project_config
        return true
      end

      @input = JSON.parse(input_data)
      @cwd = resolve_cwd
      apply_project_config
      true
    rescue JSON::ParserError => e
      log "Invalid JSON input: #{e.message}"
      output_allow("Validator error: invalid JSON input")
      false
    end

    def read_stdin
      return nil if @stdin.tty?

      @stdin.read
    rescue Errno::ENOENT
      nil
    end

    def apply_project_config
      @config = @config.merge_project_config(@cwd)
      @agent_entries = @config.agent_entries unless @options[:agent]
    end

    def prepare_changed_files
      changed_files = fetch_changed_files
      return [] if changed_files.empty?

      filter_changed_files(changed_files)
    end

    def validate_with_agent(changed_files)
      raise TemplateNotFound, "Template not found: #{@template_path}" unless File.exist?(@template_path)

      prompt = TemplateRenderer.render(@template_path, changed_files)
      min_score = @config.dig('decision', 'min_quality_score') || ResponseEvaluator::DEFAULT_MIN_QUALITY_SCORE

      if @agent_entries.size == 1
        validate_single_agent(@agent_entries.first, prompt, min_score)
      else
        validate_multiple_agents(prompt, min_score)
      end
    end

    def validate_single_agent(entry, prompt, min_score)
      log "Using agent: #{entry[:name]}"
      summary = AgentFactory.build(entry[:name], timeout: entry[:timeout]).call(prompt)
      evaluator = ResponseEvaluator.new(summary, min_quality_score: min_score)

      if evaluator.block?
        log "Issues found: #{evaluator.reasons.join(', ')}"
        output_block("AgentHookValidator (#{entry[:name]}) found issues:\n\n#{summary}")
      else
        log 'Validation successful.'
        output_allow("#{entry[:name].capitalize} Review Summary:\n\n#{summary}")
      end
    end

    def validate_multiple_agents(prompt, min_score)
      log "Using agents: #{agent_names.join(', ')}"
      results = run_agents_in_parallel(prompt)

      successful = results.select { |r| r[:summary] }
      failed = results.select { |r| r[:error] }
      merged = format_merged_summary(results)

      block_on_failure = @config.dig('decision', 'block_on_agent_failure')

      if block_on_failure && failed.any?
        log "Agent errors: #{failed.map { |r| "#{r[:agent]} - #{r[:error]}" }.join(', ')}"
        output_block("AgentHookValidator found agent errors:\n\n#{merged}")
        return
      end

      if successful.empty?
        log 'All agents failed, allowing (fail-open).'
        output_allow("All agents failed:\n\n#{merged}")
        return
      end

      any_block = successful.any? { |r| r[:evaluator].block? }

      if any_block
        blocking = successful.select { |r| r[:evaluator].block? }
        blocking.each do |r|
          log "Issues found by #{r[:agent]}: #{r[:evaluator].reasons.join(', ')}"
        end
        output_block("AgentHookValidator found issues:\n\n#{merged}")
      else
        log 'Validation successful.'
        output_allow("Multi-Agent Review Summary:\n\n#{merged}")
      end
    end

    def run_agents_in_parallel(prompt)
      threads = @agent_entries.map do |entry|
        Thread.new do
          summary = AgentFactory.build(entry[:name], timeout: entry[:timeout]).call(prompt)
          evaluator = ResponseEvaluator.new(summary, min_quality_score:
            @config.dig('decision', 'min_quality_score') || ResponseEvaluator::DEFAULT_MIN_QUALITY_SCORE)
          { agent: entry[:name], summary: summary, evaluator: evaluator }
        rescue AgentExecutionError, AgentTimeoutError => e
          { agent: entry[:name], error: e.message }
        end
      end
      threads.map(&:value)
    end

    def format_merged_summary(results)
      results.map do |r|
        header = "## #{r[:agent].capitalize} Review"
        body = r[:summary] || "Error: #{r[:error]}"
        "#{header}\n\n#{body}"
      end.join("\n\n---\n\n")
    end

    def agent_names
      @agent_entries.map { |e| e[:name] }
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

      tracked = case diff_mode
                when 'cached'
                  out, _err, status = Open3.capture3('git', 'diff', '--name-only', '--cached', chdir: @cwd)
                  log "git diff --cached failed: #{_err}" unless status.success?
                  out.split("\n")
                when 'combined'
                  cached, _err1, status1 = Open3.capture3('git', 'diff', '--name-only', '--cached', chdir: @cwd)
                  log "git diff --cached failed: #{_err1}" unless status1.success?
                  unstaged, _err2, status2 = Open3.capture3('git', 'diff', '--name-only', chdir: @cwd)
                  log "git diff failed: #{_err2}" unless status2.success?
                  (cached.split("\n") | unstaged.split("\n"))
                else
                  out, _err, status = Open3.capture3('git', 'diff', '--name-only', 'HEAD', chdir: @cwd)
                  log "git diff HEAD failed: #{_err}" unless status.success?
                  out.split("\n")
                end

      untracked, _err, status = Open3.capture3('git', 'ls-files', '--others', '--exclude-standard', chdir: @cwd)
      log "git ls-files failed: #{_err}" unless status.success?
      (tracked | untracked.split("\n"))
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
      @log_file ||= @log || open_log_file || :none
      @log_file.puts("[Agent Validator] #{msg}") unless @log_file == :none
      @stderr.puts("[Agent Validator] #{msg}") if @verbose
    rescue IOError, SystemCallError
      # Logging failure should not crash the validator
      nil
    end

    def open_log_file
      path = File.join(@cwd || Dir.pwd, '.agent-hook-validator.log')
      File.open(path, 'a')
    rescue IOError, SystemCallError
      nil
    end

    def close_log_file
      return unless @log_file
      return if @log_file == @log || @log_file == :none

      @log_file.close unless @log_file.closed?
    end
  end
end
