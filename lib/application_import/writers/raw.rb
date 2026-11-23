module ApplicationImport
  module Writers
    # output.mode raw (default without output.model): nothing is persisted; the rows'
    # attributes are added to result.records.
    class Raw < Base
      private

      def transaction?
        false
      end

      def write(rows)
        result.add_records(rows.map(&:attributes))
        rows.size
      end
    end
  end
end
