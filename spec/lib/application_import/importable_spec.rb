RSpec.describe ApplicationImport::Importable do
  before do
    ActiveRecord::Base.connection.create_table(:importable_spec_users, temporary: true) do |t|
      t.string :email
      t.string :name
    end
  end

  def model(&)
    stub_const("ImportableUser", Class.new(ApplicationRecord) do
      self.table_name = "importable_spec_users"
      include ApplicationImport::Importable
    end)
    ImportableUser.class_eval(&) if block_given?
    ImportableUser
  end

  def errors(record, import: nil)
    import ? described_class.importing(import) { record.valid? } : record.valid?
    record.errors.map(&:type)
  end

  describe ".importing" do
    it "sets the current import for the block, restoring the previous one" do
      seen = []
      described_class.importing(:users) do
        seen << described_class.current
        described_class.importing("members") { seen << described_class.current }
        seen << described_class.current
      end

      expect([ seen, described_class.current ]).to eq([ %i[ users members users ], nil ])
    end

    it "restores the previous import when the block raises" do
      expect { described_class.importing(:users) { raise "boom" } }.to raise_error("boom")
      expect(described_class.current).to be_nil
    end

    it "returns the block value" do
      expect(described_class.importing(:users) { 42 }).to eq(42)
    end
  end

  describe ".skip?" do
    it "is false outside an import" do
      expect([ described_class.skip?([]), described_class.skip?([ :users ]) ]).to eq([ false, false ])
    end

    it "is true in every import for no list, else only in listed imports" do
      described_class.importing(:users) do
        expect([ described_class.skip?([]), described_class.skip?([ :users ]), described_class.skip?([ :members ]) ])
          .to eq([ true, true, false ])
      end
    end
  end

  describe "import_skip" do
    it "skips the validation kind in every import, not outside" do
      model do
        validates :email, presence: true
        validates :name, presence: true
        import_skip :presence
      end
      record = ImportableUser.new

      expect([ errors(record, import: :users), errors(record) ]).to eq([ [], %i[ blank blank ] ])
    end

    it "covers validators declared after the macro" do
      model do
        import_skip :length
        validates :name, length: { maximum: 2 }
      end

      expect([ errors(ImportableUser.new(name: "long"), import: :x), errors(ImportableUser.new(name: "long")) ]).to eq([ [], %i[ too_long ] ])
    end

    it "only skips in the imports listed with on" do
      model do
        validates :email, presence: true
        import_skip :presence, on: %i[ users ]
      end
      record = ImportableUser.new

      expect([ errors(record, import: :users), errors(record, import: :members) ]).to eq([ [], %i[ blank ] ])
    end

    it "skips validate methods by name, declared before or after" do
      model do
        import_skip :check_a, :check_b
        validate :check_a
        define_method(:check_a) { errors.add(:base, :a) }
        define_method(:check_b) { errors.add(:base, :b) }
        validate :check_b
      end

      expect([ errors(ImportableUser.new, import: :users), errors(ImportableUser.new) ]).to eq([ [], %i[ a b ] ])
    end

    it "keeps other kinds running" do
      model do
        validates :email, presence: true
        validates :name, length: { maximum: 2 }
        import_skip :presence
      end

      expect(errors(ImportableUser.new(name: "long"), import: :users)).to eq(%i[ too_long ])
    end

    it "requires a name" do
      expect { model { import_skip } }.to raise_error(ArgumentError, "import_skip needs at least one validation kind or method name")
    end

    it "records the rules on the class" do
      expect(model { import_skip :uniqueness, on: :users }.import_skip_rules).to eq([ { names: %i[ uniqueness ], imports: %i[ users ] } ])
    end
  end

  describe ".skip_validations (config, no include needed)" do
    let(:plain) do
      stub_const("PlainUser", Class.new(ApplicationRecord) do
        self.table_name = "importable_spec_users"
        validates :email, presence: true
      end)
    end

    it "skips the names during the given imports only" do
      described_class.skip_validations(plain, %i[ presence ], imports: %i[ users ])

      expect([ errors(plain.new, import: :users), errors(plain.new, import: :members), errors(plain.new) ])
        .to eq([ [], %i[ blank ], %i[ blank ] ])
    end

    it "is applied once per class, names and imports" do
      allow(plain).to receive(:skip_callback).and_call_original
      2.times { described_class.skip_validations(plain, %i[ presence ], imports: %i[ users ]) }

      expect(plain).to have_received(:skip_callback).once
    end
  end
end
