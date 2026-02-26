# frozen_string_literal: true

require 'spec_helper'

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

  def stub_git(changed_files:)
    allow(Open3).to receive(:capture3)
      .with('git', 'rev-parse', '--is-inside-work-tree', chdir: project_cwd)
      .and_return(['true', '', success_status])
    files_output = changed_files.empty? ? '' : "#{changed_files.join("\n")}\n"
    allow(Open3).to receive(:capture3)
      .with('git', 'diff', '--name-only', 'HEAD', chdir: project_cwd)
      .and_return([files_output, '', nil])
  end

  def stub_git_cached(changed_files:)
    allow(Open3).to receive(:capture3)
      .with('git', 'rev-parse', '--is-inside-work-tree', chdir: project_cwd)
      .and_return(['true', '', success_status])
    files_output = changed_files.empty? ? '' : "#{changed_files.join("\n")}\n"
    allow(Open3).to receive(:capture3)
      .with('git', 'diff', '--name-only', '--cached', chdir: project_cwd)
      .and_return([files_output, '', nil])
  end

  describe '#run' do
    context 'when there is no input' do
      let(:stdin) { StringIO.new('') }

      it 'returns 0 without output' do
        expect(runner.run).to eq(0)
        expect(stdout.string).to be_empty
      end
    end

    context 'when not in a git repository' do
      before do
        allow(Open3).to receive(:capture3)
          .with('git', 'rev-parse', '--is-inside-work-tree', chdir: project_cwd)
          .and_return(['false', 'fatal: not a git repository', failed_status])
      end

      it 'allows with exit code 0' do
        expect(runner.run).to eq(0)
      end
    end

    context 'when no changed files' do
      before do
        stub_git(changed_files: [])
      end

      it 'allows with exit code 0' do
        expect(runner.run).to eq(0)
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

  describe '#parse_input?' do
    context 'when input is invalid JSON' do
      let(:stdin) { StringIO.new('not valid json{{{') }

      it 'returns 0 without output and logs the error' do
        expect(runner.run).to eq(0)
        expect(stdout.string).to be_empty
        expect(log_io.string).to include('Invalid JSON input')
      end
    end
  end

  describe '#resolve_cwd' do
    context 'when cwd points to a non-existent path' do
      let(:input_json) { JSON.generate({ 'cwd' => '/nonexistent/path', 'hook_event_name' => 'TaskCompleted' }) }

      it 'falls back to Dir.pwd' do
        allow(Open3).to receive(:capture3)
          .with('git', 'rev-parse', '--is-inside-work-tree', chdir: Dir.pwd)
          .and_return(['true', '', success_status])
        allow(Open3).to receive(:capture3)
          .with('git', 'diff', '--name-only', 'HEAD', chdir: Dir.pwd)
          .and_return(['', '', nil])

        expect(runner.run).to eq(0)
      end
    end

    context 'when cwd contains path traversal' do
      let(:input_json) { JSON.generate({ 'cwd' => '/tmp/../etc', 'hook_event_name' => 'TaskCompleted' }) }

      it 'resolves to the real path' do
        # /tmp/../etc resolves to /etc via File.realpath
        allow(Open3).to receive(:capture3)
          .with('git', 'rev-parse', '--is-inside-work-tree', chdir: '/etc')
          .and_return(['false', 'fatal: not a git repository', failed_status])

        expect(runner.run).to eq(0)
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
  end

  describe '#default_template_path' do
    it 'points to an existing file' do
      path = runner.send(:default_template_path)
      expect(File.exist?(path)).to be true
      expect(path).to end_with('templates/validation.erb')
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

    context 'with combined mode' do
      it 'returns union of cached and unstaged files' do
        configure_diff_mode('combined')

        allow(Open3).to receive(:capture3).with('git', 'diff', '--name-only', '--cached', chdir: project_cwd)
                                          .and_return(["file_a.rb\nfile_b.rb\n", '', nil])
        allow(Open3).to receive(:capture3).with('git', 'diff', '--name-only', chdir: project_cwd)
                                          .and_return(["file_b.rb\nfile_c.rb\n", '', nil])

        files = runner.send(:fetch_changed_files)
        expect(files).to match_array(%w[file_a.rb file_b.rb file_c.rb])
      end
    end

    context 'with cached mode' do
      it 'returns only staged files' do
        configure_diff_mode('cached')

        allow(Open3).to receive(:capture3).with('git', 'diff', '--name-only', '--cached', chdir: project_cwd)
                                          .and_return(["staged.rb\n", '', nil])

        files = runner.send(:fetch_changed_files)
        expect(files).to eq(['staged.rb'])
      end
    end

    context 'with head mode' do
      it 'returns files from HEAD diff' do
        configure_diff_mode('head')

        allow(Open3).to receive(:capture3).with('git', 'diff', '--name-only', 'HEAD', chdir: project_cwd)
                                          .and_return(["all.rb\n", '', nil])

        files = runner.send(:fetch_changed_files)
        expect(files).to eq(['all.rb'])
      end
    end
  end
end
