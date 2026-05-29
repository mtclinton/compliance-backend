# frozen_string_literal: true

module Kafka
  # Consumer concerns related to report parsing
  class ReportParser
    # Raise an error if entitlement is not available
    class EntitlementError < StandardError; end
    # Raise an error if parsing report is not possible
    class ReportParseError < StandardError; end

    def initialize(message, logger)
      @message = message
      @logger = logger
    end

    def parse_reports
      # Validate each report up front (RHINENG-18501): invalid reports are
      # rejected here, in the consumer, so the job never has to re-validate
      # or re-download. Valid reports are handed to the job as a packed
      # payload, eliminating the second download.
      downloaded_reports.each { |xml| validate_and_enqueue(xml) }
      produce_validation_message('success')
    rescue EntitlementError, ReportParseError => e
      parse_error(e)
    rescue SafeDownloader::DownloadError => e
      parse_error(e)
      raise
    end

    private

    def validate_and_enqueue(xml)
      parser = XccdfReportParser.new(xml, metadata)
      parser.validate!
      profile_id = parser.test_result_file.test_result.profile_id
      job = enqueue_parsing(profile_id, xml)
      notify_report_success(profile_id, job.jid)
    rescue *XccdfReportParser::ERRORS, PG::Error, ActiveRecord::StatementInvalid => e
      # A single invalid report is rejected on its own; sibling reports in
      # the same payload are still processed.
      parse_error(e)
    rescue StandardError
      raise ReportParseError, 'Report parsing failed'
    end

    def enqueue_parsing(profile_id, xml)
      ParseReportJob.perform_later(ReportArtifact.pack(xml), metadata) or
        raise ReportParseError, "Failed to enqueue parsing of #{profile_id}"
    end

    def downloaded_reports
      raise EntitlementError unless identity.valid?
      raise ReportParseError, 'Report empty' if reports.empty?

      reports
    end

    def notify_report_success(profile_id, job)
      msg = "Enqueued report parsing of #{profile_id} from request #{request_id} as a job #{job}"
      @logger.audit_success("[#{org_id}] #{msg}")
      notify_payload_tracker(:received, "File of #{profile_id} is valid. Job #{job} enqueued")
    end

    def notify_payload_tracker(status, status_msg = '')
      PayloadTracker.deliver(
        account: account, system_id: @message['id'],
        request_id: request_id, status: status,
        status_msg: status_msg, org_id: org_id
      )
    end

    def reports
      @reports ||= SafeDownloader.download_reports(url, ssl_only: Settings.report_download_ssl_only)
    end

    def identity
      Insights::Api::Common::IdentityHeader.new(b64_identity)
    end

    def metadata
      (@message.dig('platform_metadata', 'metadata') || {}).merge(
        'id' => id,
        'b64_identity' => b64_identity,
        'url' => url,
        'request_id' => request_id,
        'org_id' => org_id
      )
    end

    def id
      @message.dig('host', 'id')
    end

    def account
      @message.dig('host', 'account')
    end

    def b64_identity
      @message.dig('platform_metadata', 'b64_identity')
    end

    def request_id
      @message.dig('platform_metadata', 'request_id')
    end

    def org_id
      @message.dig('platform_metadata', 'org_id')
    end

    def url
      @message.dig('platform_metadata', 'url')
    end

    def produce_validation_message(result)
      return if Settings.kafka.topics.upload_compliance.blank?

      ReportValidation.deliver(
        request_id: request_id,
        service: 'compliance',
        validation: result
      )
    end

    def parse_error(exception)
      msg = "[#{org_id}] #{exception_message(exception)}"
      @logger.error msg
      @logger.audit_fail msg

      ReportUploadFailed.deliver(
        system: V2::System.find_by(id: id, account: account),
        request_id: request_id,
        error: exception_message(exception),
        org_id: org_id
      )
      produce_validation_message('failure')
    end

    def exception_message(exception)
      case exception.class.to_s
      when 'Kafka::ReportParser::EntitlementError'
        "Rejected report with request id #{request_id}: invalid identity or missing insights entitlement"
      when 'SafeDownloader::DownloadError'
        "Failed to download report with request id #{request_id}: #{exception.message}"
      when 'Kafka::ReportParser::ReportParseError'
        "Invalid report: #{exception.message}"
      else
        "Error parsing report: #{request_id} - #{exception.message}"
      end
    end
  end
end
