module ApplicationImport
  module Errors
    class InvalidValidatorError < InvalidClassError
      def initialize(message = nil, validator: nil, klass: validator, base: "ApplicationImport::Validators::Base")
        super(message, klass:, base:)
      end

      alias_method :validator, :klass
    end
  end
end
