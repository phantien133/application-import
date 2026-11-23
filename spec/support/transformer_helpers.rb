# Builds a transformer of described_class with options and runs it on attributes.
module TransformerHelpers
  def transformer_definition
    ApplicationImport::Definition.new(:users, { "columns" => { "email" => nil } })
  end

  def transform(attributes, context: {}, **options)
    row = ApplicationImport::Row.new(line: 2, attributes:, raw: attributes.values)
    [ described_class.new(transformer_definition, options, context:).call(attributes, row), row ]
  end
end

RSpec.configure do |config|
  config.include TransformerHelpers, file_path: %r{spec/lib/application_import/transformers/}
end
