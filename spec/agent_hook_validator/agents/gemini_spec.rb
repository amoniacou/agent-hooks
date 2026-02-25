# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AgentHookValidator::Agents::Gemini do
  subject(:agent) { described_class.new(timeout: 10) }

  describe '#call' do
    it 'executes gemini CLI and returns stdout' do
      status = instance_double(Process::Status, success?: true, exitstatus: 0)
      allow(Open3).to receive(:capture3)
        .with('gemini', '-p', '-', stdin_data: 'test prompt')
        .and_return(["No issues found\n", '', status])

      result = agent.call('test prompt')
      expect(result).to eq('No issues found')
    end

    it 'raises AgentExecutionError on non-zero exit' do
      status = instance_double(Process::Status, success?: false, exitstatus: 127)
      allow(Open3).to receive(:capture3)
        .and_return(['', 'gemini: not found', status])

      expect { agent.call('prompt') }.to raise_error(
        AgentHookValidator::AgentExecutionError, /Gemini CLI error.*exit 127/
      )
    end

    it 'raises AgentTimeoutError when timeout expires' do
      allow(Open3).to receive(:capture3) { sleep 20 }

      expect { agent.call('prompt') }.to raise_error(
        AgentHookValidator::AgentTimeoutError, /Gemini timed out after 10s/
      )
    end
  end
end
