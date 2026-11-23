module ApplicationImport
  module Validators
    class FileValidator < Base
      def call(source, result)
        raise NotImplementedError, "#{self.class.name}#call"
      end
    end
  end
end
