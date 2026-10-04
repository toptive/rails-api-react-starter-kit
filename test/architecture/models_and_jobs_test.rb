require "test_helper"
require_relative "../support/ruby_syntax"

class ModelsAndJobsTest < ActiveSupport::TestCase
  include RubySyntax

  test "business logic has no services poros errors or forms directories" do
    %w[services poros errors forms].each do |folder|
      assert_empty Rails.root.glob("app/**/#{folder}"), "Use app/models/<model>/ for helpers"
    end
  end

  test "each job performs exactly one model call" do
    Rails.application.eager_load!
    assert_equal "default", ApplicationJob.new.queue_name
    Rails.root.glob("app/jobs/**/*.rb").each do |path|
      next if path.basename.to_s == "application_job.rb"

      klass = path.relative_path_from(Rails.root.join("app/jobs")).to_s.delete_suffix(".rb").camelize.constantize
      assert_includes %w[default marketing], klass.queue_name
      perform = nodes(syntax(path)).grep(Prism::DefNode).find { |method| method.name == :perform }
      assert perform, "#{path}: define perform"
      statements = perform.body&.body || []
      assert_equal 1, statements.size, "#{path}: perform is ONE model call"
      call = statements.first
      assert_kind_of Prism::CallNode, call
      receiver = call.receiver
      receiver = receiver.receiver while receiver.is_a?(Prism::CallNode)
      assert receiver, "#{path}: delegate to a model"
      owner = receiver.location.slice.split("::").first.underscore
      assert_path_exists Rails.root.join("app/models/#{owner}.rb")
      assert_empty nodes(call).grep(Prism::BlockNode), "#{path}: put orchestration in the model"
    end
  end

  test "workers consume only the declared queues" do
    config = Rails.application.config_for(:queue)
    queues = config.fetch(:workers).flat_map { |worker| worker.fetch(:queues) }
    assert_equal %w[default marketing], queues.sort
  end
end
