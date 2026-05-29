# frozen_string_literal: true

require 'rails_helper'

# RHINENG-18501 / RHINENG-18502
#
# This replaces test/jobs/parse_report_job_test.rb (Minitest). The old test
# passed only by mocking a V1 interface that no longer exists on V2
# (parser.host, policy.compliant?, policy.test_result_hosts), which masked
# the broken notification path. These examples are intentionally pending
# until built against real V2 factories (no parser mocking) so they exercise
# the actual behavior rather than re-mocking it away.
describe ParseReportJob do
  describe '#perform' do
    it 'parses the packed report payload without re-downloading it'
    it 'persists the report via parser.persist! (validation already done in the consumer)'
    it 'short-circuits when the job has been cancelled'
  end

  describe 'SSG-version mismatch' do
    it 'flags the TestResult as mismatched when rules cannot be attributed to the tailoring'
    it 'saves only the rule results attributable to the tailoring'
    it 'does not evict a prior non-mismatched result for the same tailoring + system'
    it 'suppresses the non-compliance notification for a mismatched result'
  end

  describe 'notifications (V2)' do
    it 'notifies when a previously-compliant policy drops below threshold'
    it 'notifies when an untested policy comes in below threshold'
    it 'does not notify when the system is unsupported'
  end
end
