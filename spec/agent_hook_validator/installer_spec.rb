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

  describe '#install_claude' do
    it 'copies validate.md to .claude/commands/' do
      installer.run

      dest = File.join(tmpdir, '.claude', 'commands', 'validate.md')
      expect(File.exist?(dest)).to be true
      expect(File.read(dest)).to include('agent-hook-validator')
    end

    it 'creates .claude/commands/ directory if missing' do
      installer.run

      commands_dir = File.join(tmpdir, '.claude', 'commands')
      expect(Dir.exist?(commands_dir)).to be true
    end

    it 'overwrites existing validate.md' do
      commands_dir = File.join(tmpdir, '.claude', 'commands')
      FileUtils.mkdir_p(commands_dir)
      File.write(File.join(commands_dir, 'validate.md'), 'old content')

      installer.run

      content = File.read(File.join(commands_dir, 'validate.md'))
      expect(content).not_to eq('old content')
      expect(content).to include('agent-hook-validator')
    end

    it 'defaults project_dir to Dir.pwd when nil' do
      allow(Dir).to receive(:pwd).and_return(tmpdir)
      nil_dir_installer = described_class.new(
        { target: 'claude', project_dir: nil, agent: nil },
        stdout: stdout
      )
      nil_dir_installer.run

      dest = File.join(tmpdir, '.claude', 'commands', 'validate.md')
      expect(File.exist?(dest)).to be true
    end
  end

  describe '#install_gemini' do
    let(:options) { { target: 'gemini', project_dir: tmpdir, agent: nil } }
    let(:gemini_commands) { File.join(tmpdir, '.gemini', 'commands') }

    before do
      allow(File).to receive(:expand_path).and_call_original
      allow(File).to receive(:expand_path).with('~/.gemini/commands')
                                          .and_return(gemini_commands)
    end

    it 'copies validate.toml to ~/.gemini/commands/' do
      installer.run

      dest = File.join(gemini_commands, 'validate.toml')
      expect(File.exist?(dest)).to be true
      expect(File.read(dest)).to include('agent-hook-validator')
    end

    it 'creates commands directory if missing' do
      installer.run

      expect(Dir.exist?(gemini_commands)).to be true
    end
  end

  describe '#install_openai' do
    let(:options) { { target: 'openai', project_dir: tmpdir, agent: nil } }

    it 'outputs manual configuration message' do
      installer.run

      expect(stdout.string).to include('not yet supported')
    end
  end

  describe '#run' do
    it 'warns about unknown target' do
      unknown_installer = described_class.new(
        { target: 'unknown_agent', project_dir: tmpdir, agent: nil },
        stdout: stdout
      )
      expect { unknown_installer.run }.not_to raise_error
      expect(stdout.string).to include('Unknown target: unknown_agent')
      expect(stdout.string).to include('Done')
    end

    it 'installs claude command by default' do
      installer.run

      dest = File.join(tmpdir, '.claude', 'commands', 'validate.md')
      expect(File.exist?(dest)).to be true
    end

    it 'installs all targets when target is all' do
      gemini_commands = File.join(tmpdir, '.gemini', 'commands')
      allow(File).to receive(:expand_path).and_call_original
      allow(File).to receive(:expand_path).with('~/.gemini/commands')
                                          .and_return(gemini_commands)

      all_installer = described_class.new(
        { target: 'all', project_dir: tmpdir, agent: nil },
        stdout: stdout
      )
      all_installer.run

      expect(File.exist?(File.join(tmpdir, '.claude', 'commands', 'validate.md'))).to be true
      expect(File.exist?(File.join(gemini_commands, 'validate.toml'))).to be true
      expect(stdout.string).to include('not yet supported')
    end

    it 'prints done message with /validate usage hint' do
      installer.run
      expect(stdout.string).to include('/validate')
    end
  end
end
