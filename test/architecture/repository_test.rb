require "test_helper"

class RepositoryTest < ActiveSupport::TestCase
  test "repository contains reference documents rather than tracking files" do
    paths = Dir.chdir(Rails.root) { `git ls-files --cached --others --exclude-standard`.lines.map(&:strip) }
    forbidden = paths.select do |path|
      path.match?(%r{(?:\A|/)(?:PLAN|STATUS|TODO|NOTES|REPORT)\.md\z}i) || path.split("/").include?("tasks") && !path.start_with?("lib/tasks/")
    end
    assert_empty forbidden
  end
end
