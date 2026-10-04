require "test_helper"
require_relative "../support/admin_requests"
require "rake"

class AdminTranslationsTest < ActionDispatch::IntegrationTest
  include AdminRequests
  include ActionCable::TestHelper

  test "editor lists the CSV and table union sorted by key with raw cells and pagination" do
    Translation.create!(key: "custom.test", locale: "en", value: "Custom value", edited: true)
    Translation.create!(key: "custom.test", locale: "es", value: "", edited: true)
    get "/api/v1/admin/translations", params: { q: "CUSTOM", missing: "es", perPage: 1 }, headers: admin_headers
    assert_response :ok
    assert_equal [ { "key" => "custom.test", "values" => [
      { "locale" => "en", "value" => "Custom value", "edited" => true },
      { "locale" => "es", "value" => "", "edited" => true }
    ] } ], data
    assert_equal 1, response.parsed_body.dig("meta", "pagination", "total")
    get "/api/v1/admin/translations", params: { q: "CUSTOM VALUE" }, headers: admin_headers
    assert_equal "custom.test", data.first.fetch("key")
    get "/api/v1/admin/translations", params: { q: "app.name" }, headers: admin_headers
    assert_equal "app.name", data.first.fetch("key")
    assert_equal false, data.first.fetch("values").first.fetch("edited")
    get "/api/v1/admin/translations", params: { perPage: 2, page: 2 }, headers: admin_headers
    assert_equal (TranslationCatalog.reference_rows.keys | [ "custom.test" ]).sort[2, 2], data.map { |entry| entry.fetch("key") }
    get "/api/v1/admin/translations", params: { q: "absent" }, headers: admin_headers
    assert_empty data
    get "/api/v1/admin/translations", params: { missing: "fr" }, headers: admin_headers
    assert_admin_field "missing", "validation.inclusion"
  end

  test "admin edits a text then public locales and Rails messages use a new version flow" do
    get "/api/v1/locales/es"
    original_version = response.parsed_body.dig("meta", "version")
    etag = response.headers.fetch("ETag")
    assert_broadcasts("runtime_i18n", 1) do
      put "/api/v1/admin/translations/errors.api.not_found", params: { locale: "es", value: "Texto actualizado {{name}}" }, headers: admin_headers, as: :json
    end
    assert_response :ok
    assert_equal "errors.api.not_found", data.fetch("key")
    assert_equal({ "locale" => "es", "value" => "Texto actualizado {{name}}", "edited" => true }, data.fetch("values").last)
    get "/api/v1/locales/es", headers: { "If-None-Match" => etag }
    assert_response :ok
    assert_equal "Texto actualizado {{name}}", data.fetch("errors.api.not_found")
    new_version = response.parsed_body.dig("meta", "version")
    refute_equal original_version, new_version
    assert_equal "Texto actualizado Ana", I18n.t("errors.api.not_found", locale: :es, name: "Ana")
    get "/api/v1/bootstrap?locale=es"
    assert_equal new_version, data.fetch("i18nVersion")
    event = AuditEvent.find_by!(action: "translation.updated")
    assert_equal @admin.id, event.actor_id
    assert_equal({ "key" => "errors.api.not_found", "locale" => "es" }, event.metadata)
    assert_equal Translation.find_by!(key: "errors.api.not_found", locale: "es").id, event.subject_id
  end

  test "runtime edits survive the real sync task while defaults refresh and stale unedited keys disappear" do
    put "/api/v1/admin/translations/app.name", params: { locale: "en", value: "Edited brand" }, headers: admin_headers, as: :json
    assert_response :ok
    Translation.create!(key: "app.name", locale: "es", value: "Outdated default", edited: false)
    Translation.create!(key: "retired.default", locale: "en", value: "Old", edited: false)
    put "/api/v1/admin/translations/retired.edited", params: { locale: "en", value: "Keep me" }, headers: admin_headers, as: :json
    Rails.application.load_tasks unless Rake::Task.task_defined?("i18n:sync")
    Rake::Task["i18n:sync"].reenable
    Rake::Task["i18n:sync"].invoke
    assert_equal "Edited brand", Translation.find_by!(key: "app.name", locale: "en").value
    assert_equal TranslationCatalog.reference_rows.dig("app.name", "es"), Translation.find_by!(key: "app.name", locale: "es").value
    refute Translation.exists?(key: "retired.default")
    assert Translation.find_by!(key: "retired.edited", locale: "en").edited?
    assert_equal TranslationCatalog.reference_rows.dig("validation.required", "es"), Translation.find_by!(key: "validation.required", locale: "es").value
    get "/api/v1/locales/en"
    assert_equal "Edited brand", data.fetch("app.name")
    assert_equal "Keep me", data.fetch("retired.edited")
    version = response.parsed_body.dig("meta", "version")
    Rake::Task["i18n:sync"].reenable
    Rake::Task["i18n:sync"].invoke
    get "/api/v1/locales/en"
    assert_equal version, response.parsed_body.dig("meta", "version")
  end

  test "empty edited cells stay empty through sync and encoded keys remain literal" do
    key = "custom.key with spaces"
    path = "/api/v1/admin/translations/#{ERB::Util.url_encode(key)}"
    put path, params: { locale: "es", value: "" }, headers: admin_headers, as: :json
    assert_response :ok
    assert_equal key, data.fetch("key")
    Translation.sync!
    get "/api/v1/locales/es"
    assert_equal "", data.fetch(key)
    assert_equal "", I18n.t(key, locale: :es)
  end

  test "cell edits validate locale size and input types without writes" do
    [ {}, { locale: "es" }, { locale: 2, value: "Text" }, { locale: "es", value: nil } ].each do |attributes|
      assert_no_difference [ "Translation.count", "AuditEvent.count" ] do
        put "/api/v1/admin/translations/app.name", params: attributes, headers: admin_headers, as: :json
      end
      assert_error :bad_request, "bad_request"
    end
    put "/api/v1/admin/translations/app.name", params: { locale: "fr", value: "Text" }, headers: admin_headers, as: :json
    assert_admin_field "locale", "validation.inclusion"
    put "/api/v1/admin/translations/app.name", params: { locale: "en", value: "a" * 20_001 }, headers: admin_headers, as: :json
    assert_admin_field "value", "validation.length_max", bindings: { "count" => 20_000 }
    put "/api/v1/admin/translations/app.name", params: { locale: "en", value: "a" * 20_000 }, headers: admin_headers, as: :json
    assert_response :ok
  end

  test "notification from another node invalidates the process catalogue" do
    get "/api/v1/locales/en"
    old_version = response.parsed_body.dig("meta", "version")
    Translation.insert_all!([ { key: "app.name", locale: "en", value: "Remote edit", edited: true } ])
    ActionCable.server.broadcast("runtime_i18n", { changed: true })
    Timeout.timeout(5) do
      sleep 0.01 while TranslationCatalog.version == old_version
    end
    get "/api/v1/locales/en"
    assert_equal "Remote edit", data.fetch("app.name")
    refute_equal old_version, response.parsed_body.dig("meta", "version")
  end
end
