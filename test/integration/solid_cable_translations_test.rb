require "test_helper"
require_relative "../support/admin_requests"
require "open3"

class SolidCableTranslationsTest < ActionDispatch::IntegrationTest
  include AdminRequests
  self.use_transactional_tests = false

  test "a real Solid Cable broadcast invalidates a warmed catalogue in another process" do
    previous = ActionCable.server.config.cable
    TranslationCatalog.stop!
    ActionCable.server.config.cable = { "adapter" => "solid_cable" }
    SolidCable.configure(connects_to: { database: { writing: :cable } }, autotrim: false)
    SolidCable::Record.connects_to(database: { writing: :cable })

    script = <<~'CODE'
      require_relative "config/environment"
      require "timeout"
      Rails.logger = ActiveSupport::Logger.new(File::NULL)
      config = JSON.parse(STDIN.gets)
      ActiveRecord::Base.establish_connection(config.fetch("primary").symbolize_keys)
      ActionCable.server.config.cable = { "adapter" => "solid_cable" }
      SolidCable.configure(connects_to: { database: { writing: :cable } }, autotrim: false)
      SolidCable::Record.establish_connection(config.fetch("cable").symbolize_keys)
      version = TranslationCatalog.version
      STDOUT.sync = true
      puts version
      Timeout.timeout(10) { sleep 0.02 while TranslationCatalog.version == version }
      puts TranslationCatalog.values("en").fetch("app.name")
      TranslationCatalog.stop!
    CODE
    Open3.popen3(RbConfig.ruby, "-e", script, chdir: Rails.root.to_s) do |input, output, errors, process|
      input.puts JSON.generate(primary: ActiveRecord::Base.connection_db_config.configuration_hash,
        cable: SolidCable::Record.connection_db_config.configuration_hash)
      input.close
      assert_match(/\A[0-9a-f]{64}\n\z/, Timeout.timeout(15) { output.gets })
      put "/api/v1/admin/translations/app.name", params: { locale: "en", value: "Remote cable brand" }, headers: admin_headers, as: :json
      assert_response :ok
      result = Timeout.timeout(15) { output.gets }
      assert process.value.success?, errors.read
      assert_equal "Remote cable brand\n", result
    end
  ensure
    TranslationCatalog.stop!
    ActionCable.server.config.cable = previous
    SolidCable.reset_configuration!
    Translation.delete_all
  end
end
