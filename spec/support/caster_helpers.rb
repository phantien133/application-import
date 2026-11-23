# Builds a caster of described_class for a one-column definition.
module CasterHelpers
  def caster_log
    @caster_log ||= StringIO.new
  end

  def build_caster(type: :string, header: "Value", **options)
    definition = ApplicationImport::Definition.new(:users, { "columns" => { "email" => nil } })
    column = ApplicationImport::Column.new(key: :value, headers: [ header ], type:, options:)
    logger = ActiveSupport::Logger.new(caster_log).tap { |l| l.formatter = ->(severity, _, _, msg) { "#{severity} #{msg}\n" } }
    described_class.new(column, definition:, logger:)
  end
end

RSpec.configure do |config|
  config.include CasterHelpers, file_path: %r{spec/lib/application_import/casters/}
end
