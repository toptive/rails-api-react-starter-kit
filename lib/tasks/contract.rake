require "open3"

namespace :contract do
  desc "Regenerate serializer types and routes; fail on drift from the Git index"
  task check: :environment do
    # Remove stale output too: deleting a serializer must delete its old TS type.
    FileUtils.rm_rf(Rails.root.join("frontend/src/api/generated/serializers"))
    FileUtils.rm_rf(Rails.root.join("frontend/src/api/generated/routes"))
    Rake::Task["typelizer:generate"].invoke
    status, result = Open3.capture2("git", "status", "--porcelain", "--untracked-files=all",
      "--", "frontend/src/api/generated", chdir: Rails.root)
    abort "contract: git status failed" unless result.success?
    drift = status.lines.reject { |line| line[1] == " " }
    abort "contract: generated files differ from the index. Review and stage them:\n#{drift.join}" if drift.any?
    puts "contract: serializers and routes match the staged contract."
  end
end
