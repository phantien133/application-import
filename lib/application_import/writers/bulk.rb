module ApplicationImport
  module Writers
    # output.mode bulk (default with output.model): Model.import (activerecord-import)
    # per output.batch_size rows, each batch in its own savepoint.
    #   options: on_duplicate_key_update from output.upsert, then output.import merged on
    #            top as-is (any activerecord-import option, not validated)
    # failed_instances (validate: true, the activerecord-import default) -> not_saved on
    # their rows; with all_or_none a failure leaves the whole batch unwritten, so its
    # other rows get not_saved too; a database error -> not_saved on every row of the
    # batch. The written count comes from the returned ids where the database returns
    # them (rows skipped by on_duplicate_key_ignore are not counted).
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
        rows_by_record = rows_by_record(batch)
        imported = savepoint { model.import(rows_by_record.keys, **import_options) }
        imported.failed_instances.each { |record| fail_record(rows_by_record.fetch(record), record) }
        written_after(imported, batch, imported.failed_instances)
      rescue *FATAL_ERRORS
        raise
      rescue ActiveModel::RangeError => e
        out_of_range(batch, e)
      rescue *ROW_ERRORS => e
        fail_batch(batch, e)
      end

      # By identity: records compare by id, two new records with the same id would collapse.
      def rows_by_record(batch)
        batch.each_with_object({}.compare_by_identity) { |row, map| map[record_of(row)] = row }
      end

      # Raised before any SQL, for the whole batch: imported row by row to find the culprit.
      def out_of_range(batch, error)
        return fail_batch(batch, error) if batch.one?

        batch.sum { |row| aborted? ? 0 : import([ row ]) }
      end

      def written_after(imported, batch, failed)
        return fail_all_or_none(batch, failed) if failed.any? && import_options[:all_or_none]

        written_count(imported, batch.size - failed.size)
      end

      def written_count(imported, attempted)
        model.connection.supports_insert_returning? ? imported.ids.size : attempted
      end

      def fail_all_or_none(batch, failed)
        failed_rows = failed.to_set { |record| record.object_id }
        batch.each do |row|
          next if failed_rows.include?(row.record.object_id) || aborted?

          failed(row, "not imported: another row of the batch is invalid (all_or_none)", details: { all_or_none: true })
        end
        0
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
