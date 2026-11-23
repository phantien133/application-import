module ApplicationImport
  module Errors
    class FileError < Error
      attr_reader :code

      def initialize(message = nil, code: :invalid_file)
        super(message)
        @code = code
      end
    end
  end
end
