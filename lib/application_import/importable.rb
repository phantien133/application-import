module ApplicationImport
  # Skips model validations in the model validator step (type: model) of a given import,
  # declared on the model or in the import definition:
  #
  #   class User < ApplicationRecord
  #     include ApplicationImport::Importable
  #     import_skip :uniqueness                            # in every import
  #     import_skip :length, :check_manager, on: :users    # only in the users import
  #   end
  #
  #   # config/imports/users.yml (no include needed): this import only
  #   validators:
  #     row:
  #       - type: model
  #         skip: [ uniqueness, check_manager ]
  #
  # Names are validation kinds (presence, uniqueness, length, format, numericality, ...:
  # a validator's `kind`) or the method names of `validate :method` callbacks. The model
  # gets conditional skip_callbacks, active only inside Importable.importing, which the
  # model validator wraps around record.valid?. Everywhere else — the write step
  # (record.save, Model.import with validate), other imports, the rest of the app — the
  # model validates as usual.
  module Importable
    extend ActiveSupport::Concern

    STATE_KEY = :application_import_importing
    APPLIED = Concurrent::Map.new

    class << self
      # Runs the block as the import `name`.
      def importing(name)
        previous = ActiveSupport::IsolatedExecutionState[STATE_KEY]
        ActiveSupport::IsolatedExecutionState[STATE_KEY] = name.to_sym
        yield
      ensure
        ActiveSupport::IsolatedExecutionState[STATE_KEY] = previous
      end

      # The import running in this thread / fiber, or nil.
      def current
        ActiveSupport::IsolatedExecutionState[STATE_KEY]
      end

      def skip?(imports)
        name = current
        !name.nil? && (imports.empty? || imports.include?(name))
      end

      # Skips the named validations of klass during the given imports (all imports when
      # empty). Idempotent: applied once per class, names and imports.
      def skip_validations(klass, names, imports: [])
        rule = { names: names.map(&:to_sym).sort, imports: imports.map(&:to_sym).sort }.freeze
        APPLIED.compute_if_absent([ klass, rule ]) do
          log_skip(klass, rule)
          klass.validators.each { |validator| skip_validator(klass, validator, rule) }
          skip_methods(klass, rule, rule[:names])
          true
        end
      end

      def log_skip(klass, rule)
        ApplicationImport.logger&.debug do
          "[ApplicationImport] #{klass.name}: skipping #{rule[:names].join(", ")} in the model validator of " \
            "#{rule[:imports].empty? ? "every import" : rule[:imports].join(", ")}"
        end
      end

      def skip_validator(klass, validator, rule)
        return unless rule[:names].include?(validator.kind)

        imports = rule[:imports]
        klass.skip_callback(:validate, :before, validator, if: -> { Importable.skip?(imports) })
      end

      def skip_methods(klass, rule, methods)
        defined = klass._validate_callbacks.map(&:filter)
        (rule[:names] & methods & defined).each do |method|
          imports = rule[:imports]
          klass.skip_callback(:validate, :before, method, if: -> { Importable.skip?(imports) })
        end
      end
    end

    included do
      class_attribute :import_skip_rules, instance_accessor: false, default: []
    end

    # The macro, plus hooks covering validations declared after it.
    module ClassMethods
      def import_skip(*names, on: nil)
        raise ArgumentError, "import_skip needs at least one validation kind or method name" if names.empty?

        rule = { names: names.map(&:to_sym), imports: Array(on).map(&:to_sym) }.freeze
        self.import_skip_rules = [ *import_skip_rules, rule ]
        validators.each { |validator| Importable.skip_validator(self, validator, rule) }
        Importable.skip_methods(self, rule, rule[:names])
      end

      def validates_with(*args, &)
        before = validators
        super
        (validators - before).each do |validator|
          import_skip_rules.each { |rule| Importable.skip_validator(self, validator, rule) }
        end
      end

      def validate(*args, &)
        super
        methods = args.grep(Symbol)
        import_skip_rules.each { |rule| Importable.skip_methods(self, rule, methods) }
      end
    end
  end
end
