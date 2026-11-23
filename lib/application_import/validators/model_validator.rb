module ApplicationImport
  module Validators
    # type: model — runs the model's own validations on the row.
    #   model:   model class (default: output.model)
    #   context: validation context(s) passed to valid?, a name or a list. A custom context
    #            replaces the default (create for a new record): use [ create, import ]
    #            to also run `on: :create` validations.
    #   except:  validation kinds or error types whose errors are ignored, e.g.
    #            [ uniqueness ] (-> taken). The validators still run: to not run them at
    #            all (e.g. no per-row uniqueness query), declare it on the model with
    #            ApplicationImport::Importable `import_skip :uniqueness, on: :<import>`.
    #   skip:    validation kinds or validate method names not run in this step for this
    #            import (see ApplicationImport::Importable; same as the model macro
    #            `import_skip ..., on: :<import>`). The write step still runs them.
    # Validation goes through the model (record.valid?) inside Importable.importing, so
    # the model's import_skip rules and `skip` apply to this step only.
    # The row's record is validated when it is an instance of the model, otherwise a new
    # one is built from the declared columns. Each error becomes a row error: code = the
    # error type (:blank, :taken, ...; :invalid for message-only errors), column = the
    # attribute (none for :base), message = the full message.
    class ModelValidator < RowValidator
      KINDS = {
        presence: %i[ blank ], absence: %i[ present ], uniqueness: %i[ taken ],
        length: %i[ too_long too_short wrong_length ], format: %i[ invalid ],
        inclusion: %i[ inclusion ], exclusion: %i[ exclusion ], confirmation: %i[ confirmation ],
        acceptance: %i[ accepted ], comparison: %i[ greater_than greater_than_or_equal_to equal_to less_than
          less_than_or_equal_to other_than ],
        numericality: %i[ not_a_number not_an_integer greater_than greater_than_or_equal_to equal_to
          less_than less_than_or_equal_to other_than odd even in ]
      }.freeze

      def call(row, _result)
        record = record_for(row)
        skip_validations(record.class)
        Importable.importing(definition.name) { record.valid?(context_option) }
        record.errors.each { |error| add_error(row, error) unless ignored?(error) }
      end

      def model
        @model ||= options[:model] || definition.output[:model] ||
          raise(Errors::ConfigError, "#{definition.name}: the model validator needs a model or output.model")
      end

      private

      def skip_validations(klass)
        names = Array(options[:skip])
        Importable.skip_validations(klass, names, imports: [ definition.name ]) if names.any?
      end

      def context_option
        contexts = Array(options[:context]).map(&:to_sym)
        (contexts.size > 1) ? contexts : contexts.first
      end

      def record_for(row)
        return row.record if row.record.is_a?(model)

        RecordBuilder.build(model, row.attributes, definition.columns, assign: definition.assign_rules,
          generated: row.generated_keys)
      end

      def add_error(row, error)
        code = error.type.is_a?(Symbol) ? error.type : :invalid
        column = (error.attribute == :base) ? nil : error.attribute
        row.add_error(code:, message: error.full_message, column:)
      end

      def ignored?(error)
        ignored_types.include?(error.type)
      end

      def ignored_types
        @ignored_types ||= Array(options[:except]).flat_map { |name| KINDS.fetch(name.to_sym) { [ name.to_sym ] } }
      end
    end
  end
end
