# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AgentHookValidator::Agents::Claude do
  subject(:agent) { described_class.new(timeout: 10) }

  describe '#call' do
    it 'executes claude CLI and returns stdout' do
      status = instance_double(Process::Status, success?: true, exitstatus: 0)
      allow(Open3).to receive(:capture3)
        .with('claude', '-p', '-', stdin_data: 'test prompt')
        .and_return(["Review looks good\n", '', status])

      result = agent.call('test prompt')
      expect(result).to eq('Review looks good')
    end

    it 'raises AgentExecutionError on non-zero exit' do
      status = instance_double(Process::Status, success?: false, exitstatus: 1)
      allow(Open3).to receive(:capture3)
        .and_return(['', 'command not found', status])

      expect { agent.call('prompt') }.to raise_error(
        AgentHookValidator::AgentExecutionError, /Claude CLI error.*exit 1/
      )
    end

    it 'raises AgentTimeoutError when timeout expires' do
      allow(Open3).to receive(:capture3) { sleep 20 }

      expect { agent.call('prompt') }.to raise_error(
        AgentHookValidator::AgentTimeoutError, /Claude timed out after 10s/
      )
    end
  end
end
