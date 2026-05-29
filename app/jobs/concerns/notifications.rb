# frozen_string_literal: true

# Helper methods related to notifications
module Notifications
  extend ActiveSupport::Concern

  included do
    private

    def compliance_notification_wrapper
      # Capture the notification preconditions before the new result is saved.
      preconditions = policy_previously_compliant? || policy_untested?

      yield

      # Don't alert on a mismatched (partial / unreliable) result — the score
      # isn't meaningful when the report's rule set doesn't match the tailoring.
      return if parser.mismatched?

      # Produce a notification if preconditions are met and the new score is below threshold
      return unless parser.supported? && preconditions && parser.score < parser.policy.compliance_threshold

      notify_non_compliant!
      Rails.logger.info('Notification emitted due to non-compliance')
    end

    # The system's most recent prior result for this tailoring (the view is
    # already "latest per tailoring+system"; this runs before the new save).
    def previous_test_result
      ::V2::TestResult.find_by(system_id: parser.system.id, tailoring_id: parser.tailoring.id)
    end

    # Only notify when there were no results yet, or the policy was compliant.
    def policy_previously_compliant?
      tr = previous_test_result
      tr.present? && tr.score >= parser.policy.compliance_threshold
    end

    def policy_untested?
      previous_test_result.nil?
    end

    def notify_non_compliant!
      SystemNonCompliant.deliver(
        system: parser.system,
        org_id: @msg_value['org_id'],
        policy: parser.policy,
        compliance_score: parser.score
      )
    end
  end
end
