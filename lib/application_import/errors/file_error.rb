module ApplicationImport
  module Errors
    class FileError < Error
      attr_reader :code, :details

      def initialize(message = nil, code: :invalid_file, details: nil)
        super(message)
        @code = code.to_sym
        @details = details
      end
    end
  end
end
