# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AgentHookValidator::Agents::Gemini do
  subject(:agent) { described_class.new(timeout: 10) }

  describe '#call' do
    it 'executes gemini CLI and returns stdout' do
      stdin = instance_double(IO, write: nil, close: nil, closed?: true)
      stdout = instance_double(IO, read: "No issues found\n", closed?: true)
      stderr = instance_double(IO, read: '', closed?: true)
      status = instance_double(Process::Status, success?: true, exitstatus: 0)
      wait_thr = instance_double(Process::Waiter, pid: 12_345, value: status, join: true)

      allow(Open3).to receive(:popen3).with('gemini', '-p', '-')
                                      .and_return([stdin, stdout, stderr, wait_thr])

      result = agent.call('test prompt')
      expect(result).to eq('No issues found')
      expect(stdin).to have_received(:write).with('test prompt')
      expect(stdin).to have_received(:close).at_least(:once)
    end

    it 'raises AgentExecutionError on non-zero exit' do
      stdin = instance_double(IO, write: nil, close: nil, closed?: true)
      stdout = instance_double(IO, read: '', closed?: true)
      stderr = instance_double(IO, read: 'gemini: not found', closed?: true)
      status = instance_double(Process::Status, success?: false, exitstatus: 127)
      wait_thr = instance_double(Process::Waiter, pid: 12_345, value: status, join: true)

      allow(Open3).to receive(:popen3).and_return([stdin, stdout, stderr, wait_thr])

      expect { agent.call('prompt') }.to raise_error(
        AgentHookValidator::AgentExecutionError, /Gemini CLI error.*exit 127/
      )
    end

    it 'raises AgentTimeoutError when timeout expires' do
      stdin = instance_double(IO, write: nil, close: nil, closed?: true)
      stdout = instance_double(IO, closed?: true)
      stderr = instance_double(IO, closed?: true)
      wait_thr = instance_double(Process::Waiter, pid: 12_345, join: nil)

      allow(Open3).to receive(:popen3).and_return([stdin, stdout, stderr, wait_thr])
      allow(agent).to receive(:kill_process)

      expect { agent.call('prompt') }.to raise_error(
        AgentHookValidator::AgentTimeoutError, /Gemini timed out after 10s/
      )
    end
  end
end
