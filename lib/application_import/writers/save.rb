module ApplicationImport
  module Writers
    # output.mode save: record.save(**output.save) for each row, in its own savepoint.
    # A false save (validation) or a database error -> not_saved on the row.
    class Save < Base
      private

      def write(rows)
        written = 0
        rows.each do |row|
          break if aborted?

          written += 1 if save(row)
        end
        written
      end

      def save(row)
        record = record_of(row)
        return true if savepoint { record.save(**output.fetch(:save, {})) }

        failed(row, record.errors.full_messages.to_sentence, details: { errors: record.errors.details })
        false
      rescue ActiveRecord::ActiveRecordError => e
        failed(row, e.message, details: { exception: e.class.name })
        false
      end
    end
  end
end
