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
      end

      it 'preserves defaults for non-overridden keys' do
        path = File.join(fixtures_path, 'config_custom.yml')
        config = described_class.load(path)

        expect(config.dig('git', 'exclude_patterns')).to eq(['*.lock', '*.min.js', 'vendor/**'])
      end

      it 'applies overridden decision values from custom config' do
        path = File.join(fixtures_path, 'config_custom.yml')
        config = described_class.load(path)

        expect(config.dig('decision', 'block_on_agent_failure')).to eq(true)
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

  describe '.deep_merge with new top-level key' do
    it 'includes keys from override not present in base' do
      path = File.join(fixtures_path, 'config_custom.yml')
      config = described_class.load(path)

      # config_custom.yml has 'decision' key with block_on_agent_failure: true
      # which overrides the default false, proving override.reject branch works
      expect(config.dig('decision', 'block_on_agent_failure')).to eq(true)
    end
  end

  describe '.resolve_path fallback to default.yml' do
    it 'falls back to config/default.yml when no path or env given' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('AGENT_HOOK_CONFIG', nil).and_return(nil)

      config = described_class.load(nil)
      expect(config.dig('agent', 'name')).to eq('gemini')
    end
  end

  describe '.load with empty YAML file' do
    it 'returns defaults when YAML file is empty' do
      empty_yaml = File.join(fixtures_path, 'config_empty.yml')
      FileUtils.mkdir_p(fixtures_path) unless File.directory?(fixtures_path)
      File.write(empty_yaml, '')

      config = described_class.load(empty_yaml)
      expect(config.dig('agent', 'name')).to eq('gemini')
      expect(config.dig('git', 'diff_mode')).to eq('head')
    ensure
      FileUtils.rm_f(empty_yaml)
    end
  end

  describe '#dig' do
    it 'accesses nested values' do
      config = described_class.load(nil)
      expect(config.dig('agent', 'timeout_seconds')).to eq(300)
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
