module ApplicationImport
  module Configs
    # Parses the definition's output section (see Writers).
    #   mode:        raw | save | bulk; default bulk with a model, raw without
    #   model:       ActiveRecord model, required by save and bulk
    #   batch_size:  rows per activerecord-import call (bulk), default 1000
    #   transaction: one transaction around the whole write (default true)
    #   upsert:      bulk only: { conflict_target:, update: } -> on_duplicate_key_update
    #   import:      bulk only: options handed to Model.import as-is (not validated)
    #   save:        save only: options handed to record.save as-is (not validated)
    class OutputParser
      include Checks
      include Constants

      KEYS = %w[ mode model batch_size transaction upsert import save ].freeze
      UPSERT_KEYS = %w[ conflict_target update ].freeze

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
          import: passthrough("import"),
          save: passthrough("save")
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
      end

      def only_for(key, allowed, mode)
        add_error("output.#{key}", "is only used when mode is #{allowed}") if @output.key?(key) && mode && mode != allowed
      end

      def passthrough(key)
        mapping(@output[key], "output.#{key}").deep_symbolize_keys
      end

      def upsert(value)
        return if value.nil?

        upsert = mapping(value, "output.upsert")
        check_keys(upsert, UPSERT_KEYS, "output.upsert")
        update = upsert.key?("update") ? names(upsert["update"], "output.upsert.update").map(&:to_sym) : []
        check_columns(update, @column_keys, "output.upsert.update")
        { conflict_target: names(upsert["conflict_target"], "output.upsert.conflict_target").map(&:to_sym), update: }
      end
    end
  end
end
