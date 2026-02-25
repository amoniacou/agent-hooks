# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AgentHookValidator::Config do
  let(:fixtures_path) { File.expand_path('../fixtures', __dir__) }

  describe '.load' do
    context 'with no path provided' do
      it 'returns config with defaults' do
        config = described_class.load(nil)
        expect(config.dig('agent', 'name')).to eq('gemini')
        expect(config.dig('git', 'diff_mode')).to eq('head')
        expect(config.dig('git', 'max_diff_lines')).to eq(2000)
        expect(config.dig('decision', 'block_on_agent_failure')).to eq(false)
      end
    end

    context 'with a custom config path' do
      it 'merges custom values over defaults' do
        path = File.join(fixtures_path, 'config_custom.yml')
        config = described_class.load(path)

        expect(config.dig('agent', 'name')).to eq('claude')
        expect(config.dig('agent', 'timeout_seconds')).to eq(60)
        expect(config.dig('git', 'diff_mode')).to eq('cached')
        expect(config.dig('git', 'max_diff_lines')).to eq(500)
      end

      it 'preserves defaults for non-overridden keys' do
        path = File.join(fixtures_path, 'config_custom.yml')
        config = described_class.load(path)

        expect(config.dig('git', 'exclude_patterns')).to eq(['*.lock', '*.min.js', 'vendor/**'])
        expect(config.dig('thresholds', 'max_critical_issues')).to eq(0)
      end
    end

    context 'with invalid YAML' do
      it 'raises ConfigLoadError' do
        path = File.join(fixtures_path, 'config_invalid.yml')
        expect { described_class.load(path) }.to raise_error(AgentHookValidator::ConfigLoadError, /Invalid YAML/)
      end
    end

    context 'with non-existent path' do
      it 'returns defaults' do
        config = described_class.load('/tmp/nonexistent_config_12345.yml')
        expect(config.dig('agent', 'name')).to eq('gemini')
      end
    end

    context 'with ENV override' do
      it 'loads from AGENT_HOOK_CONFIG env var' do
        path = File.join(fixtures_path, 'config_custom.yml')
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with('AGENT_HOOK_CONFIG', nil).and_return(path)

        config = described_class.load(nil)
        expect(config.dig('agent', 'name')).to eq('claude')
      end
    end
  end

  describe '#dig' do
    it 'accesses nested values' do
      config = described_class.load(nil)
      expect(config.dig('thresholds', 'require_tests_for_new_code')).to eq(true)
    end
  end

  describe '#[]' do
    it 'accesses top-level keys' do
      config = described_class.load(nil)
      expect(config['agent']).to be_a(Hash)
      expect(config['agent']['name']).to eq('gemini')
    end
  end
end
