require "test_helper"
require_relative "../support/auth_requests"

class SudoProbeController < Api::V1::BaseController
  before_action :require_sudo!

  def show
    authorize current_session, :update?
    head :no_content
  end
end

class SudoBoundaryTest < ActionDispatch::IntegrationTest
  include AuthRequests

  test "sudo boundary refuses old authentication and accepts reauthentication" do
    token = sign_in(create_user)
    Session.find_by_token(token).update!(sudo_until: Time.current)
    with_routing do |routes|
      routes.draw { get "/sudo-probe", to: "sudo_probe#show" }
      get "/sudo-probe", headers: bearer(token)
      assert_error :forbidden, "sudo_required"
      Session.find_by_token(token).touch_sudo!
      get "/sudo-probe", headers: bearer(token)
      assert_response :no_content
    end
  end
end
