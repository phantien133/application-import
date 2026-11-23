module ApplicationImport
  module Errors
    class InvalidClassError < ConfigError
      attr_reader :klass, :base

      def initialize(message = nil, klass: nil, base: nil)
        @klass = klass
        @base = base
        super(message || "#{klass.inspect} must inherit from #{base}")
      end
    end
  end
end
