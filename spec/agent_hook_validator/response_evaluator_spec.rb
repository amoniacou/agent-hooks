# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AgentHookValidator::ResponseEvaluator do
  describe '#block?' do
    context 'with CRITICAL at start of line' do
      it 'blocks when CRITICAL is the first line' do
        response = "CRITICAL: Missing tests\n\nCode Quality Score: 9/10"
        evaluator = described_class.new(response)
        expect(evaluator.block?).to be true
      end

      it 'blocks when CRITICAL appears at start of a later line' do
        response = "Summary of review\n\nCRITICAL: Security vulnerability found\n\nCode Quality Score: 9/10"
        evaluator = described_class.new(response)
        expect(evaluator.block?).to be true
      end

      it 'does not treat CRITICAL mid-line as critical' do
        response = "No issues. Not CRITICAL: just a mention\n\nCode Quality Score: 9/10"
        evaluator = described_class.new(response)
        expect(evaluator.block?).to be false
      end
    end

    context 'with Code Quality Score' do
      it 'blocks when score is below minimum (8/10)' do
        response = "All looks good.\n\nCode Quality Score: 8/10"
        evaluator = described_class.new(response)
        expect(evaluator.block?).to be true
      end

      it 'allows when score equals minimum (9/10)' do
        response = "All looks good.\n\nCode Quality Score: 9/10"
        evaluator = described_class.new(response)
        expect(evaluator.block?).to be false
      end

      it 'allows when score is above minimum (10/10)' do
        response = "All looks good.\n\nCode Quality Score: 10/10"
        evaluator = described_class.new(response)
        expect(evaluator.block?).to be false
      end

      it 'blocks when score is missing from response' do
        response = 'All looks good, no issues found.'
        evaluator = described_class.new(response)
        expect(evaluator.block?).to be true
      end

      it 'respects custom min_quality_score' do
        response = "All looks good.\n\nCode Quality Score: 7/10"
        evaluator = described_class.new(response, min_quality_score: 7)
        expect(evaluator.block?).to be false
      end
    end

    context 'with ### Other Issues section' do
      it 'blocks when Other Issues has content' do
        response = "Summary\n\nCode Quality Score: 9/10\n\n" \
                   "### Other Issues\n- Minor naming issue in `app/models/user.rb:5`"
        evaluator = described_class.new(response)
        expect(evaluator.block?).to be true
      end

      it 'allows when Other Issues section is absent' do
        response = "Summary\n\nCode Quality Score: 9/10"
        evaluator = described_class.new(response)
        expect(evaluator.block?).to be false
      end

      it 'allows when Other Issues section is empty' do
        response = "Summary\n\nCode Quality Score: 9/10\n\n### Other Issues\n"
        evaluator = described_class.new(response)
        expect(evaluator.block?).to be false
      end
    end

    context 'with combined rules' do
      it 'blocks when all issues present' do
        response = "CRITICAL: SQL injection\n\nCode Quality Score: 3/10\n\n### Other Issues\n- Typo in variable name"
        evaluator = described_class.new(response)
        expect(evaluator.block?).to be true
      end

      it 'allows when response is clean' do
        response = "No issues found.\n\nCode Quality Score: 10/10"
        evaluator = described_class.new(response)
        expect(evaluator.block?).to be false
      end
    end
  end

  describe '#reasons' do
    it 'lists all triggered reasons' do
      response = "CRITICAL: Bad stuff\n\nCode Quality Score: 5/10\n\n### Other Issues\n- Something minor"
      evaluator = described_class.new(response)
      reasons = evaluator.reasons

      expect(reasons).to include('Critical issues found')
      expect(reasons).to include(a_string_matching(%r{Code Quality Score 5/10}))
      expect(reasons).to include('Other issues reported')
    end

    it 'reports missing score' do
      response = 'No score here'
      evaluator = described_class.new(response)
      expect(evaluator.reasons).to include('Code Quality Score not found in response')
    end

    it 'returns empty array when no issues' do
      response = "All good.\n\nCode Quality Score: 9/10"
      evaluator = described_class.new(response)
      expect(evaluator.reasons).to be_empty
    end
  end
end
