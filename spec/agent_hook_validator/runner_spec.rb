# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AgentHookValidator::Runner do
  let(:fixtures_path) { File.expand_path('../fixtures', __dir__) }
  let(:input_json) { File.read(File.join(fixtures_path, 'sample_input.json')) }
  let(:sample_diff) { File.read(File.join(fixtures_path, 'sample_diff.txt')) }
  let(:multi_file_diff) { File.read(File.join(fixtures_path, 'multi_file_diff.txt')) }
  let(:stdin) { StringIO.new(input_json) }
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:options) { { agent: 'gemini' } }

  subject(:runner) { described_class.new(options, stdin: stdin, stdout: stdout, stderr: stderr) }

  def parsed_output
    JSON.parse(stdout.string)
  end

  describe '#run' do
    context 'when there is no input' do
      let(:stdin) { StringIO.new('') }

      it 'returns nil without output' do
        runner.run
        expect(stdout.string).to be_empty
      end
    end

    context 'when not in a git repository' do
      before do
        allow(runner).to receive(:git_available?).and_return(false)
      end

      it 'outputs allow decision' do
        runner.run
        expect(parsed_output['decision']).to eq('allow')
      end
    end

    context 'when diff is empty' do
      before do
        allow(runner).to receive(:git_available?).and_return(true)
        allow(runner).to receive(:fetch_diff).and_return('')
      end

      it 'outputs allow decision' do
        runner.run
        expect(parsed_output['decision']).to eq('allow')
      end
    end

    context 'when agent returns clean review' do
      let(:ok_response) { File.read(File.join(fixtures_path, 'agent_response_ok.txt')) }

      before do
        allow(runner).to receive(:git_available?).and_return(true)
        allow(runner).to receive(:fetch_diff).and_return(sample_diff)
        allow(runner).to receive(:fetch_changed_files).and_return(['app/models/user.rb'])

        agent = instance_double(AgentHookValidator::Agents::Gemini)
        allow(agent).to receive(:call).and_return(ok_response)
        allow(AgentHookValidator::AgentFactory).to receive(:build).and_return(agent)
      end

      it 'outputs allow decision with summary' do
        runner.run
        expect(parsed_output['decision']).to eq('allow')
        expect(parsed_output['systemMessage']).to include('Code Quality Score')
      end
    end

    context 'when agent returns critical issues' do
      let(:critical_response) { File.read(File.join(fixtures_path, 'agent_response_critical.txt')) }

      before do
        allow(runner).to receive(:git_available?).and_return(true)
        allow(runner).to receive(:fetch_diff).and_return(sample_diff)
        allow(runner).to receive(:fetch_changed_files).and_return(['app/models/user.rb'])

        agent = instance_double(AgentHookValidator::Agents::Gemini)
        allow(agent).to receive(:call).and_return(critical_response)
        allow(AgentHookValidator::AgentFactory).to receive(:build).and_return(agent)
      end

      it 'outputs retry decision with reason' do
        runner.run
        expect(parsed_output['decision']).to eq('retry')
        expect(parsed_output['reason']).to include('CRITICAL')
      end
    end

    context 'when agent fails and block_on_agent_failure is false' do
      before do
        allow(runner).to receive(:git_available?).and_return(true)
        allow(runner).to receive(:fetch_diff).and_return(sample_diff)
        allow(runner).to receive(:fetch_changed_files).and_return(['app/models/user.rb'])

        agent = instance_double(AgentHookValidator::Agents::Gemini)
        allow(agent).to receive(:call).and_raise(AgentHookValidator::AgentExecutionError, 'CLI crashed')
        allow(AgentHookValidator::AgentFactory).to receive(:build).and_return(agent)
      end

      it 'outputs allow decision (fail-open)' do
        runner.run
        expect(parsed_output['decision']).to eq('allow')
        expect(parsed_output['systemMessage']).to include('CLI crashed')
      end
    end

    context 'when agent fails and block_on_agent_failure is true' do
      let(:options) { { agent: 'claude', config: File.join(fixtures_path, 'config_custom.yml') } }

      before do
        allow(runner).to receive(:git_available?).and_return(true)
        allow(runner).to receive(:fetch_diff).and_return(sample_diff)
        allow(runner).to receive(:fetch_changed_files).and_return(['app/models/user.rb'])

        agent = instance_double(AgentHookValidator::Agents::Claude)
        allow(agent).to receive(:call).and_raise(AgentHookValidator::AgentExecutionError, 'API down')
        allow(AgentHookValidator::AgentFactory).to receive(:build).and_return(agent)
      end

      it 'outputs retry decision (fail-closed)' do
        runner.run
        expect(parsed_output['decision']).to eq('retry')
        expect(parsed_output['reason']).to include('API down')
      end
    end

    context 'with exclude_patterns filtering' do
      context 'when all files are excluded' do
        let(:lock_diff) do
          <<~DIFF
            diff --git a/Gemfile.lock b/Gemfile.lock
            index aaaaaaa..bbbbbbb 100644
            --- a/Gemfile.lock
            +++ b/Gemfile.lock
            @@ -10,6 +10,7 @@
            +    newgem (1.0.0)
          DIFF
        end

        before do
          allow(runner).to receive(:git_available?).and_return(true)
          allow(runner).to receive(:fetch_diff).and_return(lock_diff)
          allow(runner).to receive(:fetch_changed_files).and_return(['Gemfile.lock'])
        end

        it 'outputs allow when all files are excluded' do
          runner.run
          expect(parsed_output['decision']).to eq('allow')
        end
      end

      context 'when some files are excluded (partial filtering)' do
        let(:ok_response) { File.read(File.join(fixtures_path, 'agent_response_ok.txt')) }

        before do
          allow(runner).to receive(:git_available?).and_return(true)
          allow(runner).to receive(:fetch_diff).and_return(multi_file_diff)
          allow(runner).to receive(:fetch_changed_files).and_return(
            ['app/models/user.rb', 'Gemfile.lock', 'app/controllers/users_controller.rb']
          )

          agent = instance_double(AgentHookValidator::Agents::Gemini)
          allow(agent).to receive(:call).and_return(ok_response)
          allow(AgentHookValidator::AgentFactory).to receive(:build).and_return(agent)
        end

        it 'passes filtered diff without excluded file sections to agent' do
          runner.run

          expect(AgentHookValidator::AgentFactory).to have_received(:build)
          # The agent was called, meaning diff was non-empty after filtering
          expect(parsed_output['decision']).to eq('allow')
        end
      end
    end
  end

  describe '#filter_diff (via send)' do
    it 'removes excluded file sections from diff' do
      diff = runner.send(:filter_diff, multi_file_diff, [
                           'app/models/user.rb', 'Gemfile.lock', 'app/controllers/users_controller.rb'
                         ])

      expect(diff).to include('app/models/user.rb')
      expect(diff).not_to include('Gemfile.lock')
      expect(diff).to include('app/controllers/users_controller.rb')
    end

    it 'returns full diff when no patterns match' do
      no_lock_diff = <<~DIFF
        diff --git a/app/models/user.rb b/app/models/user.rb
        index 1234567..abcdefg 100644
        --- a/app/models/user.rb
        +++ b/app/models/user.rb
        @@ -1,5 +1,10 @@
        +  validates :name, presence: true
      DIFF

      diff = runner.send(:filter_diff, no_lock_diff, ['app/models/user.rb'])
      expect(diff).to include('app/models/user.rb')
    end

    it 'returns empty string when all sections are excluded' do
      lock_only_diff = <<~DIFF
        diff --git a/Gemfile.lock b/Gemfile.lock
        index aaaaaaa..bbbbbbb 100644
        --- a/Gemfile.lock
        +++ b/Gemfile.lock
        @@ -10,6 +10,7 @@
        +    newgem (1.0.0)
      DIFF

      diff = runner.send(:filter_diff, lock_only_diff, ['Gemfile.lock'])
      expect(diff).to eq('')
    end
  end
end
