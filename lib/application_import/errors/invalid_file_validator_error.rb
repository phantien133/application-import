module ApplicationImport
  module Errors
    class InvalidFileValidatorError < InvalidClassError
      def initialize(message = nil, file_validator: nil, klass: file_validator, base: "ApplicationImport::FileValidator")
        super(message, klass:, base:)
      end

      alias_method :file_validator, :klass
    end
  end
end
