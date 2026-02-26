# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

RSpec.describe AgentHookValidator::TemplateRenderer do
  let(:template_path) { File.expand_path('../../templates/validation.erb', __dir__) }

  describe '.render' do
    context 'with Ruby files changed' do
      let(:changed_files) { ['app/models/user.rb', 'spec/models/user_spec.rb'] }

      it 'includes Ruby-specific guidelines' do
        result = described_class.render(template_path, changed_files)
        expect(result).to include('Ruby-Specific Guidelines')
        expect(result).to include('RuboCop conventions')
      end

      it 'lists changed files' do
        result = described_class.render(template_path, changed_files)
        expect(result).to include('app/models/user.rb')
        expect(result).to include('spec/models/user_spec.rb')
      end
    end

    context 'with JS files changed' do
      let(:changed_files) { ['src/app.js'] }

      it 'includes JS-specific guidelines' do
        result = described_class.render(template_path, changed_files)
        expect(result).to include('JS/TS-Specific Guidelines')
      end

      it 'does not include Ruby guidelines' do
        result = described_class.render(template_path, changed_files)
        expect(result).not_to include('Ruby-Specific Guidelines')
      end
    end

    context 'with empty changed_files' do
      it 'renders without error' do
        result = described_class.render(template_path, [])
        expect(result).to be_a(String)
        expect(result).not_to include('Ruby-Specific Guidelines')
      end
    end

    context 'with custom template' do
      it 'renders using provided binding with changed_files' do
        custom_template = Tempfile.new(['custom', '.erb'])
        custom_template.write('Files: <%= changed_files.size %>')
        custom_template.close

        result = described_class.render(custom_template.path, ['a.rb', 'b.rb'])
        expect(result).to eq('Files: 2')
      ensure
        custom_template.unlink
      end
    end

    context 'with non-code files changed' do
      let(:changed_files) { ['README.md'] }

      it 'does not include language-specific guidelines' do
        result = described_class.render(template_path, changed_files)
        expect(result).not_to include('Ruby-Specific Guidelines')
        expect(result).not_to include('JS/TS-Specific Guidelines')
      end
    end
  end
end
