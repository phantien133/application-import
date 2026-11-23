module ApplicationImport
  module Writers
    # output.mode bulk (default with output.model): Model.import (activerecord-import)
    # per output.batch_size rows, each batch in its own savepoint.
    #   options: on_duplicate_key_update from output.upsert, then output.import merged on
    #            top as-is (any activerecord-import option, not validated)
    # failed_instances (validate: true, the activerecord-import default) -> not_saved on
    # their rows; a database error -> not_saved on every row of the batch.
    class Bulk < Base
      private

      def write(rows)
        written = 0
        rows.each_slice(output[:batch_size] || Constants::DEFAULT_BATCH_SIZE) do |batch|
          break if aborted?

          written += import(batch)
        end
        written
      end

      def import(batch)
        rows_by_record = batch.to_h { |row| [ record_of(row), row ] }.compare_by_identity
        failed_records = import_records(rows_by_record.keys)
        failed_records.each { |record| fail_record(rows_by_record.fetch(record), record) }
        batch.size - failed_records.size
      rescue ActiveRecord::ActiveRecordError => e
        fail_batch(batch, e)
      end

      def import_records(records)
        savepoint { model.import(records, **import_options) }.failed_instances
      end

      def fail_batch(batch, error)
        batch.each { |row| failed(row, error.message, details: { exception: error.class.name }) unless aborted? }
        0
      end

      def fail_record(row, record)
        return if aborted?

        failed(row, record.errors.full_messages.to_sentence, details: { errors: record.errors.details })
      end

      def import_options
        @import_options ||= upsert_options.merge(output.fetch(:import, {}))
      end

      def upsert_options
        upsert = output[:upsert]
        return {} unless upsert

        { on_duplicate_key_update: { conflict_target: upsert[:conflict_target], columns: upsert[:update] } }
      end
    end
  end
end
