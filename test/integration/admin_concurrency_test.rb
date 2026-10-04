require "test_helper"
require_relative "../support/admin_requests"

class AdminConcurrencyTest < ActionDispatch::IntegrationTest
  include AdminRequests
  self.use_transactional_tests = false

  setup do
    @organization_ids = Organization.for_user(@admin).map(&:id)
    @document_ids = LegalDocument.pluck(:id)
  end

  teardown do
    @admin.destroy! if User.exists?(@admin.id)
    Organization.where(id: @organization_ids).destroy_all
    LegalDocument.where.not(id: @document_ids).each do |document|
      document.update!(published_version: nil)
      document.versions.destroy_all
      document.destroy!
    end
  end

  test "two simultaneous browser exchanges consume a jobs ticket once" do
    post "/api/v1/admin/jobs-access", headers: admin_headers, as: :json
    assert_response :created
    path = URI(data.fetch("url")).request_uri
    results = concurrent_requests do |client|
      client.get path
      [ client.response.status, client.response.headers["Set-Cookie"] ]
    end
    assert_equal [ 302, 404 ], results.map(&:first).sort
    assert results.find { |status, _| status == 302 }.last
    assert_nil results.find { |status, _| status == 404 }.last
    assert JobsTicket.find_by!(session_id: Session.find_by_token(@admin_token).id).consumed_at
  end

  test "simultaneous legal versions receive distinct consecutive numbers and publish atomically" do
    results = concurrent_requests do |client|
      client.post "/api/v1/admin/legal-documents/terms/versions", params: {
        titles: { en: "Terms" }, bodies: { en: "Plain text" }, publish: true
      }, headers: admin_headers, as: :json
      [ client.response.status, client.response.parsed_body ]
    end
    assert_equal [ 201, 201 ], results.map(&:first)
    assert_equal [ 1, 2 ], results.map { |_, payload| payload.dig("data", "number") }.sort
    document = LegalDocument.find_by!(slug: "terms")
    assert_equal 2, document.published_version.number
    assert_equal [ 2, 1 ], document.versions.map(&:number)
    document.versions.each do |version|
      assert version.published_at
      %w[legal.version_created legal.published].each do |action|
        assert_equal 1, AuditEvent.where(action: action, subject_id: version.id).count
      end
    end
  end

  private

  def concurrent_requests
    ready = Queue.new
    start = Queue.new
    workers = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          client = ActionDispatch::Integration::Session.new(Rails.application)
          ready << true
          start.pop
          yield client
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    workers.map(&:value)
  ensure
    workers&.each(&:join)
  end
end
