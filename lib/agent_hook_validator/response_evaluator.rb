# frozen_string_literal: true

module AgentHookValidator
  class ResponseEvaluator
    DEFAULT_MIN_QUALITY_SCORE = 9

    def initialize(response, min_quality_score: DEFAULT_MIN_QUALITY_SCORE)
      @response = response
      @min_quality_score = min_quality_score
    end

    def block?
      critical? || low_quality_score? || other_issues?
    end

    def reasons
      r = []
      r << 'Critical issues found' if critical?
      if quality_score.nil?
        r << 'Code Quality Score not found in response'
      elsif low_quality_score?
        r << "Code Quality Score #{quality_score}/10 (minimum #{@min_quality_score})"
      end
      r << 'Other issues reported' if other_issues?
      r
    end

    private

    def critical?
      @response.match?(/^CRITICAL:/m)
    end

    def quality_score
      return @quality_score if defined?(@quality_score)

      match = @response.match(%r{Code Quality Score:\s*(\d+)\s*/\s*10})
      @quality_score = match ? match[1].to_i : nil
    end

    def low_quality_score?
      score = quality_score
      return true if score.nil?

      score < @min_quality_score
    end

    def other_issues?
      match = @response.match(/^###\s*Other Issues\s*$(.*)/m)
      return false unless match

      !match[1].strip.empty?
    end
  end
end
