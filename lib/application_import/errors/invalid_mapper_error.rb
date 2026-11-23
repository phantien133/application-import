module ApplicationImport
  module Errors
    class InvalidMapperError < InvalidClassError
      def initialize(message = nil, mapper: nil, klass: mapper, base: "ApplicationImport::Mappers::Base")
        super(message, klass:, base:)
      end

      alias_method :mapper, :klass
    end
  end
end
