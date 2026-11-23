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
