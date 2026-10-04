# AGENTS.md's boundaries, executable. Never add a violation baseline.
architecture :rails
component :serializers, in: "app/serializers/**/*.rb"
component :policies, in: "app/policies/**/*.rb"
component :api_controllers, in: "app/controllers/api/**/*.rb"
component :channels, in: "app/channels/**/*.rb"

poro_constants = Dir.glob("app/models/*/**/*.rb")
  .reject { |path| path.start_with?("app/models/concerns/") }
  .map do |path|
    path.delete_prefix("app/models/").delete_suffix(".rb").split("/")
      .map { |segment| segment.split("_").map(&:capitalize).join }.join("::")
  end
component :poros, constants: poro_constants

controllers.can_only_use :serializers, :policies, :api_controllers, :poros
controllers.method_names.matching(/\A(?!(?:index|show|create|update|destroy)\z)/)
  .forbidden(because: "REST actions only; use a nested resource for another verb")
controllers.cannot_call :render_hash, :deep_camelize,
  :find_by_sql, :where, :joins, :left_joins, :pluck, :connection, :execute,
  :transaction, :update_all, :delete_all,
  because: "controllers authorize, cast, call one model method, and serialize"

services.must_be_empty because: "business rules belong to models"
%w[forms poros errors].each do |folder|
  component("#{folder}_folder".to_sym, in: "app/#{folder}/**/*.rb")
    .must_be_empty(because: "helpers live in app/models/<model>/, errors are domain objects")
end
poros.can_only_be_used_by :models, :serializers

jobs.can_only_use :models, :poros
jobs.cannot_call :render, :redirect_to, :params, :session, :cookies, :flash, receiver: :none
# test/architecture additionally requires perform to be exactly ONE model call;
# the same AST tests limit resource actions to one model call and no branching.
channels.can_only_use :models, :serializers, :policies, :poros
channels.cannot_use :controllers
serializers.cannot_call :save, :save!, :update!, :destroy!, :create!, :delete_all,
  :destroy_all, :update_columns, :update_column, :upsert, :upsert!
serializers.cannot_call :render, :redirect_to, :session, :cookies, :flash, receiver: :none
