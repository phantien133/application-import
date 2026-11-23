module ApplicationImport
  module Readers
    # Placeholder: XLSX reading needs a gem (roo or creek), not added yet.
    # To implement: open file.xlsx.sheet (index or name, default 0) and yield
    # (row number, cell values) from #each_record; Base handles the rest.
    class Xlsx < Base
      private

      def each_record
        raise NotImplementedError, "#{self.class.name}: XLSX reading is not implemented yet"
      end
    end
  end
end
