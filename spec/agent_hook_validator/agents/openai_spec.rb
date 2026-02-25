# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AgentHookValidator::Agents::OpenAI do
  subject(:agent) { described_class.new(timeout: 10) }

  describe '#call' do
    it 'executes openai CLI and returns stdout' do
      status = instance_double(Process::Status, success?: true, exitstatus: 0)
      allow(Open3).to receive(:capture3)
        .with('openai', 'chat', 'create', '--model', 'gpt-4o', '--message', '-', stdin_data: 'test prompt')
        .and_return(["All good\n", '', status])

      result = agent.call('test prompt')
      expect(result).to eq('All good')
    end

    it 'raises AgentExecutionError on failure' do
      status = instance_double(Process::Status, success?: false, exitstatus: 2)
      allow(Open3).to receive(:capture3)
        .and_return(['', 'API error', status])

      expect { agent.call('prompt') }.to raise_error(
        AgentHookValidator::AgentExecutionError, /OpenAI CLI error/
      )
    end
  end
end
