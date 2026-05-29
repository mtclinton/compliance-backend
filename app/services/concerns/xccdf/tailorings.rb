# frozen_string_literal: true

module Xccdf
  # Methods related to finding Tailorings
  module Tailorings
    # Deterministic: exactly one tailoring per (policy, system os_minor).
    # RHINENG-18501:
    #   * memoized — resolved once per report
    #   * we only ever FIND, never create, so parsing can't accumulate
    #     dangling tailorings (the V2 API guarantees one exists, created by
    #     V2::PolicySystem#after_create when the system joins the policy)
    #   * no nil -> 0 coercion: an unsynced os_minor must not silently bind
    #     to the os_minor 0 tailoring
    def tailoring
      @tailoring ||= ::V2::Tailoring.find_by(
        policy: @policy,
        os_minor_version: report_os_minor_version
      )
    end

    def external_report?
      @policy.nil?
    end

    private

    def report_os_minor_version
      @system.os_minor_version&.to_i
    end

    def tailored_profile
      @tailored_profile ||= tailoring.profile
    end
  end
end
