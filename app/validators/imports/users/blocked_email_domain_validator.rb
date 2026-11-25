module Imports
  module Users
    class BlockedEmailDomainValidator < ApplicationImport::Validators::RowValidator
      def initialize(...)
        super
        return if blocked_domains.any?

        raise ApplicationImport::Errors::ConfigError, "#{self.class.name} needs blocked_domains"
      end

      def call(row, _result)
        domain = row.attributes[:email].to_s.split("@", 2)[1]&.strip&.downcase
        return if domain.blank? || !blocked?(domain)

        row.add_error(code: :blocked_domain, column: :email, message: "Email domain #{domain} is not allowed",
          details: { domain: })
      end

      private

      def blocked?(domain)
        blocked_domains.any? { |blocked| domain == blocked || domain.end_with?(".#{blocked}") }
      end

      def blocked_domains
        @blocked_domains ||= Array(options[:blocked_domains]).map { |domain| domain.to_s.strip.downcase }.compact_blank
      end
    end
  end
end
