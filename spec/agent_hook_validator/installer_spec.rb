# frozen_string_literal: true

require 'spec_helper'
require 'agent_hook_validator/installer'
require 'tmpdir'
require 'json'

RSpec.describe AgentHookValidator::Installer do
  let(:stdout) { StringIO.new }
  let(:options) { { target: 'claude', project_dir: tmpdir, agent: nil } }
  let(:tmpdir) { Dir.mktmpdir }
  let(:installer) { described_class.new(options, stdout: stdout) }

  after { FileUtils.remove_entry(tmpdir) }

  describe '#read_json_settings' do
    it 'reads valid JSON file' do
      path = File.join(tmpdir, 'test.json')
      File.write(path, '{"key": "value"}')

      result = installer.read_json_settings(path)
      expect(result).to eq('key' => 'value')
    end

    it 'returns empty hash for missing file' do
      result = installer.read_json_settings(File.join(tmpdir, 'nonexistent.json'))
      expect(result).to eq({})
    end

    it 'returns empty hash for invalid JSON' do
      path = File.join(tmpdir, 'bad.json')
      File.write(path, 'not json at all')

      result = installer.read_json_settings(path)
      expect(result).to eq({})
    end
  end

  describe '#write_json_settings' do
    it 'writes pretty JSON to file' do
      path = File.join(tmpdir, 'output.json')
      installer.write_json_settings(path, { 'a' => 1 })

      content = File.read(path)
      expect(JSON.parse(content)).to eq('a' => 1)
      expect(content).to include("\n") # pretty-printed
    end

    it 'creates parent directories' do
      path = File.join(tmpdir, 'deep', 'nested', 'settings.json')
      installer.write_json_settings(path, { 'ok' => true })

      expect(File.exist?(path)).to be true
      expect(JSON.parse(File.read(path))).to eq('ok' => true)
    end
  end

  describe '#install_claude' do
    it 'creates hooks structure in settings.json' do
      installer.install_claude(tmpdir, 'claude')

      settings_path = File.join(tmpdir, '.claude', 'settings.json')
      settings = JSON.parse(File.read(settings_path))

      expect(settings['hooks']['Stop']).to be_an(Array)
      expect(settings['hooks']['Stop'].length).to eq(1)

      hook_entry = settings['hooks']['Stop'].first
      expect(hook_entry['hooks'].first['type']).to eq('command')
      expect(hook_entry['hooks'].first['command']).to include('agent-hook-validator')
      expect(hook_entry['hooks'].first['command']).to include('-a claude')
      expect(hook_entry['hooks'].first['timeout']).to eq(180)
    end

    it 'replaces existing agent-hook-validator hook' do
      settings_path = File.join(tmpdir, '.claude', 'settings.json')
      FileUtils.mkdir_p(File.dirname(settings_path))
      old_hook = { 'type' => 'command', 'command' => 'old agent-hook-validator cmd' }
      existing = { 'hooks' => { 'Stop' => [{ 'hooks' => [old_hook] }] } }
      File.write(settings_path, JSON.pretty_generate(existing))

      installer.install_claude(tmpdir, 'gemini')

      settings = JSON.parse(File.read(settings_path))
      expect(settings['hooks']['Stop'].length).to eq(1)
      expect(settings['hooks']['Stop'].first['hooks'].first['command']).to include('-a gemini')
    end

    it 'preserves other hooks' do
      settings_path = File.join(tmpdir, '.claude', 'settings.json')
      FileUtils.mkdir_p(File.dirname(settings_path))
      other_hook = { 'type' => 'command', 'command' => 'other-tool' }
      existing = { 'hooks' => { 'Stop' => [{ 'hooks' => [other_hook] }] } }
      File.write(settings_path, JSON.pretty_generate(existing))

      installer.install_claude(tmpdir, 'claude')

      settings = JSON.parse(File.read(settings_path))
      expect(settings['hooks']['Stop'].length).to eq(2)
    end
  end

  describe '#install_gemini' do
    let(:gemini_home) { File.join(tmpdir, '.gemini') }

    before do
      allow(File).to receive(:expand_path).and_call_original
      allow(File).to receive(:expand_path).with('~/.gemini/settings.json')
                                          .and_return(File.join(gemini_home, 'settings.json'))
    end

    it 'creates AfterAgent hook in settings' do
      installer.install_gemini('gemini')

      settings = JSON.parse(File.read(File.join(gemini_home, 'settings.json')))
      expect(settings['hooks']['AfterAgent']).to be_an(Array)
      expect(settings['hooks']['AfterAgent'].length).to eq(1)

      hook = settings['hooks']['AfterAgent'].first
      expect(hook['name']).to eq('agent-hook-validator')
      expect(hook['type']).to eq('command')
      expect(hook['command']).to include('-a gemini')
    end

    it 'replaces existing agent-hook-validator hook' do
      FileUtils.mkdir_p(gemini_home)
      old_hook = { 'name' => 'agent-hook-validator', 'command' => 'old' }
      existing = { 'hooks' => { 'AfterAgent' => [old_hook] } }
      File.write(File.join(gemini_home, 'settings.json'), JSON.pretty_generate(existing))

      installer.install_gemini('claude')

      settings = JSON.parse(File.read(File.join(gemini_home, 'settings.json')))
      expect(settings['hooks']['AfterAgent'].length).to eq(1)
      expect(settings['hooks']['AfterAgent'].first['command']).to include('-a claude')
    end
  end

  describe '#install_openai' do
    it 'outputs manual configuration message' do
      installer.install_openai('openai')

      expect(stdout.string).to include('not yet supported')
    end
  end

  describe '#run' do
    it 'installs claude hook by default' do
      installer.run

      settings_path = File.join(tmpdir, '.claude', 'settings.json')
      expect(File.exist?(settings_path)).to be true
    end

    it 'installs all targets when target is all' do
      gemini_home = File.join(tmpdir, '.gemini')
      allow(File).to receive(:expand_path).and_call_original
      allow(File).to receive(:expand_path).with('~/.gemini/settings.json')
                                          .and_return(File.join(gemini_home, 'settings.json'))

      all_installer = described_class.new(
        { target: 'all', project_dir: tmpdir, agent: nil },
        stdout: stdout
      )
      all_installer.run

      expect(File.exist?(File.join(tmpdir, '.claude', 'settings.json'))).to be true
      expect(File.exist?(File.join(gemini_home, 'settings.json'))).to be true
      expect(stdout.string).to include('not yet supported')
    end
  end
end
