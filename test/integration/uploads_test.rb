require "test_helper"
require "aws-sdk-s3"
require_relative "../support/tenancy_requests"

class UploadsTest < ActionDispatch::IntegrationTest
  include TenancyRequests

  setup do
    @storage_env = ENV.to_h.select { |key, _| key.start_with?("S3_") }
    ENV["S3_BUCKET"] = "private-uploads"
    ENV["S3_ENDPOINT"] = "https://storage.example"
    ENV["S3_REGION"] = "us-east-1"
    ENV["S3_ACCESS_KEY_ID"] = "stub-access"
    ENV["S3_SECRET_ACCESS_KEY"] = "stub-secret"
    @storage = Aws::S3::Client.new(region: "us-east-1", stub_responses: true)
  end

  teardown do
    ENV.keys.grep(/\AS3_/).each { |key| ENV.delete(key) }
    @storage_env.each { |key, value| ENV[key] = value }
  end

  test "presigns a private PUT with tenant prefix safe filename and fixed type for ten minutes" do
    presign(filename: "../../My photo.PNG", byteSize: 100, contentType: "image/png", kind: "image")
    assert_response :created
    assert_equal %w[headers key method url], data.keys.sort
    assert_equal "PUT", data.fetch("method")
    assert_equal({ "content-type" => "image/png" }, data.fetch("headers"))
    assert_match(%r{\Auploads/#{@organization.id}/[0-9a-f-]{36}/my-photo.png\z}, data.fetch("key"))
    uri = URI(data.fetch("url"))
    assert_equal "storage.example", uri.host
    params = URI.decode_www_form(uri.query).to_h
    assert_equal "600", params.fetch("X-Amz-Expires")
    assert_includes params.fetch("X-Amz-SignedHeaders").split(";"), "content-type"
    assert_includes params.fetch("X-Amz-SignedHeaders").split(";"), "content-length"
    assert_nil params["acl"]
  end

  test "uploads require authentication and configured storage" do
    post "/api/v1/direct-uploads", params: {}, as: :json
    assert_error :unauthorized, "unauthorized"
    ENV.delete("S3_BUCKET")
    presign
    assert_error :service_unavailable, "uploads_not_configured"
    ENV["S3_BUCKET"] = "private-uploads"
    ENV.delete("S3_SECRET_ACCESS_KEY")
    presign
    assert_error :service_unavailable, "uploads_not_configured"
  end

  test "presign refuses missing fields unknown kinds types and invalid sizes" do
    post "/api/v1/direct-uploads", params: {}, headers: bearer(@owner_token), as: :json
    assert_error :bad_request, "bad_request"
    [ [ { kind: "unknown" }, "unknown_kind" ], [ { contentType: "image/svg+xml" }, "content_type_not_allowed" ],
      [ { contentType: "text/html" }, "content_type_not_allowed" ],
      [ { kind: "avatar", contentType: "image/gif" }, "content_type_not_allowed" ],
      [ { kind: "document", contentType: "image/webp" }, "content_type_not_allowed" ],
      [ { byteSize: 0 }, "invalid_size" ], [ { byteSize: -1 }, "invalid_size" ],
      [ { byteSize: "100" }, "invalid_size" ], [ { byteSize: 1.5 }, "invalid_size" ],
      [ { byteSize: 10_000_001 }, "too_large" ], [ { kind: "avatar", byteSize: 2_000_001 }, "too_large" ],
      [ { kind: "document", byteSize: 20_000_001 }, "too_large" ] ].each do |attributes, code|
      presign(**attributes)
      assert_error :unprocessable_entity, code
    end
  end

  test "every allowed kind and exact cap can be presigned" do
    { "image" => [ 10_000_000, %w[image/jpeg image/png image/webp image/gif] ],
      "document" => [ 20_000_000, %w[application/pdf image/jpeg image/png] ],
      "avatar" => [ 2_000_000, %w[image/jpeg image/png image/webp] ] }.each do |kind, (cap, types)|
      types.each do |type|
        presign(kind: kind, contentType: type, byteSize: cap)
        assert_response :created
      end
    end
  end

  test "a completed upload is verified by stored size and bytes before attachment" do
    presign
    key = data.fetch("key")
    @storage.stub_responses(:head_object, content_length: 100, content_type: "image/png")
    @storage.stub_responses(:get_object, body: "\x89PNG\r\n\x1A\n".b + "x" * 92)
    Uploads.stub(:client, @storage) do
      assert Uploads.verify(@scope, key, "image")
      url = URI(Uploads.url(@scope, key))
      assert_equal "300", URI.decode_www_form(url.query).to_h.fetch("X-Amz-Expires")
    end
    assert_equal "bytes=0-4095", @storage.api_requests.find { |operation| operation[:operation_name] == :get_object }.dig(:params, :range)
  end

  test "verify refuses other tenants malformed keys missing objects oversize and spoofed bytes" do
    presign
    key = data.fetch("key")
    Uploads.stub(:client, @storage) do
      [ key.sub(@organization.id, SecureRandom.uuid), "uploads/#{@organization.id}/../secret.png", nil ].each do |invalid|
        assert_equal "upload_incomplete", assert_raises(ApiError) { Uploads.verify(@scope, invalid, "image") }.code
      end
      assert_empty @storage.api_requests
      @storage.stub_responses(:head_object, "NotFound")
      assert_equal "upload_incomplete", assert_raises(ApiError) { Uploads.verify(@scope, key, "image") }.code
      [ 0, 10_000_001 ].each do |size|
        @storage.stub_responses(:head_object, content_length: size, content_type: "image/png")
        assert_equal "upload_incomplete", assert_raises(ApiError) { Uploads.verify(@scope, key, "image") }.code
      end
      @storage.stub_responses(:head_object, content_length: 100, content_type: "image/png")
      [ "<svg><script>alert(1)</script></svg>", "%PDF-1.7", "not a file" ].each do |bytes|
        @storage.stub_responses(:get_object, body: bytes)
        assert_equal "upload_incomplete", assert_raises(ApiError) { Uploads.verify(@scope, key, "image") }.code
      end
      @storage.stub_responses(:head_object, content_length: 100, content_type: "image/gif")
      @storage.stub_responses(:get_object, body: "GIF89a" + "x" * 94)
      assert_equal "upload_incomplete", assert_raises(ApiError) { Uploads.verify(@scope, key, "avatar") }.code
    end
  end

  test "presign is limited to sixty requests per minute" do
    60.times { presign }
    assert_response :created
    presign
    assert_error :too_many_requests, "rate_limited"
  end

  private

  def presign(**attributes)
    post "/api/v1/direct-uploads", params: { filename: "photo.png", contentType: "image/png", byteSize: 100, kind: "image" }.merge(attributes),
      headers: bearer(@owner_token), as: :json
  end
end
