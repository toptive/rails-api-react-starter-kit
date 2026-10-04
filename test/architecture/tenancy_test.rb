require "test_helper"
require_relative "../support/ruby_syntax"

class TenancyTest < ActiveSupport::TestCase
  include RubySyntax

  QUERY_METHODS = %i[all unscoped where find find_by find_by! find_each find_in_batches first last count exists?
    joins left_joins includes preload eager_load select pluck pick order reorder limit offset new create create!
    find_or_create_by find_or_create_by! find_or_initialize_by take take! none lock readonly rewhere in_batches
    sum average minimum maximum build insert insert! insert_all insert_all! upsert upsert! upsert_all
    update update! update_all delete delete_all destroy destroy_all].freeze

  test "every tenant model declares the scope concern foreign key policy and isolation request test" do
    isolation = File.read(Rails.root.join("test/integration/tenant_isolation_test.rb"))
    Rails.root.glob("app/models/*.rb").each do |path|
      model = path.basename.to_s.delete_suffix(".rb").camelize.constantize
      next unless model < ApplicationRecord && model.column_names.include?("organization_id")
      # Contract global records: the webhook inbox organization ID is a nullable hint.
      next if [ Session, AuditEvent, BillingEvent ].include?(model)

      assert model.include?(TenantScoped), "#{model}: include TenantScoped"
      assert model.reflect_on_association(:organization), "#{model}: belongs_to organization"
      refute model.columns_hash.fetch("organization_id").null
      assert_path_exists Rails.root.join("app/policies/#{model.name.underscore}_policy.rb")
      assert_match(/test "#{model.name} tenant isolation/, isolation, "#{model}: add an isolation request test")
      assert_raises(ApiError) { model.for(nil) }
    end
  end

  test "tenant records are never queried directly or through unscoped associations" do
    tenant_models = Rails.root.glob("app/models/*.rb").filter_map do |path|
      path.basename.to_s.delete_suffix(".rb").camelize if File.read(path).match?(/^\s*include TenantScoped$/)
    end
    (Rails.root.glob("app/**/*.rb") + Rails.root.glob("lib/**/*.rb") + [ Rails.root.join("db/seeds.rb") ]).each do |path|
      calls(syntax(path)).each do |call|
        receiver = call.receiver&.location&.slice
        tenant_file = tenant_models.include?(path.basename.to_s.delete_suffix(".rb").camelize)
        direct_model = tenant_models.include?(receiver) || tenant_file && (receiver.nil? || receiver == "self")
        refute direct_model && QUERY_METHODS.include?(call.name),
          "#{path}:#{call.location.start_line}: enter tenant queries through Model.for(scope)"
        refute %i[memberships invitations].include?(call.name),
          "#{path}:#{call.location.start_line}: association queries bypass Model.for(scope)"
        refute call.name == :unscoped, "#{path}:#{call.location.start_line}: unscoped bypasses tenancy"
      end
    end
  end

  test "tenancy updates expose PUT and never PATCH" do
    routes = Rails.application.routes.routes.select do |route|
      route.defaults[:controller].to_s.match?(%r{\Aapi/v1/(?:current_organization|onboarding|settings/(?:organization|members))\z})
    end
    refute_empty routes
    routes.each { |route| refute_match(/PATCH/, route.verb) }
  end
end
