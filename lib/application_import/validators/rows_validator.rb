module ApplicationImport
  module Validators
    class RowsValidator < Base
      def call(row, result)
        raise NotImplementedError, "#{self.class.name}#call"
      end
    end
  end
end
