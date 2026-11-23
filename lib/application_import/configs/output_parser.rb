module ApplicationImport
  module Configs
    # Parses the definition's output section (see Writers).
    #   mode:        raw | save | bulk; default bulk with a model, raw without
    #   model:       ActiveRecord model, required by save and bulk
    #   batch_size:  rows per activerecord-import call (bulk), default 1000
    #   transaction: one transaction around the whole write (default true)
    #   upsert:      bulk only: { conflict_target:, update: } (update required) ->
    #                on_duplicate_key_update; to skip conflicting rows use
    #                import: { on_duplicate_key_ignore: true }
    #   import:      bulk only: activerecord-import options from IMPORT_OPTIONS (values
    #                handed as-is); on_duplicate_key_* not together with upsert
    #   save:        save only: record.save options from SAVE_OPTIONS (values as-is)
    class OutputParser
      include Checks
      include Constants

      KEYS = %w[ mode model batch_size transaction upsert import save ].freeze
      UPSERT_KEYS = %w[ conflict_target update ].freeze
      # Options the bulk writer supports; others (raise_error, synchronize,
      # track_validation_failures, returning, ...) change the result shape it relies on.
      IMPORT_OPTIONS = %i[ validate validate_with_context validate_uniqueness timestamps recursive batch_size
        on_duplicate_key_update on_duplicate_key_ignore all_or_none ].freeze
      SAVE_OPTIONS = %i[ validate context touch ].freeze

      def initialize(config, column_keys, errors)
        @errors = errors
        @output = mapping(config, "output")
        @column_keys = column_keys
      end

      def parse
        check_keys(@output, KEYS, "output")
        model = class_name(@output["model"], "output.model")
        mode = mode(model)
        check_mode_options(mode)
        {
          mode:, model:,
          batch_size: integer(@output.fetch("batch_size", DEFAULT_BATCH_SIZE), "output.batch_size"),
          transaction: boolean(@output.fetch("transaction", true), "output.transaction"),
          upsert: upsert(@output["upsert"]),
          import: passthrough("import", IMPORT_OPTIONS),
          save: passthrough("save", SAVE_OPTIONS)
        }
      end

      private

      def mode(model)
        default = model ? "bulk" : "raw"
        mode = one_of(@output.fetch("mode", default), OUTPUT_MODES, "output.mode")
        add_error("output.model", "is required when mode is #{mode}") if %i[ save bulk ].include?(mode) && model.nil?
        mode
      end

      def check_mode_options(mode)
        %w[ upsert import ].each { |key| only_for(key, :bulk, mode) }
        only_for("save", :save, mode)
        conflicts = mapping(@output["import"], "output.import").keys & %w[ on_duplicate_key_update on_duplicate_key_ignore ]
        add_error("output.import", "#{conflicts.join(", ")} cannot be combined with upsert") if @output.key?("upsert") && conflicts.any?
      end

      def only_for(key, allowed, mode)
        add_error("output.#{key}", "is only used when mode is #{allowed}") if @output.key?(key) && mode && mode != allowed
      end

      def passthrough(key, allowed)
        options = mapping(@output[key], "output.#{key}").deep_symbolize_keys
        unknown = options.keys - allowed
        add_error("output.#{key}", "has unsupported options: #{unknown.join(", ")}") if unknown.any?
        options.slice(*allowed)
      end

      def upsert(value)
        return if value.nil?

        upsert = mapping(value, "output.upsert")
        check_keys(upsert, UPSERT_KEYS, "output.upsert")
        update = names(upsert["update"], "output.upsert.update").map(&:to_sym)
        { conflict_target: names(upsert["conflict_target"], "output.upsert.conflict_target").map(&:to_sym), update: }
      end
    end
  end
end
