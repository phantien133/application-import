module ApplicationImport
  module Validators
    class Base
      attr_reader :definition, :options

      def initialize(definition, options = {})
        @definition = definition
        @options = options
      end

      def call(*)
        raise NotImplementedError, "#{self.class.name}#call"
      end
    end
  end
end
