require "test_helper"

class RuntimeI18nTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  setup do
    @key = "verification.query_cache.#{SecureRandom.hex(6)}"
    @row = Translation.create!(key: @key, locale: "en", value: "Original text", edited: true)
  end

  teardown { @row.destroy! }

  test "remote invalidation rebuilds from the database despite the current request query cache" do
    Translation.cache do
      get "/api/v1/locales/en"
      assert_equal "Original text", response.parsed_body.dig("data", @key)
      initial_version = response.parsed_body.dig("meta", "version")
      # A remote database write cannot clear this thread's Active Record query cache.
      worker = Thread.new do
        Translation.connection_pool.with_connection do
          Translation.where(id: @row.id).update_all(value: "Remote text")
        end
      end
      worker.value
      ActiveSupport::Notifications.instrument("translations.changed")
      get "/api/v1/locales/en"
      assert_response :ok
      assert_equal "Remote text", response.parsed_body.dig("data", @key)
      refute_equal initial_version, response.parsed_body.dig("meta", "version")
      assert_equal "Remote text", I18n.t(@key, locale: :en)
    end
  end
end
