# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AgentHookValidator::AgentFactory do
  describe '.build' do
    it 'creates a Claude agent' do
      agent = described_class.build('claude')
      expect(agent).to be_a(AgentHookValidator::Agents::Claude)
    end

    it 'creates an OpenAI agent' do
      agent = described_class.build('openai')
      expect(agent).to be_a(AgentHookValidator::Agents::OpenAI)
    end

    it 'creates a Gemini agent' do
      agent = described_class.build('gemini')
      expect(agent).to be_a(AgentHookValidator::Agents::Gemini)
    end

    it 'is case-insensitive' do
      expect(described_class.build('Claude')).to be_a(AgentHookValidator::Agents::Claude)
      expect(described_class.build('GEMINI')).to be_a(AgentHookValidator::Agents::Gemini)
    end

    it 'passes timeout to agent' do
      agent = described_class.build('claude', timeout: 60)
      expect(agent.timeout).to eq(60)
    end

    it 'raises ArgumentError when agent name is nil' do
      expect { described_class.build(nil) }.to raise_error(ArgumentError, /Agent name is required/)
    end

    it 'raises ArgumentError when agent name is empty' do
      expect { described_class.build('') }.to raise_error(ArgumentError, /Agent name is required/)
    end

    it 'raises ArgumentError for unsupported agent' do
      expect { described_class.build('unknown') }.to raise_error(
        ArgumentError, /Unsupported agent: unknown.*claude, openai, gemini/
      )
    end
  end
end
