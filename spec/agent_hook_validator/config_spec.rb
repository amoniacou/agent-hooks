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

  describe '#merge_project_config' do
    let(:project_dir) { Dir.mktmpdir }

    after { FileUtils.rm_rf(project_dir) }

    context 'when project config exists' do
      before do
        File.write(File.join(project_dir, '.agent-hook-validator.yml'), <<~YAML)
          agent:
            name: claude
        YAML
      end

      it 'merges project config over current config' do
        config = described_class.load(nil)
        merged = config.merge_project_config(project_dir)

        expect(merged.dig('agent', 'name')).to eq('claude')
        expect(merged.dig('agent', 'timeout_seconds')).to eq(300)
        expect(merged.dig('git', 'diff_mode')).to eq('head')
      end
    end

    context 'when project config adds exclude_patterns' do
      before do
        File.write(File.join(project_dir, '.agent-hook-validator.yml'), <<~YAML)
          git:
            exclude_patterns:
              - "*.generated.ts"
        YAML
      end

      it 'unions project patterns with default patterns' do
        config = described_class.load(nil)
        merged = config.merge_project_config(project_dir)

        patterns = merged.dig('git', 'exclude_patterns')
        expect(patterns).to include('*.lock', '*.min.js', 'vendor/**', '*.generated.ts')
      end
    end

    context 'when project config does not exist' do
      it 'returns self unchanged' do
        config = described_class.load(nil)
        result = config.merge_project_config(project_dir)

        expect(result).to be(config)
      end
    end

    context 'when project config has invalid YAML' do
      before do
        File.write(File.join(project_dir, '.agent-hook-validator.yml'), "invalid: yaml: {{{")
      end

      it 'raises ConfigLoadError' do
        config = described_class.load(nil)
        expect { config.merge_project_config(project_dir) }
          .to raise_error(AgentHookValidator::ConfigLoadError, /Invalid project YAML config/)
      end
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

  describe '#agent_entries' do
    context 'with default config (agent.name only)' do
      it 'returns single entry with agent name and timeout' do
        config = described_class.load(nil)
        expect(config.agent_entries).to eq([{ name: 'gemini', timeout: 300 }])
      end
    end

    context 'with agents array and per-agent timeouts' do
      it 'returns entries with per-agent timeouts' do
        config = described_class.new(
          'agent' => { 'name' => 'gemini', 'timeout_seconds' => 120 },
          'agents' => [
            { 'name' => 'claude', 'timeout_seconds' => 60 },
            { 'name' => 'gemini', 'timeout_seconds' => 600 }
          ]
        )
        expect(config.agent_entries).to eq([
          { name: 'claude', timeout: 60 },
          { name: 'gemini', timeout: 600 }
        ])
      end
    end

    context 'with agents array without per-agent timeouts' do
      it 'falls back to global agent timeout' do
        config = described_class.new(
          'agent' => { 'name' => 'gemini', 'timeout_seconds' => 200 },
          'agents' => [
            { 'name' => 'claude' },
            { 'name' => 'openai' }
          ]
        )
        expect(config.agent_entries).to eq([
          { name: 'claude', timeout: 200 },
          { name: 'openai', timeout: 200 }
        ])
      end
    end

    context 'with agents array taking priority over agent' do
      it 'uses agents array when both are present' do
        config = described_class.new(
          'agent' => { 'name' => 'gemini', 'timeout_seconds' => 300 },
          'agents' => [{ 'name' => 'claude', 'timeout_seconds' => 120 }]
        )
        expect(config.agent_entries).to eq([{ name: 'claude', timeout: 120 }])
      end
    end

    context 'with empty agents array' do
      it 'falls back to single agent from agent.name' do
        config = described_class.new(
          'agent' => { 'name' => 'claude', 'timeout_seconds' => 100 },
          'agents' => []
        )
        expect(config.agent_entries).to eq([{ name: 'claude', timeout: 100 }])
      end
    end
  end

  describe '#agent_names' do
    it 'returns array of agent names' do
      config = described_class.new(
        'agent' => { 'name' => 'gemini', 'timeout_seconds' => 120 },
        'agents' => [
          { 'name' => 'claude', 'timeout_seconds' => 60 },
          { 'name' => 'gemini', 'timeout_seconds' => 600 }
        ]
      )
      expect(config.agent_names).to eq(%w[claude gemini])
    end

    it 'returns single name for single agent config' do
      config = described_class.load(nil)
      expect(config.agent_names).to eq(['gemini'])
    end
  end
end
