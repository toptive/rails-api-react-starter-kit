require "test_helper"
require_relative "../support/ruby_syntax"

class ControllersTest < ActiveSupport::TestCase
  include RubySyntax

  REST_ACTIONS = %w[index show create update destroy].freeze
  BASES = %w[ApplicationController Api::V1::BaseController].freeze

  test "controllers expose REST actions and each explicitly authorizes" do
    Rails.application.eager_load!
    controller_files.each do |path|
      klass = path.relative_path_from(Rails.root.join("app/controllers")).to_s.delete_suffix(".rb").camelize.constantize
      actions = klass.action_methods
      assert_empty actions - REST_ACTIONS, "#{klass}: use a nested resource for custom actions"
      next if BASES.include?(klass.name)

      actions.each do |action|
        file, line = klass.instance_method(action).source_location
        method = nodes(syntax(file)).grep(Prism::DefNode).find { |node| node.location.start_line == line }
        assert method, "#{klass}##{action}: actions must be explicit methods"
        assert calls(method).any? { |call| call.receiver.nil? && %i[authorize skip_authorization].include?(call.name) },
          "#{klass}##{action}: authorize or skip_authorization is required"
      end
    end
  end

  test "raw JSON rendering exists only in the envelope" do
    controller_files.each do |path|
      next if path == Rails.root.join("app/controllers/application_controller.rb")

      offenders = calls(syntax(path)).select do |call|
        call.name == :render && nodes(call.arguments).grep(Prism::AssocNode).any? do |pair|
          pair.key.is_a?(Prism::SymbolNode) && pair.key.unescaped == "json"
        end
      end
      assert_empty offenders, "#{path}: use render_data or render_collection"
    end
  end

  test "resource controllers contain no branching or multiple model calls per method" do
    models = Dir[Rails.root.join("app/models/*.rb")].map { |path| File.basename(path, ".rb").camelize }
    controller_files.each do |path|
      next if BASES.include?(path.relative_path_from(Rails.root.join("app/controllers")).to_s.delete_suffix(".rb").camelize)

      nodes(syntax(path)).grep(Prism::DefNode).each do |method|
        branches = nodes(method.body).select do |node|
          [ Prism::IfNode, Prism::UnlessNode, Prism::CaseNode, Prism::WhileNode, Prism::UntilNode,
            Prism::ForNode, Prism::RescueNode ].any? { |kind| node.is_a?(kind) }
        end
        assert_empty branches, "#{path}##{method.name}: move business decisions to the model"
        model_calls = calls(method.body).select { |call| models.include?(call.receiver&.location&.slice) }
        assert_operator model_calls.length, :<=, 1, "#{path}##{method.name}: delegate to one model method"
      end
    end
  end

  private

  def controller_files
    Rails.root.glob("app/controllers/**/*_controller.rb")
  end
end
