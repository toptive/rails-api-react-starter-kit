require "test_helper"

class PlatformAiTest < ActiveSupport::TestCase
  setup do
    @ai_env = ENV.to_h.slice("OPENROUTER_API_KEY", "OPENROUTER_MODEL", "FAL_KEY", "GOOGLE_API_KEY", "GEMINI_MODEL")
    ENV["OPENROUTER_API_KEY"] = "test-router"
    ENV["FAL_KEY"] = "test-fal"
    ENV["GOOGLE_API_KEY"] = "test-google"
    ENV.delete("OPENROUTER_MODEL")
    ENV.delete("GEMINI_MODEL")
  end
  teardown { %w[OPENROUTER_API_KEY OPENROUTER_MODEL FAL_KEY GOOGLE_API_KEY GEMINI_MODEL].each { |name| ENV[name] = @ai_env[name] } }

  test "all AI entry points fail visibly when their own key is missing" do
    %w[OPENROUTER_API_KEY FAL_KEY GOOGLE_API_KEY].each { |key| ENV.delete(key) }
    [ -> { Ai.chat([]) }, -> { Ai.translate_strings({}, from: "en", to: "es") },
      -> { Ai.fal("fal-ai/model", {}) }, -> { Ai.gemini("Hello") } ].each do |call|
      assert_equal "ai_not_configured", assert_raises(ApiError, &call).code
    end
  end

  test "chat media and Gemini use their configured HTTP provider and never retry" do
    replies = [
      [ "openrouter.ai", "/api/v1/chat/completions", { choices: [ { message: { content: "Answer" } } ] }, -> { Ai.chat([ { role: "user", content: "Hello" } ]) } ],
      [ "fal.run", "/fal-ai/model", { images: [] }, -> { Ai.fal("fal-ai/model", { prompt: "Hello" }) } ],
      [ "generativelanguage.googleapis.com", "/v1beta/models/gemini-2.5-flash:generateContent",
        { candidates: [ { content: { parts: [ { text: "Answer" } ] } } ] }, -> { Ai.gemini("Hello") } ]
    ]
    replies.each do |host, path, body, call|
      http = Net::HTTP.new(host, 443)
      Net::HTTP.stub(:new, ->(actual_host, port) { assert_equal host, actual_host; assert_equal 443, port; http }) do
        http.stub(:post, ->(actual_path, payload, headers) {
          assert_equal path, actual_path
          assert_equal 0, http.max_retries
          assert_equal "application/json", headers.fetch("Content-Type")
          assert JSON.parse(payload).is_a?(Hash)
          response = Net::HTTPOK.new("1.1", "200", "OK")
          response.define_singleton_method(:body) { JSON.generate(body) }
          response
        }) { assert call.call }
      end
    end
  end

  test "DNS failures become ai_unavailable for every provider" do
    Net::HTTP.stub(:new, ->(*) { raise SocketError }) do
      [ -> { Ai.chat([]) }, -> { Ai.fal("fal-ai/model", {}) }, -> { Ai.gemini("Hello") } ].each do |call|
        assert_equal "ai_unavailable", assert_raises(ApiError, &call).code
      end
    end
  end
end
