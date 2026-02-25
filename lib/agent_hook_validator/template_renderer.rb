# frozen_string_literal: true

require 'erb'

module AgentHookValidator
  class TemplateRenderer
    def self.render(template_path, diff, changed_files)
      template = File.read(template_path)
      renderer = ERB.new(template, trim_mode: '-')

      context = Object.new
      context.instance_variable_set(:@diff, diff)
      context.instance_variable_set(:@changed_files, changed_files)

      # Додаємо методи для доступу в ERB
      context.define_singleton_method(:diff) { @diff }
      context.define_singleton_method(:changed_files) { @changed_files }

      renderer.result(context.instance_eval { binding })
    end
  end
end
