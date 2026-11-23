RSpec.describe ApplicationImport::Validators::ModelValidator do
  let(:result) { ApplicationImport::Result.new }

  before do
    ActiveRecord::Base.connection.create_table(:model_validator_spec_users, temporary: true) do |t|
      t.string :email
      t.string :name
      t.integer :age
    end
    stub_const("MvUser", Class.new(ApplicationRecord) do
      self.table_name = "model_validator_spec_users"
      validates :email, presence: true, uniqueness: true
      validates :name, length: { maximum: 5 }
      validates :age, numericality: { greater_than: 0 }, allow_nil: true
      validate { errors.add(:base, "is blocked") if name == "bad" }
      validate(on: :import) { errors.add(:name, :reserved, message: "is reserved") if name == "admin" }
    end)
    stub_const("OtherUser", Class.new(ApplicationRecord) do
      self.table_name = "model_validator_spec_users"
      validates :name, presence: true
    end)
  end

  def definition(output: { "model" => "MvUser" })
    ApplicationImport::Definition.new(:users, { "columns" => { "email" => nil, "name" => nil, "age" => nil }, "output" => output })
  end

  def validator(options = {}, definition: self.definition)
    described_class.new(definition, options)
  end

  def row(attributes, record: nil)
    ApplicationImport::Row.new(line: 2, attributes:, raw: attributes.values, record:)
  end

  def errors_of(attributes, options = {}, **row_options)
    row = row(attributes, **row_options)
    validator(options).call(row, result)
    row.errors.map { |error| [ error.code, error.column, error.message ] }
  end

  it "adds no error for a valid row" do
    expect(errors_of({ email: "a@x.io", name: "Ann", age: 3 })).to eq([])
  end

  it "maps every model error to a row error with type, attribute and full message" do
    expect(errors_of({ email: nil, name: "Annabelle", age: 0 })).to eq([
      [ :blank, "email", "Email can't be blank" ],
      [ :too_long, "name", "Name is too long (maximum is 5 characters)" ],
      [ :greater_than, "age", "Age must be greater than 0" ]
    ])
  end

  it "reports base errors without column and message-only errors as :invalid" do
    expect(errors_of({ email: "a@x.io", name: "bad" })).to eq([ [ :invalid, nil, "is blocked" ] ])
  end

  it "checks the database for uniqueness" do
    MvUser.create!(email: "taken@x.io")

    expect(errors_of({ email: "taken@x.io" })).to eq([ [ :taken, "email", "Email has already been taken" ] ])
  end

  describe "context" do
    it "runs the default context when absent" do
      expect(errors_of({ email: "a@x.io", name: "admin" })).to eq([])
    end

    it "runs the given validation context" do
      expect(errors_of({ email: "a@x.io", name: "admin" }, { context: "import" })).to eq([ [ :reserved, "name", "Name is reserved" ] ])
    end
  end

  def queries
    count = 0
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, payload| count += 1 unless payload[:name] == "SCHEMA" }
    yield
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  describe "skip (only in this step of this import)" do
    def import_definition(name)
      ApplicationImport::Definition.new(name, { "columns" => { "email" => nil, "name" => nil, "age" => nil }, "output" => { "model" => "MvUser" } })
    end

    it "does not run the skipped validators at all (no uniqueness query)" do
      expect(queries { validator({}).call(row({ email: "a@x.io", name: "Ann" }), result) }).to eq(1)
      expect(queries { validator({ skip: %i[ uniqueness ] }).call(row({ email: "a@x.io", name: "Ann" }), result) }).to eq(0)
    end

    it "applies to every model validator of the same import once configured" do
      validator({ skip: %i[ uniqueness ] }).call(row({ email: "a@x.io" }), result)

      expect(queries { validator({}).call(row({ email: "a@x.io", name: "Ann" }), result) }).to eq(0)
    end

    it "keeps every other validator and custom validate blocks" do
      expect(errors_of({ email: nil, name: "bad" }, { skip: %i[ uniqueness ] }).map(&:first)).to eq(%i[ blank invalid ])
    end

    it "skips validate methods by name" do
      MvUser.define_method(:no_admins) { errors.add(:name, :reserved, message: "is reserved") if name == "root" }
      MvUser.validate :no_admins

      expect([ errors_of({ email: "a@x.io", name: "root" }), errors_of({ email: "a@x.io", name: "root" }, { skip: %i[ no_admins ] }) ])
        .to eq([ [ [ :reserved, "name", "Name is reserved" ] ], [] ])
    end

    it "leaves the model validating as usual outside this step (e.g. the write step)" do
      MvUser.create!(email: "taken@x.io")
      validator({ skip: %i[ uniqueness ] }).call(row({ email: "taken@x.io" }), result)
      record = MvUser.new(email: "taken@x.io")

      expect([ record.valid?, record.errors.map(&:type) ]).to eq([ false, %i[ taken ] ])
    end

    it "only applies to the import it is configured in" do
      MvUser.create!(email: "taken@x.io")
      described_class.new(import_definition(:users), { skip: %i[ uniqueness ] }).call(row({ email: "taken@x.io" }), result)
      other = row({ email: "taken@x.io" })
      described_class.new(import_definition(:members), {}).call(other, result)

      expect(other.errors.map(&:code)).to eq(%i[ taken ])
    end

    it "honours the model's import_skip macro in this step" do
      MvUser.include(ApplicationImport::Importable)
      MvUser.import_skip :uniqueness, on: :users
      MvUser.create!(email: "taken@x.io")

      expect([ errors_of({ email: "taken@x.io" }), MvUser.new(email: "taken@x.io").valid? ]).to eq([ [], false ])
    end
  end

  describe "except (errors ignored, validators still run)" do
    it "hides the errors but still runs the validators" do
      MvUser.create!(email: "taken@x.io")
      validator = validator({ except: %i[ uniqueness ] })
      row = row({ email: "taken@x.io" })

      expect(queries { validator.call(row, result) }).to eq(1)
      expect(row.errors).to eq([])
    end
  end

  describe "context list" do
    before { MvUser.validate(on: :create) { errors.add(:email, :created, message: "is checked on create") if email == "c@x.io" } }

    it "runs every listed context, the default one included" do
      expect([ errors_of({ email: "c@x.io" }, { context: "import" }), errors_of({ email: "c@x.io" }, { context: %w[ create import ] }).map(&:first) ])
        .to eq([ [], %i[ created ] ])
    end
  end

  describe "except" do
    before { MvUser.create!(email: "taken@x.io") }

    it "ignores errors of the given validation kinds" do
      expect(errors_of({ email: "taken@x.io", name: "Annabelle" }, { except: %i[ uniqueness length ] })).to eq([])
    end

    it "ignores given error types too" do
      expect(errors_of({ email: nil, name: "Annabelle" }, { except: %i[ blank ] }).map(&:first)).to eq(%i[ too_long ])
    end

    it "keeps other errors" do
      expect(errors_of({ email: "taken@x.io", name: "Annabelle" }, { except: %i[ uniqueness ] }).map(&:first)).to eq(%i[ too_long ])
    end
  end

  describe "record" do
    it "validates the row's record when it is an instance of the model" do
      record = MvUser.new(email: nil)
      row = row({ email: "ignored@x.io" }, record:)

      validator.call(row, result)

      expect([ row.errors.map(&:code), record.errors.any? ]).to eq([ %i[ blank ], true ])
    end

    it "builds a record from the declared columns otherwise" do
      expect(errors_of({ :email => "a@x.io", "name" => "Annabelle" }, record: Object.new)).to eq([])
    end

    it "uses the model option over output.model" do
      expect(errors_of({ email: nil, name: nil }, { model: OtherUser })).to eq([ [ :blank, "name", "Name can't be blank" ] ])
    end
  end

  describe "#model" do
    it "is the model option, else output.model" do
      expect([ validator.model, validator({ model: OtherUser }).model ]).to eq([ MvUser, OtherUser ])
    end

    it "raises ConfigError without any model" do
      expect { validator(definition: definition(output: {})).model }
        .to raise_error(ApplicationImport::Errors::ConfigError, "users: the model validator needs a model or output.model")
    end
  end

  it "adds nothing to the result directly" do
    validator.call(row({ email: nil }), result)

    expect(result.errors).to eq([])
  end
end
