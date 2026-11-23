module ApplicationImport
  class Runner
    # Reader open / close and the end of a run: unexpected exceptions recorded on the
    # result, summary log and handler.after_import.
    module Lifecycle
      private

      # The reader may hold the file open from here until close_reader (after process).
      def open_reader
        reader.open
        @reader_open = true
      end

      # Runs after process, whatever happened; a failure to close is logged, not raised,
      # so it never hides the import's own result or exception.
      def close_reader
        return unless @reader_open

        @reader_open = false
        reader.close
      rescue => e
        error("closing the reader failed: #{e.class}: #{e.message}")
      end

      def fail_unexpectedly(exception)
        result.add_file_error(:unexpected_error, "import stopped by #{exception.class}: #{exception.message}",
          details: { exception: exception.class.name })
        result.halt!
        error("#{exception.class}: #{exception.message}")
      end

      # Always runs: close the reader, log the summary, call after_import. A failure in
      # after_import is logged and reported, never raised: rows may already be committed,
      # and raising would hide the result (or the original exception).
      def settings_summary
        reader_name = definition.reader_class(source.extension).name.demodulize
        "reader #{reader_name}, output #{output_summary}, stream #{streaming?}, dry_run #{result.dry_run?}, " \
          "row_errors #{definition.on_error.row_errors}"
      end

      def output_summary
        output = definition.output
        [ output[:mode], output[:model]&.name ].compact.join(" ")
      end

      def finish
        count_valid
        close_reader
        info("finished #{source.filename}#{" (dry run, rolled back)" if result.dry_run?}: #{result.status}, " \
             "#{result.stats.map { |key, value| "#{key} #{value}" }.join(", ")}")
        run_after_import
      end

      # Dry run: the steps run in a transaction (on output.model's connection, else
      # ActiveRecord::Base's) that is always rolled back. HALT is caught inside it, so
      # no throw crosses the transaction (Rails would commit); after_import runs after the
      # rollback and sees result.dry_run?.
      def within_dry_run(&)
        return yield unless result.dry_run?

        (definition.output[:model] || ActiveRecord::Base).transaction(requires_new: true) do
          yield
          raise ActiveRecord::Rollback
        end
      end

      # valid: rows read without any error (total = valid + invalid).
      def count_valid
        stats = result.stats
        stats[:valid] = stats[:total] - stats[:invalid]
      end

      def run_after_import
        handler.after_import(result)
      rescue => e
        error("after_import failed: #{e.class}: #{e.message}")
        Rails.error.report(e, handled: true, context: { import: definition.name.to_s })
      end
    end
  end
end
