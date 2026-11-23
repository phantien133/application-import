module ApplicationImport
  class Runner
    # output.stream: kept rows are written by output.batch_size while the file is read
    # (Runner::Rows#process), so the records of written rows can be released. The rest
    # is written by write_rows. verify is not run (rows are already written); a handler
    # overriding verify is a configuration error, raised before anything is read.
    module Streaming
      private

      def streaming?
        definition.output[:stream] == true
      end

      def check_streaming!
        return unless streaming? && handler.method(:verify).owner != Handler

        raise Errors::ConfigError, "#{definition.name}: output.stream cannot be used with #{handler.class.name}#verify " \
                                   "(rows are written before verify)"
      end

      # Called after each row is settled: queue it if kept, write a full batch. A dry run
      # writes nothing: the row's record is released at once.
      def stream(row)
        return row.release! if result.dry_run?

        pending = (@unwritten ||= [])
        pending << row unless row.skipped?
        return if pending.size < (definition.output[:batch_size] || Constants::DEFAULT_BATCH_SIZE)

        debug { "stream: writing a batch of #{pending.size} rows (up to line #{row.line})" }
        write_batch(unwritten_rows)
      end

      # Queued rows still kept (a later check may have skipped one), then cleared.
      def unwritten_rows
        batch = (@unwritten || []).reject(&:skipped?)
        @unwritten = []
        batch
      end
    end
  end
end
