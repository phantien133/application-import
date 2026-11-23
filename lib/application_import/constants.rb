module ApplicationImport
  module Constants
    HALT = :application_import_halt
    NAME_FORMAT = /\A[a-z_][a-z0-9_]*\z/

    COMPLETED = :completed
    COMPLETED_WITH_ERRORS = :completed_with_errors
    FAILED = :failed
    EMPTY_STATS = { total: 0, valid: 0, invalid: 0, written: 0 }.freeze

    FORMATS = %w[ csv xlsx ].freeze
    COLUMN_TYPES = %w[ string integer decimal boolean date datetime ].freeze
    VALIDATOR_TYPES = %w[ unique_in_file ].freeze
    VALIDATOR_SCOPES = %w[ file row ].freeze
    OUTPUT_MODES = %w[ raw database ].freeze
    ON_ERROR_MODES = %w[ abort skip ].freeze
    EMAIL_FORMAT = "email".freeze

    DEFAULT_FORMATS = %w[ csv ].freeze
    DEFAULT_COLUMN_TYPE = "string".freeze
    DEFAULT_VALIDATOR_SCOPE = "file".freeze
    DEFAULT_OUTPUT_MODE = "raw".freeze
    DEFAULT_ON_ERROR = "abort".freeze
    DEFAULT_ENCODING = "UTF-8".freeze
    DEFAULT_MAX_SIZE = 10 * 1024 * 1024
    DEFAULT_MAX_ROWS = 100_000
    DEFAULT_BATCH_SIZE = 1000
  end
end
