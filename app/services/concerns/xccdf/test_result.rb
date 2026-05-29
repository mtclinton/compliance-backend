# frozen_string_literal: true

module Xccdf
  # Methods related to saving TestResult from openscap_parser
  module TestResult
    delegate :score, to: :@op_test_result

    def save_test_result
      @test_result = ::V2::TestResult.create!(
        system: @system, tailoring: tailoring,
        supported: supported?, score: score,
        mismatched: mismatched?,
        # Count only failures among the rules we could attribute to the tailoring.
        failed_rule_count: attributable_op_rule_results&.count { |rr| ::V2::RuleResult::FAILED.include?(rr.result) }.to_i,
        start_time: @op_test_result.start_time.in_time_zone,
        end_time: @op_test_result.end_time.in_time_zone
      )

      delete_old_test_results if @test_result.persisted?

      @test_result
    end

    # RHINENG-18501 (Q6): a mismatched/partial result must not evict a prior
    # good (non-mismatched) result for the same tailoring+system — otherwise
    # a single bad upload makes the customer's last good data disappear.
    def delete_old_test_results
      scope = ::V2::TestResult.where(tailoring: @tailoring, system: @system)
                              .where.not(id: @test_result.id)
      scope = scope.where(mismatched: true) if @test_result.mismatched?
      scope.destroy_all
    end

    def supported?
      SupportedSsg.supported?(
        ssg_version: security_guide.version,
        os_major_version: @system.os_major_version,
        os_minor_version: @system.os_minor_version
      )
    end
  end
end
