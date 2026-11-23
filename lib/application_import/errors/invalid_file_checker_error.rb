module ApplicationImport
  module Errors
    class InvalidFileCheckerError < InvalidClassError
      def initialize(message = nil, file_checker: nil, klass: file_checker, base: "ApplicationImport::FileChecker")
        super(message, klass:, base:)
      end

      alias_method :file_checker, :klass
    end
  end
end
