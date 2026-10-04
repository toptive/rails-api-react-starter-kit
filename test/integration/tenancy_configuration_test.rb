require "test_helper"
require "open3"

class TenancyConfigurationTest < ActiveSupport::TestCase
  test "production boot refuses missing or blank SPA_ORIGIN even with PUBLIC_URL" do
    [ nil, "" ].each do |origin|
      output, status = boot("SPA_ORIGIN" => origin, "PUBLIC_URL" => "https://app.example.com")
      refute status.success?
      assert_includes output, "SPA_ORIGIN is required in production"
    end
  end

  test "boot refuses invalid tenancy and accepts the configured SPA origin" do
    output, status = boot("SPA_ORIGIN" => "https://app.example.com", "TENANCY" => "typo")
    refute status.success?
    assert_includes output, "TENANCY must be multi or single"
    output, status = boot("SPA_ORIGIN" => "https://app.example.com", "TENANCY" => "multi")
    assert status.success?, output
    assert_includes output, "https://app.example.com"
  end

  private

  def boot(overrides)
    environment = { "RAILS_ENV" => "production", "SECRET_KEY_BASE" => SecureRandom.hex(64), "TENANCY" => "multi" }.merge(overrides)
    stdout, stderr, status = Open3.capture3(environment, "bin/rails", "runner", "puts Rails.application.config.x.spa_origin", chdir: Rails.root)
    [ stdout + stderr, status ]
  end
end
