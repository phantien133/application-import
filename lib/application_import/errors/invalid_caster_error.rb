module ApplicationImport
  module Errors
    class InvalidCasterError < InvalidClassError
      def initialize(message = nil, caster: nil, klass: caster, base: "ApplicationImport::Casters::Base")
        super(message, klass:, base:)
      end

      alias_method :caster, :klass
    end
  end
end
