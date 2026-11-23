module ApplicationImport
  module Errors
    class InvalidTransformerError < InvalidClassError
      def initialize(message = nil, transformer: nil, klass: transformer, base: "ApplicationImport::Transformers::Base")
        super(message, klass:, base:)
      end

      alias_method :transformer, :klass
    end
  end
end
