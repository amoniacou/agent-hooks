# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AgentHookValidator::Agents::OpenAI do
  subject(:agent) { described_class.new(timeout: 10) }

  describe '#call' do
    it 'executes openai CLI and returns stdout' do
      stdin = instance_double(IO, write: nil, close: nil, closed?: true)
      stdout = instance_double(IO, read: "All good\n", closed?: true)
      stderr = instance_double(IO, read: '', closed?: true)
      status = instance_double(Process::Status, success?: true, exitstatus: 0)
      wait_thr = instance_double(Process::Waiter, pid: 12_345, value: status, join: true)

      allow(Open3).to receive(:popen3)
        .with('codex', 'exec', '-')
        .and_return([stdin, stdout, stderr, wait_thr])

      result = agent.call('test prompt')
      expect(result).to eq('All good')
      expect(stdin).to have_received(:write).with('test prompt')
      expect(stdin).to have_received(:close).at_least(:once)
    end

    it 'raises AgentExecutionError on failure' do
      stdin = instance_double(IO, write: nil, close: nil, closed?: true)
      stdout = instance_double(IO, read: '', closed?: true)
      stderr = instance_double(IO, read: 'API error', closed?: true)
      status = instance_double(Process::Status, success?: false, exitstatus: 2)
      wait_thr = instance_double(Process::Waiter, pid: 12_345, value: status, join: true)

      allow(Open3).to receive(:popen3).and_return([stdin, stdout, stderr, wait_thr])

      expect { agent.call('prompt') }.to raise_error(
        AgentHookValidator::AgentExecutionError, /Codex CLI error/
      )
    end
  end
end
