# frozen_string_literal: true

desc 'Remove dangling tailoring profiles (empty os_minor_version) and orphaned profile_rules'
task cleanup_dangling_tailorings: :environment do
  start = Time.zone.now

  puts 'Beginning cleanup of dangling tailorings.'

  dangling_profile_ids = Profile.where.not(parent_profile_id: nil)
                                .where(os_minor_version: '')
                                .pluck(:id)
  puts "Found #{dangling_profile_ids.count} dangling profiles"

  if dangling_profile_ids.any?
    num_deleted = RuleResult.joins(:test_result)
                            .where(test_results: { profile_id: dangling_profile_ids })
                            .delete_all
    puts "  Deleted #{num_deleted} RuleResults"

    num_deleted = TestResult.where(profile_id: dangling_profile_ids).delete_all
    puts "  Deleted #{num_deleted} TestResults"

    num_deleted = ProfileRule.where(profile_id: dangling_profile_ids).delete_all
    puts "  Deleted #{num_deleted} ProfileRules"

    num_deleted = Profile.where(id: dangling_profile_ids).delete_all
    puts "  Deleted #{num_deleted} dangling Profiles"
  end

  num_deleted = ProfileRule.where.not(
    profile_id: Profile.select(:id)
  ).delete_all
  puts "Deleted #{num_deleted} orphaned ProfileRules"

  puts "Finished cleanup in #{Time.zone.now - start} seconds."
end
