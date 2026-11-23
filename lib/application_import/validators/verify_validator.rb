module ApplicationImport
  module Validators
    class VerifyValidator < Base
      def call(rows, result)
        raise NotImplementedError, "#{self.class.name}#call"
      end
    end
  end
end
