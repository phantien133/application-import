module ApplicationImport
  module Errors
    class InvalidHandlerError < InvalidClassError
      def initialize(message = nil, handler: nil, klass: handler, base: "ApplicationImport::Handler")
        super(message, klass:, base:)
      end

      alias_method :handler, :klass
    end
  end
end
