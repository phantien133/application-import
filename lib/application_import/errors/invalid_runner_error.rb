module ApplicationImport
  module Errors
    class InvalidRunnerError < InvalidClassError
      def initialize(message = nil, runner: nil, klass: runner, base: "ApplicationImport::Runner")
        super(message, klass:, base:)
      end

      alias_method :runner, :klass
    end
  end
end
