# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AgentHookValidator::TemplateRenderer do
  let(:template_path) { File.expand_path('../../templates/validation.erb', __dir__) }
  let(:diff) { File.read(File.expand_path('../fixtures/sample_diff.txt', __dir__)) }

  describe '.render' do
    context 'with Ruby files changed' do
      let(:changed_files) { ['app/models/user.rb', 'spec/models/user_spec.rb'] }

      it 'includes Ruby-specific guidelines' do
        result = described_class.render(template_path, diff, changed_files)
        expect(result).to include('Ruby-Specific Guidelines')
        expect(result).to include('RuboCop conventions')
      end

      it 'includes the diff data' do
        result = described_class.render(template_path, diff, changed_files)
        expect(result).to include('full_name')
        expect(result).to include('DIFF DATA')
      end

      it 'lists changed files' do
        result = described_class.render(template_path, diff, changed_files)
        expect(result).to include('app/models/user.rb')
        expect(result).to include('spec/models/user_spec.rb')
      end
    end

    context 'with JS files changed' do
      let(:changed_files) { ['src/app.js'] }

      it 'includes JS-specific guidelines' do
        result = described_class.render(template_path, diff, changed_files)
        expect(result).to include('JS/TS-Specific Guidelines')
      end

      it 'does not include Ruby guidelines' do
        result = described_class.render(template_path, diff, changed_files)
        expect(result).not_to include('Ruby-Specific Guidelines')
      end
    end

    context 'with non-code files changed' do
      let(:changed_files) { ['README.md'] }

      it 'does not include language-specific guidelines' do
        result = described_class.render(template_path, diff, changed_files)
        expect(result).not_to include('Ruby-Specific Guidelines')
        expect(result).not_to include('JS/TS-Specific Guidelines')
      end
    end
  end
end
