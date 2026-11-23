module ApplicationImport
  module Constants
    HALT = :application_import_halt
    NAME_FORMAT = /\A[a-z][a-z0-9_]*\z/
    YAML_EXTENSIONS = %w[ .yml .yaml ].freeze

    COMPLETED = :completed
    COMPLETED_WITH_ERRORS = :completed_with_errors
    FAILED = :failed
    EMPTY_STATS = { total: 0, valid: 0, invalid: 0, written: 0 }.freeze

    FORMATS = %w[ csv xlsx ].freeze
    COLUMN_TYPES = %w[ string integer decimal boolean date datetime ].freeze
    VALIDATOR_STAGES = %w[ file row rows verify ].freeze
    VALIDATOR_BASES = {
      file: "ApplicationImport::Validators::FileValidator",
      row: "ApplicationImport::Validators::RowValidator",
      rows: "ApplicationImport::Validators::RowsValidator",
      verify: "ApplicationImport::Validators::VerifyValidator"
    }.freeze
    BUILTIN_VALIDATORS = {
      file: {}.freeze,
      row: { model: "ApplicationImport::Validators::ModelValidator" }.freeze,
      rows: { unique_in_file: "ApplicationImport::Validators::UniqueInFile" }.freeze,
      verify: {}.freeze
    }.freeze
    OUTPUT_MODES = %w[ raw save bulk ].freeze
    ON_ERROR_MODES = %w[ abort skip ].freeze
    ROW_ERRORS = %w[ first all ].freeze
    UNKNOWN_HEADERS = %w[ skip keep assign reject ].freeze
    EXTRA_CELLS = %w[ warn ignore reject ].freeze
    EMAIL_FORMAT = "email".freeze

    DEFAULT_COLUMN_TYPE = "string".freeze
    DEFAULT_ON_ERROR = "abort".freeze
    DEFAULT_ROW_ERRORS = "first".freeze
    DEFAULT_ENCODING = "UTF-8".freeze
    DEFAULT_FORMAT = "csv".freeze
    DEFAULT_UNKNOWN_HEADERS = "skip".freeze
    DEFAULT_EXTRA_CELLS = "warn".freeze
    DEFAULT_BATCH_SIZE = 1000
  end
end
