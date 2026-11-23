module ApplicationImport
  # Runs one import: validate_file -> open_reader -> read_headers -> process -> verify
  # -> write_rows, then close_reader and handler.after_import whatever happened.
  # The row pipeline (process / verify / write_rows) lives in Runner::Rows.
  class Runner
    include Constants
    include Logging
    include Rows
    include Lifecycle
    include Settling
    include Streaming
    include RowMapping

    attr_reader :definition, :source, :context, :handler, :result, :cache

    # dry_run: run every step up to the write and stop there: nothing is written (no
    # transaction is held), result.stats[:valid] says how many rows would be written.
    def initialize(definition, source, context: {}, logger: ApplicationImport.logger, dry_run: false)
      @definition = definition
      @source = source
      @logger = logger
      @context = context.dup.freeze
      @handler = definition.handler_class.new(definition, @context)
      @result = Result.new(dry_run:)
      @rows_by_line = {}
      @pending_rows = Set.new.compare_by_identity
      @cache = {}
    end

    # definition.reader_class: file.reader, the reader of the file's extension when it is
    # in file.formats, else the one for file.format.
    def reader
      @reader ||= definition.reader_class(source.extension).new(definition, source, logger:)
    end

    # Returns the result. Any exception escaping the steps (a bug in custom code, a
    # library or database error, an interrupt) first marks the result failed with an
    # unexpected_error file error, so close_reader, the summary log and
    # handler.after_import all see the real outcome; it is then re-raised.
    def call
      catch(HALT) { run_steps }
      result
    rescue Exception => e # rubocop:disable Lint/RescueException -- recorded, then re-raised
      fail_unexpectedly(e)
      raise
    ensure
      finish
    end

    private

    STEPS = %i[ validate_file open_reader read_headers process verify write_rows ].freeze

    # A Runner subclass can override run_steps (or single steps) to add or reorder.
    def run_steps
      check_streaming!
      debug { "start #{source.filename}: #{settings_summary}" }
      STEPS.each do |name|
        next if name == :verify && streaming?
        break debug { "dry run: stopping before write_rows" } if name == :write_rows && result.dry_run?

        step(name) { send(name) }
      end
    end

    def step(name = nil)
      debug { "step #{name}" } if name
      yield
    rescue Errors::FileError, Errors::RowError, Errors::RowsError => e
      handle_error(e)
    end

    def handle_error(error)
      result.add_exception(error)
      action = error_action(error)
      halt! if action == :abort
      action
    end

    # Row errors are handled per row inside process / verify (guard). One reaching a
    # step was raised outside any row (e.g. by a file validator): recorded, then abort.
    def error_action(_error)
      :abort
    end

    # The file checker's errors halt at once: file validators and handler.validate_file
    # only run on a file that passed the built-in checks (format, name, size).
    def validate_file
      file_checker.call(source, result)
      halt! if result.file_errors?

      run_validators(:file, source)
      handler.validate_file(source, result)
      halt! if result.file_errors?
    end

    def file_checker
      definition.file_checker_class.new(definition, logger:)
    end

    # Headers are checked before the first data row. A reader that knows them up front
    # returns them from #read_headers (mapped now); a streaming reader (CSV) reports them
    # through on_headers when process reaches the header row. Header errors halt.
    def read_headers
      headers = reader.read_headers
      return map_headers(headers) if headers

      reader.on_headers { |streamed| map_headers(streamed) }
    end

    def map_headers(headers)
      @header_map = HeaderMapper.new(definition, logger:).call(headers, result)
      halt! if result.file_errors?
    end

    def run_validators(stage, subject)
      validators(stage).each { |validator| validator.call(subject, result) }
    end

    def mapper
      spec = definition.mapper
      @mapper ||= spec && spec[:class].new(definition, spec[:options], context:, logger:)
    end

    def transformers
      @transformers ||= definition.transformers.map { |spec| spec[:class].new(definition, spec[:options], context:, logger:) }
    end

    def validators(stage)
      @validators ||= definition.validators.transform_values do |specs|
        specs.map { |spec| spec[:class].new(definition, spec[:options], context:, logger:) }
      end
      @validators.fetch(stage)
    end

    def halt!
      result.halt!
      throw HALT
    end
  end
end
