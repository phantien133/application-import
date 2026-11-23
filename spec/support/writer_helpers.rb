# A temporary writer_spec_users table (email unique, name required by the model) and
# rows with records for writer specs.
module WriterHelpers
  def create_writer_table
    ActiveRecord::Base.connection.create_table(:writer_spec_users, temporary: true) do |t|
      t.string :email
      t.string :name
      t.index :email, unique: true
    end
    stub_const("WriterSpecUser", Class.new(ApplicationRecord) do
      self.table_name = "writer_spec_users"
      validates :name, presence: true
    end)
  end

  def writer_definition(output = {})
    ApplicationImport::Definition.new(:users, {
      "columns" => { "email" => nil, "name" => nil }, "output" => { "model" => "WriterSpecUser", **output }
    })
  end

  def writer_rows(*pairs)
    pairs.each_with_index.map do |(email, name), index|
      attributes = { email:, name: }
      ApplicationImport::Row.new(line: index + 2, attributes:, raw: [ email, name ], record: WriterSpecUser.new(attributes))
    end
  end

  # on_failure double: records failed lines, answers the given action.
  def on_failure(action = :skip)
    failures = []
    callback = lambda do |row|
      failures << row.line
      action
    end
    [ callback, failures ]
  end
end

RSpec.configure do |config|
  config.include WriterHelpers, file_path: %r{spec/lib/application_import/writers}
end
