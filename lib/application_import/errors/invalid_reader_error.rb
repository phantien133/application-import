module ApplicationImport
  module Errors
    class InvalidReaderError < InvalidClassError
      def initialize(message = nil, reader: nil, klass: reader, base: "ApplicationImport::Readers::Base")
        super(message, klass:, base:)
      end

      alias_method :reader, :klass
    end
  end
end
