module ApplicationImport
  module Validators
    class UniqueInFile < RowsValidator
      def call(row, result, cache)
        raise NotImplementedError, "#{self.class.name}#call"
      end
    end
  end
end
