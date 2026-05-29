# frozen_string_literal: true

module Xccdf
  # Methods related to saving RuleResults from openscap_parser
  module RuleResults
    def save_rule_results
      ::V2::RuleResult.import!(rule_results.select(&:new_record?), ignore: true)
    end

    # RHINENG-18501: only build RuleResults for op results we can attribute
    # to a rule in THIS tailoring. Results we can't attribute (rule-set
    # differences across SSG versions) are dropped — see #mismatched?.
    def rule_results
      @rule_results ||= attributable_op_rule_results.map do |op_rule_result|
        ::V2::RuleResult.from_parser(
          op_rule_result,
          test_result_id: @test_result.id,
          rule_id: tailoring_rule_ids[op_rule_result.id]
        )
      end
    end

    def failed_rule_results
      ::V2::RuleResult.where(id: rule_results).failed
    end

    def failed_rules
      ::V2::Rule.joins(:rule_results)
                .where(rule_results: failed_rule_results)
                .distinct
    end

    def selected_op_rule_results
      @op_rule_results&.reject do |rule_result|
        ::V2::RuleResult::NOT_SELECTED.include? rule_result.result
      end
    end

    # Selected results whose rule exists in the tailoring — these get saved.
    def attributable_op_rule_results
      selected_op_rule_results.select { |rr| tailoring_rule_ids.key?(rr.id) }
    end

    # Selected results we can't place in the tailoring — these are ignored
    # and are the signal that the report is mismatched.
    def unattributable_op_rule_results
      selected_op_rule_results.reject { |rr| tailoring_rule_ids.key?(rr.id) }
    end

    # The report was produced against a rule set that doesn't line up with
    # the policy's tailoring (typically a different SSG version), so the
    # results we can show are only partial.
    # NOTE (Q4): defined here as the ref-id attribution gap. Could also be
    # OR'd with an explicit SSG-version inequality — flagged for Janos.
    def mismatched?
      return @mismatched if defined?(@mismatched)

      @mismatched = unattributable_op_rule_results.any?
    end

    private

    # ref_id => rule_id for the rules that belong to THIS tailoring (the
    # policy's expected rule set), not the rules in the uploaded report.
    def tailoring_rule_ids
      @tailoring_rule_ids ||= tailoring.rules.pluck(:ref_id, :id).to_h
    end
  end
end
