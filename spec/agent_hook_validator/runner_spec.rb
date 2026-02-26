# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe AgentHookValidator::Runner do
  let(:fixtures_path) { File.expand_path('../fixtures', __dir__) }
  let(:input_json) { File.read(File.join(fixtures_path, 'sample_input.json')) }
  let(:stdin) { StringIO.new(input_json) }
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:options) { { agent: 'gemini' } }
  let(:success_status) { instance_double(Process::Status, success?: true) }
  let(:failed_status) { instance_double(Process::Status, success?: false) }
  let(:project_cwd) { '/tmp/test-project' }

  let(:log_io) { StringIO.new }

  before { FileUtils.mkdir_p(project_cwd) }
  after { FileUtils.rm_rf(project_cwd) }

  subject(:runner) { described_class.new(options, stdin: stdin, stdout: stdout, stderr: stderr, log: log_io) }

  def stub_git(changed_files:, untracked: [])
    allow(Open3).to receive(:capture3)
      .with('git', 'rev-parse', '--is-inside-work-tree', chdir: project_cwd)
      .and_return(['true', '', success_status])
    files_output = changed_files.empty? ? '' : "#{changed_files.join("\n")}\n"
    allow(Open3).to receive(:capture3)
      .with('git', 'diff', '--name-only', 'HEAD', chdir: project_cwd)
      .and_return([files_output, '', success_status])
    untracked_output = untracked.empty? ? '' : "#{untracked.join("\n")}\n"
    allow(Open3).to receive(:capture3)
      .with('git', 'ls-files', '--others', '--exclude-standard', chdir: project_cwd)
      .and_return([untracked_output, '', success_status])
  end

  def stub_git_cached(changed_files:, untracked: [])
    allow(Open3).to receive(:capture3)
      .with('git', 'rev-parse', '--is-inside-work-tree', chdir: project_cwd)
      .and_return(['true', '', success_status])
    files_output = changed_files.empty? ? '' : "#{changed_files.join("\n")}\n"
    allow(Open3).to receive(:capture3)
      .with('git', 'diff', '--name-only', '--cached', chdir: project_cwd)
      .and_return([files_output, '', success_status])
    untracked_output = untracked.empty? ? '' : "#{untracked.join("\n")}\n"
    allow(Open3).to receive(:capture3)
      .with('git', 'ls-files', '--others', '--exclude-standard', chdir: project_cwd)
      .and_return([untracked_output, '', success_status])
  end

  describe '#run' do
    context 'when there is no input (empty stdin)' do
      let(:stdin) { StringIO.new('') }

      before do
        allow(Open3).to receive(:capture3)
          .with('git', 'rev-parse', '--is-inside-work-tree', chdir: Dir.pwd)
          .and_return(['true', '', success_status])
        allow(Open3).to receive(:capture3)
          .with('git', 'diff', '--name-only', 'HEAD', chdir: Dir.pwd)
          .and_return(['', '', success_status])
        allow(Open3).to receive(:capture3)
          .with('git', 'ls-files', '--others', '--exclude-standard', chdir: Dir.pwd)
          .and_return(['', '', success_status])
      end

      it 'falls back to Dir.pwd and continues validation' do
        expect(runner.run).to eq(0)
        parsed = JSON.parse(stdout.string)
        expect(parsed['decision']).to eq('allow')
      end
    end

    context 'when stdin is a TTY' do
      let(:stdin) do
        io = StringIO.new
        allow(io).to receive(:tty?).and_return(true)
        io
      end

      before do
        allow(Open3).to receive(:capture3)
          .with('git', 'rev-parse', '--is-inside-work-tree', chdir: Dir.pwd)
          .and_return(['true', '', success_status])
        allow(Open3).to receive(:capture3)
          .with('git', 'diff', '--name-only', 'HEAD', chdir: Dir.pwd)
          .and_return(['', '', success_status])
        allow(Open3).to receive(:capture3)
          .with('git', 'ls-files', '--others', '--exclude-standard', chdir: Dir.pwd)
          .and_return(['', '', success_status])
      end

      it 'falls back to Dir.pwd and continues validation without hanging' do
        expect(runner.run).to eq(0)
        parsed = JSON.parse(stdout.string)
        expect(parsed['decision']).to eq('allow')
      end
    end

    context 'when not in a git repository' do
      before do
        allow(Open3).to receive(:capture3)
          .with('git', 'rev-parse', '--is-inside-work-tree', chdir: project_cwd)
          .and_return(['false', 'fatal: not a git repository', failed_status])
      end

      it 'allows with exit code 0 and outputs allow decision' do
        expect(runner.run).to eq(0)
        parsed = JSON.parse(stdout.string)
        expect(parsed['decision']).to eq('allow')
      end
    end

    context 'when no changed files' do
      before do
        stub_git(changed_files: [])
      end

      it 'allows with exit code 0 and outputs allow decision' do
        expect(runner.run).to eq(0)
        parsed = JSON.parse(stdout.string)
        expect(parsed['decision']).to eq('allow')
      end
    end

    context 'when agent returns clean review' do
      let(:ok_response) { File.read(File.join(fixtures_path, 'agent_response_ok.txt')) }
      let(:agent) { instance_double(AgentHookValidator::Agents::Gemini) }

      before do
        stub_git(changed_files: ['app/models/user.rb'])

        allow(agent).to receive(:call).and_return(ok_response)
        allow(AgentHookValidator::AgentFactory).to receive(:build).and_return(agent)
      end

      it 'allows with summary in JSON output' do
        expect(runner.run).to eq(0)
        parsed = JSON.parse(stdout.string)
        expect(parsed['decision']).to eq('allow')
        expect(parsed['systemMessage']).to include('Code Quality Score')

        expect(agent).to have_received(:call).with(
          a_string_including('app/models/user.rb')
        )
      end
    end

    context 'when agent returns critical issues' do
      let(:critical_response) { File.read(File.join(fixtures_path, 'agent_response_critical.txt')) }
      let(:agent) { instance_double(AgentHookValidator::Agents::Gemini) }

      before do
        stub_git(changed_files: ['app/models/user.rb'])

        allow(agent).to receive(:call).and_return(critical_response)
        allow(AgentHookValidator::AgentFactory).to receive(:build).and_return(agent)
      end

      it 'blocks with reason in JSON output' do
        expect(runner.run).to eq(0)
        parsed = JSON.parse(stdout.string)
        expect(parsed['decision']).to eq('block')
        expect(parsed['reason']).to include('CRITICAL')

        expect(agent).to have_received(:call).with(
          a_string_including('app/models/user.rb')
        )
      end
    end

    context 'when agent returns low quality score' do
      let(:agent) { instance_double(AgentHookValidator::Agents::Gemini) }

      before do
        stub_git(changed_files: ['app/models/user.rb'])

        allow(agent).to receive(:call).and_return("All looks okay.\n\nCode Quality Score: 8/10")
        allow(AgentHookValidator::AgentFactory).to receive(:build).and_return(agent)
      end

      it 'blocks due to score below threshold' do
        expect(runner.run).to eq(0)
        parsed = JSON.parse(stdout.string)
        expect(parsed['decision']).to eq('block')
        expect(parsed['reason']).to include('AgentHookValidator')
      end
    end

    context 'when agent returns other issues' do
      let(:agent) { instance_double(AgentHookValidator::Agents::Gemini) }

      before do
        stub_git(changed_files: ['app/models/user.rb'])

        response = "Summary\n\nCode Quality Score: 9/10\n\n### Other Issues\n- Minor naming issue in `user.rb:10`"
        allow(agent).to receive(:call).and_return(response)
        allow(AgentHookValidator::AgentFactory).to receive(:build).and_return(agent)
      end

      it 'blocks due to other issues' do
        expect(runner.run).to eq(0)
        parsed = JSON.parse(stdout.string)
        expect(parsed['decision']).to eq('block')
        expect(parsed['reason']).to include('AgentHookValidator')
      end
    end

    context 'when agent fails and block_on_agent_failure is false' do
      let(:agent) { instance_double(AgentHookValidator::Agents::Gemini) }

      before do
        stub_git(changed_files: ['app/models/user.rb'])

        allow(agent).to receive(:call).and_raise(AgentHookValidator::AgentExecutionError, 'CLI crashed')
        allow(AgentHookValidator::AgentFactory).to receive(:build).and_return(agent)
      end

      it 'allows with error in JSON output (fail-open)' do
        expect(runner.run).to eq(0)
        parsed = JSON.parse(stdout.string)
        expect(parsed['decision']).to eq('allow')
        expect(parsed['systemMessage']).to include('CLI crashed')
        expect(agent).to have_received(:call).with(
          a_string_including('app/models/user.rb')
        )
      end
    end

    context 'when agent fails and block_on_agent_failure is true' do
      let(:options) { { agent: 'claude', config: File.join(fixtures_path, 'config_custom.yml') } }
      let(:agent) { instance_double(AgentHookValidator::Agents::Claude) }

      before do
        stub_git_cached(changed_files: ['app/models/user.rb'])

        allow(agent).to receive(:call).and_raise(AgentHookValidator::AgentExecutionError, 'API down')
        allow(AgentHookValidator::AgentFactory).to receive(:build).and_return(agent)
      end

      it 'blocks with error in JSON output (fail-closed)' do
        expect(runner.run).to eq(0)
        parsed = JSON.parse(stdout.string)
        expect(parsed['decision']).to eq('block')
        expect(parsed['reason']).to include('API down')

        expect(agent).to have_received(:call).with(
          a_string_including('app/models/user.rb')
        )
      end
    end

    context 'with exclude_patterns filtering' do
      context 'when all files are excluded' do
        before do
          stub_git(changed_files: ['Gemfile.lock'])
        end

        it 'allows when all files are excluded' do
          expect(runner.run).to eq(0)
          parsed = JSON.parse(stdout.string)
          expect(parsed['decision']).to eq('allow')
        end
      end

      context 'when some files are excluded (partial filtering)' do
        let(:ok_response) { File.read(File.join(fixtures_path, 'agent_response_ok.txt')) }
        let(:agent) { instance_double(AgentHookValidator::Agents::Gemini) }

        before do
          stub_git(changed_files: ['app/models/user.rb', 'Gemfile.lock', 'app/controllers/users_controller.rb'])

          allow(agent).to receive(:call).and_return(ok_response)
          allow(AgentHookValidator::AgentFactory).to receive(:build).and_return(agent)
        end

        it 'passes only non-excluded files to agent' do
          expect(runner.run).to eq(0)

          expect(agent).to have_received(:call).with(
            a_string_including('app/models/user.rb', 'users_controller.rb')
          )
          expect(agent).not_to have_received(:call).with(
            a_string_including('Gemfile.lock')
          )
        end
      end
    end
  end

  describe 'project config' do
    context 'when project has .agent-hook-validator.yml' do
      let(:options) { {} }
      let(:ok_response) { File.read(File.join(fixtures_path, 'agent_response_ok.txt')) }
      let(:agent) { instance_double(AgentHookValidator::Agents::Claude) }

      before do
        File.write(File.join(project_cwd, '.agent-hook-validator.yml'), <<~YAML)
          agent:
            name: claude
        YAML

        stub_git(changed_files: ['app/models/user.rb'])
        allow(agent).to receive(:call).and_return(ok_response)
        allow(AgentHookValidator::AgentFactory).to receive(:build).and_return(agent)
      end

      it 'uses agent from project config' do
        runner.run
        expect(AgentHookValidator::AgentFactory).to have_received(:build).with('claude', timeout: 300)
      end
    end

    context 'when CLI --agent overrides project config' do
      let(:options) { { agent: 'gemini' } }
      let(:ok_response) { File.read(File.join(fixtures_path, 'agent_response_ok.txt')) }
      let(:agent) { instance_double(AgentHookValidator::Agents::Gemini) }

      before do
        File.write(File.join(project_cwd, '.agent-hook-validator.yml'), <<~YAML)
          agent:
            name: claude
        YAML

        stub_git(changed_files: ['app/models/user.rb'])
        allow(agent).to receive(:call).and_return(ok_response)
        allow(AgentHookValidator::AgentFactory).to receive(:build).and_return(agent)
      end

      it 'uses agent from CLI flag, not project config' do
        runner.run
        expect(AgentHookValidator::AgentFactory).to have_received(:build).with('gemini', timeout: 300)
      end
    end
  end

  describe '#parse_input?' do
    context 'when input is invalid JSON' do
      let(:stdin) { StringIO.new('not valid json{{{') }

      it 'returns 0 with allow decision and logs the error' do
        expect(runner.run).to eq(0)
        parsed = JSON.parse(stdout.string)
        expect(parsed['decision']).to eq('allow')
        expect(parsed['systemMessage']).to include('invalid JSON input')
        expect(log_io.string).to include('Invalid JSON input')
      end
    end
  end

  describe '#resolve_cwd' do
    context 'when cwd points to a non-existent path' do
      let(:input_json) { JSON.generate({ 'cwd' => '/nonexistent/path', 'hook_event_name' => 'TaskCompleted' }) }

      it 'falls back to Dir.pwd and outputs allow decision' do
        allow(Open3).to receive(:capture3)
          .with('git', 'rev-parse', '--is-inside-work-tree', chdir: Dir.pwd)
          .and_return(['true', '', success_status])
        allow(Open3).to receive(:capture3)
          .with('git', 'diff', '--name-only', 'HEAD', chdir: Dir.pwd)
          .and_return(['', '', success_status])
        allow(Open3).to receive(:capture3)
          .with('git', 'ls-files', '--others', '--exclude-standard', chdir: Dir.pwd)
          .and_return(['', '', success_status])

        expect(runner.run).to eq(0)
        parsed = JSON.parse(stdout.string)
        expect(parsed['decision']).to eq('allow')
      end
    end

    context 'when cwd contains path traversal' do
      let(:input_json) { JSON.generate({ 'cwd' => '/tmp/../etc', 'hook_event_name' => 'TaskCompleted' }) }

      it 'resolves to the real path and outputs allow decision' do
        # /tmp/../etc resolves to /etc via File.realpath
        allow(Open3).to receive(:capture3)
          .with('git', 'rev-parse', '--is-inside-work-tree', chdir: '/etc')
          .and_return(['false', 'fatal: not a git repository', failed_status])

        expect(runner.run).to eq(0)
        parsed = JSON.parse(stdout.string)
        expect(parsed['decision']).to eq('allow')
      end
    end
  end

  describe '#log' do
    context 'when log file cannot be written' do
      let(:runner_no_log) { described_class.new(options, stdin: stdin, stdout: stdout, stderr: stderr) }

      it 'does not crash when logging fails' do
        runner_no_log.instance_variable_set(:@cwd, '/nonexistent/dir')
        # Should not raise even though open_log_file will fail
        expect { runner_no_log.send(:log, 'test message') }.not_to raise_error
      end
    end

    context 'when verbose is enabled' do
      let(:verbose_options) { { agent: 'gemini', verbose: true } }
      let(:verbose_runner) { described_class.new(verbose_options, stdin: stdin, stdout: stdout, stderr: stderr, log: log_io) }

      it 'writes log messages to stderr' do
        verbose_runner.instance_variable_set(:@cwd, project_cwd)
        verbose_runner.send(:log, 'test verbose message')
        expect(stderr.string).to include('[Agent Validator] test verbose message')
      end
    end

    context 'when verbose is disabled' do
      it 'does not write log messages to stderr' do
        runner.instance_variable_set(:@cwd, project_cwd)
        runner.send(:log, 'test quiet message')
        expect(stderr.string).to be_empty
      end
    end
  end

  describe '#default_template_path' do
    it 'points to an existing file' do
      path = runner.send(:default_template_path)
      expect(File.exist?(path)).to be true
      expect(path).to end_with('templates/validation.erb')
    end
  end

  describe 'multi-agent execution' do
    let(:options) { {} }
    let(:ok_response) { File.read(File.join(fixtures_path, 'agent_response_ok.txt')) }
    let(:critical_response) { File.read(File.join(fixtures_path, 'agent_response_critical.txt')) }
    let(:claude_agent) { instance_double(AgentHookValidator::Agents::Claude) }
    let(:gemini_agent) { instance_double(AgentHookValidator::Agents::Gemini) }

    before do
      File.write(File.join(project_cwd, '.agent-hook-validator.yml'), <<~YAML)
        agents:
          - name: claude
            timeout_seconds: 120
          - name: gemini
            timeout_seconds: 600
      YAML

      stub_git(changed_files: ['app/models/user.rb'])
    end

    context 'when both agents allow' do
      before do
        allow(claude_agent).to receive(:call).and_return(ok_response)
        allow(gemini_agent).to receive(:call).and_return(ok_response)
        allow(AgentHookValidator::AgentFactory).to receive(:build).with('claude', timeout: 120).and_return(claude_agent)
        allow(AgentHookValidator::AgentFactory).to receive(:build).with('gemini', timeout: 600).and_return(gemini_agent)
      end

      it 'allows with merged summary containing both reviews' do
        expect(runner.run).to eq(0)
        parsed = JSON.parse(stdout.string)
        expect(parsed['decision']).to eq('allow')
        expect(parsed['systemMessage']).to include('## Claude Review')
        expect(parsed['systemMessage']).to include('## Gemini Review')
        expect(parsed['systemMessage']).to include('---')
      end
    end

    context 'when one agent blocks' do
      before do
        allow(claude_agent).to receive(:call).and_return(critical_response)
        allow(gemini_agent).to receive(:call).and_return(ok_response)
        allow(AgentHookValidator::AgentFactory).to receive(:build).with('claude', timeout: 120).and_return(claude_agent)
        allow(AgentHookValidator::AgentFactory).to receive(:build).with('gemini', timeout: 600).and_return(gemini_agent)
      end

      it 'blocks with merged summary' do
        expect(runner.run).to eq(0)
        parsed = JSON.parse(stdout.string)
        expect(parsed['decision']).to eq('block')
        expect(parsed['reason']).to include('## Claude Review')
        expect(parsed['reason']).to include('## Gemini Review')
      end
    end

    context 'when CLI --agent overrides multi-agent config' do
      let(:options) { { agent: 'gemini' } }

      before do
        allow(gemini_agent).to receive(:call).and_return(ok_response)
        allow(AgentHookValidator::AgentFactory).to receive(:build).with('gemini', timeout: 300).and_return(gemini_agent)
      end

      it 'uses single agent from CLI flag' do
        runner.run
        expect(AgentHookValidator::AgentFactory).to have_received(:build).with('gemini', timeout: 300).once
        parsed = JSON.parse(stdout.string)
        expect(parsed['decision']).to eq('allow')
        expect(parsed['systemMessage']).not_to include('## Claude Review')
      end
    end

    context 'when one agent errors and block_on_agent_failure is false' do
      before do
        allow(gemini_agent).to receive(:call).and_return(ok_response)
        allow(claude_agent).to receive(:call).and_raise(AgentHookValidator::AgentExecutionError, 'API down')
        allow(AgentHookValidator::AgentFactory).to receive(:build).with('claude', timeout: 120).and_return(claude_agent)
        allow(AgentHookValidator::AgentFactory).to receive(:build).with('gemini', timeout: 600).and_return(gemini_agent)
      end

      it 'evaluates successful agent only and includes error in summary' do
        expect(runner.run).to eq(0)
        parsed = JSON.parse(stdout.string)
        expect(parsed['decision']).to eq('allow')
        expect(parsed['systemMessage']).to include('## Claude Review')
        expect(parsed['systemMessage']).to include('Error: API down')
        expect(parsed['systemMessage']).to include('## Gemini Review')
      end
    end

    context 'when one agent errors and block_on_agent_failure is true' do
      before do
        File.write(File.join(project_cwd, '.agent-hook-validator.yml'), <<~YAML)
          agents:
            - name: claude
              timeout_seconds: 120
            - name: gemini
              timeout_seconds: 600
          decision:
            block_on_agent_failure: true
        YAML

        allow(gemini_agent).to receive(:call).and_return(ok_response)
        allow(claude_agent).to receive(:call).and_raise(AgentHookValidator::AgentExecutionError, 'API down')
        allow(AgentHookValidator::AgentFactory).to receive(:build).with('claude', timeout: 120).and_return(claude_agent)
        allow(AgentHookValidator::AgentFactory).to receive(:build).with('gemini', timeout: 600).and_return(gemini_agent)
      end

      it 'blocks due to agent error' do
        expect(runner.run).to eq(0)
        parsed = JSON.parse(stdout.string)
        expect(parsed['decision']).to eq('block')
        expect(parsed['reason']).to include('Error: API down')
      end
    end

    context 'per-agent timeout' do
      before do
        allow(claude_agent).to receive(:call).and_return(ok_response)
        allow(gemini_agent).to receive(:call).and_return(ok_response)
        allow(AgentHookValidator::AgentFactory).to receive(:build).with('claude', timeout: 120).and_return(claude_agent)
        allow(AgentHookValidator::AgentFactory).to receive(:build).with('gemini', timeout: 600).and_return(gemini_agent)
      end

      it 'passes correct timeout to each agent' do
        runner.run
        expect(AgentHookValidator::AgentFactory).to have_received(:build).with('claude', timeout: 120)
        expect(AgentHookValidator::AgentFactory).to have_received(:build).with('gemini', timeout: 600)
      end
    end

    context 'when CLI --agent has comma-separated names' do
      let(:options) { { agent: 'gemini,claude' } }

      before do
        allow(gemini_agent).to receive(:call).and_return(ok_response)
        allow(claude_agent).to receive(:call).and_return(ok_response)
        allow(AgentHookValidator::AgentFactory).to receive(:build).with('gemini', timeout: 300).and_return(gemini_agent)
        allow(AgentHookValidator::AgentFactory).to receive(:build).with('claude', timeout: 300).and_return(claude_agent)
      end

      it 'runs multi-agent validation with both agents' do
        expect(runner.run).to eq(0)
        expect(AgentHookValidator::AgentFactory).to have_received(:build).with('gemini', timeout: 300)
        expect(AgentHookValidator::AgentFactory).to have_received(:build).with('claude', timeout: 300)
        parsed = JSON.parse(stdout.string)
        expect(parsed['decision']).to eq('allow')
        expect(parsed['systemMessage']).to include('## Gemini Review')
        expect(parsed['systemMessage']).to include('## Claude Review')
      end
    end

    context 'when CLI --agent has comma-separated names with spaces' do
      let(:options) { { agent: 'gemini, claude' } }

      before do
        allow(gemini_agent).to receive(:call).and_return(ok_response)
        allow(claude_agent).to receive(:call).and_return(ok_response)
        allow(AgentHookValidator::AgentFactory).to receive(:build).with('gemini', timeout: 300).and_return(gemini_agent)
        allow(AgentHookValidator::AgentFactory).to receive(:build).with('claude', timeout: 300).and_return(claude_agent)
      end

      it 'strips whitespace and runs both agents' do
        expect(runner.run).to eq(0)
        expect(AgentHookValidator::AgentFactory).to have_received(:build).with('gemini', timeout: 300)
        expect(AgentHookValidator::AgentFactory).to have_received(:build).with('claude', timeout: 300)
      end
    end
  end

  describe 'git worktree integration' do
    let(:repo_dir) { Dir.mktmpdir('test-repo') }
    let(:worktree_dir) { File.join(repo_dir, '.worktrees', 'feature') }
    let(:options) { { agent: 'gemini' } }

    before do
      system('git', 'init', repo_dir, [:out, :err] => File::NULL)
      system('git', '-C', repo_dir, 'config', 'user.email', 'test@test.com')
      system('git', '-C', repo_dir, 'config', 'user.name', 'Test')
      File.write(File.join(repo_dir, 'existing.rb'), 'puts "hello"')
      system('git', '-C', repo_dir, 'add', '.')
      system('git', '-C', repo_dir, 'commit', '-m', 'init', [:out, :err] => File::NULL)

      FileUtils.mkdir_p(File.dirname(worktree_dir))
      system('git', '-C', repo_dir, 'worktree', 'add', worktree_dir, '-b', 'feature', [:out, :err] => File::NULL)

      File.write(File.join(worktree_dir, 'existing.rb'), 'puts "modified"')
      File.write(File.join(worktree_dir, 'new_file.rb'), 'puts "new"')
    end

    after do
      system('git', '-C', repo_dir, 'worktree', 'remove', '--force', worktree_dir, [:out, :err] => File::NULL)
      FileUtils.rm_rf(repo_dir)
    end

    it 'fetch_changed_files sees tracked and untracked files in worktree' do
      runner.instance_variable_set(:@cwd, worktree_dir)
      files = runner.send(:fetch_changed_files)
      expect(files).to include('existing.rb')
      expect(files).to include('new_file.rb')
    end

    it 'git_available? returns true in worktree' do
      runner.instance_variable_set(:@cwd, worktree_dir)
      expect(runner.send(:git_available?)).to be true
    end

    it 'fetch_changed_files sees staged files in worktree with cached mode' do
      system('git', '-C', worktree_dir, 'add', 'new_file.rb')

      config = AgentHookValidator::Config.new(
        'git' => { 'diff_mode' => 'cached', 'exclude_patterns' => [] },
        'agent' => { 'name' => 'gemini', 'timeout_seconds' => 120 },
        'decision' => { 'block_on_agent_failure' => false }
      )
      runner.instance_variable_set(:@cwd, worktree_dir)
      runner.instance_variable_set(:@config, config)

      files = runner.send(:fetch_changed_files)
      expect(files).to include('new_file.rb')
    end
  end

  describe '#fetch_changed_files' do
    before { runner.instance_variable_set(:@cwd, project_cwd) }

    def configure_diff_mode(mode)
      config = AgentHookValidator::Config.new(
        'git' => { 'diff_mode' => mode, 'exclude_patterns' => [] },
        'agent' => { 'name' => 'gemini', 'timeout_seconds' => 120 },
        'decision' => { 'block_on_agent_failure' => false }
      )
      runner.instance_variable_set(:@config, config)
    end

    def stub_no_untracked
      allow(Open3).to receive(:capture3).with('git', 'ls-files', '--others', '--exclude-standard', chdir: project_cwd)
                                        .and_return(['', '', success_status])
    end

    context 'with combined mode' do
      it 'returns union of cached, unstaged, and untracked files' do
        configure_diff_mode('combined')

        allow(Open3).to receive(:capture3).with('git', 'diff', '--name-only', '--cached', chdir: project_cwd)
                                          .and_return(["file_a.rb\nfile_b.rb\n", '', success_status])
        allow(Open3).to receive(:capture3).with('git', 'diff', '--name-only', chdir: project_cwd)
                                          .and_return(["file_b.rb\nfile_c.rb\n", '', success_status])
        stub_no_untracked

        files = runner.send(:fetch_changed_files)
        expect(files).to match_array(%w[file_a.rb file_b.rb file_c.rb])
      end
    end

    context 'with cached mode' do
      it 'returns staged and untracked files' do
        configure_diff_mode('cached')

        allow(Open3).to receive(:capture3).with('git', 'diff', '--name-only', '--cached', chdir: project_cwd)
                                          .and_return(["staged.rb\n", '', success_status])
        stub_no_untracked

        files = runner.send(:fetch_changed_files)
        expect(files).to eq(['staged.rb'])
      end
    end

    context 'with head mode' do
      it 'returns files from HEAD diff' do
        configure_diff_mode('head')

        allow(Open3).to receive(:capture3).with('git', 'diff', '--name-only', 'HEAD', chdir: project_cwd)
                                          .and_return(["all.rb\n", '', success_status])
        stub_no_untracked

        files = runner.send(:fetch_changed_files)
        expect(files).to eq(['all.rb'])
      end
    end

    context 'with untracked files' do
      it 'includes untracked files in the result' do
        configure_diff_mode('head')

        allow(Open3).to receive(:capture3).with('git', 'diff', '--name-only', 'HEAD', chdir: project_cwd)
                                          .and_return(["tracked.rb\n", '', success_status])
        allow(Open3).to receive(:capture3).with('git', 'ls-files', '--others', '--exclude-standard', chdir: project_cwd)
                                          .and_return(["new_file.rb\nanother_new.rb\n", '', success_status])

        files = runner.send(:fetch_changed_files)
        expect(files).to match_array(%w[tracked.rb new_file.rb another_new.rb])
      end

      it 'deduplicates files appearing in both tracked and untracked' do
        configure_diff_mode('head')

        allow(Open3).to receive(:capture3).with('git', 'diff', '--name-only', 'HEAD', chdir: project_cwd)
                                          .and_return(["shared.rb\n", '', success_status])
        allow(Open3).to receive(:capture3).with('git', 'ls-files', '--others', '--exclude-standard', chdir: project_cwd)
                                          .and_return(["shared.rb\nnew.rb\n", '', success_status])

        files = runner.send(:fetch_changed_files)
        expect(files).to match_array(%w[shared.rb new.rb])
      end
    end
  end
end
