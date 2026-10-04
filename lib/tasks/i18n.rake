require "csv"
require "yaml"
require "open3"

namespace :i18n do
  desc "Sync CSV defaults without replacing runtime edits"
  task sync: :environment do
    puts "i18n: #{Translation.sync!}"
  ensure
    # Flush Solid Cable's batched writer before this short-lived process exits.
    TranslationCatalog.stop!
  end

  desc "Build JSON and Rails locales from the shared translation CSV"
  task :build do
    rows = CSV.read(Rails.root.join("i18n/translations.csv"), headers: true)
    keys = rows.map { |row| row["key"] }
    abort "i18n: duplicate or empty keys" if keys.uniq != keys || keys.any?(&:blank?)
    locales = rows.headers.drop(1)
    abort "i18n: every locale cell must be filled" if rows.any? { |row| locales.any? { |locale| row[locale].blank? } }
    system("node", "i18n/scripts/build.mjs", exception: true)
    locales.each do |locale|
      tree = {}
      rows.each do |row|
        parts = row["key"].split(".")
        leaf = parts.pop
        branch = parts.reduce(tree) { |hash, part| hash[part] ||= {} }
        branch[leaf] = row[locale].gsub(/\{\{(\w+)\}\}/, '%{\1}')
      end
      path = Rails.root.join("config/locales/#{locale}.yml")
      File.write(path, "# Generated from i18n/translations.csv. Do not edit.\n" + { locale => tree }.to_yaml)
    end
    puts "i18n: Rails locales built (#{locales.join(', ')})."
  end

  desc "Rebuild locales and fail on drift from the Git index"
  task check: :build do
    status, result = Open3.capture2("git", "status", "--porcelain", "--untracked-files=all",
      "--", "i18n/locales", "config/locales", chdir: Rails.root)
    abort "i18n: git status failed" unless result.success?
    drift = status.lines.reject { |line| line[1] == " " }
    abort "i18n: review and stage generated locales:\n#{drift.join}" if drift.any?
  end
end
