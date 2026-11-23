RSpec.describe ApplicationImport::Configs::TransformerParser do
  let(:errors) { [] }

  def parse(config)
    described_class.new(config, errors).parse
  end

  it "returns no transformers when absent" do
    expect([ parse(nil), parse([]) ]).to eq([ [], [] ])
  end

  it "parses custom classes with their options" do
    expect(parse([ { "class" => "Imports::FullName", "separator" => " ", "nested" => { "a" => 1 } } ]))
      .to eq([ { type: nil, class: "Imports::FullName", options: { separator: " ", nested: { a: 1 } } } ])
  end

  describe "built-in types" do
    def parsed(spec)
      result = parse([ spec ]).first
      expect(errors).to eq([])
      [ result[:type], result[:class], result[:options] ]
    end

    it "parses concat (separator optional)" do
      expect([ parsed("type" => "concat", "from" => %w[ first last ], "to" => "full_name", "separator" => ","),
        parsed("type" => "concat", "from" => "first", "to" => "name").last ])
        .to eq([ [ :concat, "ApplicationImport::Transformers::Concat", { from: %i[ first last ], to: :full_name, separator: "," } ],
          { from: %i[ first ], to: :name } ])
    end

    it "parses default with any value, nil and false included" do
      expect([ parsed("type" => "default", "attribute" => "role", "value" => "member"),
        parsed("type" => "default", "attribute" => "active", "value" => false).last ])
        .to eq([ [ :default, "ApplicationImport::Transformers::Default", { attribute: :role, value: "member" } ],
          { attribute: :active, value: false } ])
    end

    it "parses map, stringifying the table keys" do
      expect(parsed("type" => "map", "attribute" => "role", "values" => { "Admin" => "admin", 1 => "one" }, "to" => "role_code",
        "case_sensitive" => true, "strict" => true))
        .to eq([ :map, "ApplicationImport::Transformers::Map",
          { attribute: :role, values: { "Admin" => "admin", "1" => "one" }, to: :role_code, case_sensitive: true, strict: true } ])
    end

    it "parses normalize with one or several attributes" do
      expect([ parsed("type" => "normalize", "attributes" => "email", "with" => %w[ strip downcase ]),
        parsed("type" => "normalize", "attributes" => %w[ a b ], "with" => "squish").last ])
        .to eq([ [ :normalize, "ApplicationImport::Transformers::Normalize", { attributes: %i[ email ], with: %w[ strip downcase ] } ],
          { attributes: %i[ a b ], with: %w[ squish ] } ])
    end

    it "parses context" do
      expect(parsed("type" => "context", "key" => "user_id", "to" => "created_by_id"))
        .to eq([ :context, "ApplicationImport::Transformers::Context", { key: :user_id, to: :created_by_id } ])
    end
  end

  it "has a parser entry and a class for every built-in" do
    expect([ described_class::KEYS.keys, described_class::REQUIRED.keys ]).to all(match_array(described_class::BUILTIN.keys))
    expect(described_class::BUILTIN.values.map(&:constantize)).to all(be < ApplicationImport::Transformers::Base)
  end

  it "rejects invalid lists and entries" do
    parse("x")
    parse([ 1, {}, { "type" => "concat", "class" => "X" }, { "type" => "upper" }, { "class" => nil }, { "class" => 1 } ])

    expect(errors).to eq([
      "transformers must be a list", "transformers[0] must be a mapping", "transformers[1] needs exactly one of type, class",
      "transformers[2] needs exactly one of type, class", "transformers[3].type must be one of concat, default, map, normalize, context",
      "transformers[4].class must be a class name", "transformers[5].class must be a class name"
    ])
  end

  it "reports every missing option" do
    parse(%w[ concat default map normalize context ].map { |type| { "type" => type } })

    expect(errors).to eq([
      "transformers[0] needs from, to", "transformers[1] needs attribute, value", "transformers[2] needs attribute, values",
      "transformers[2].values must be a non-empty mapping", "transformers[3] needs attributes, with",
      "transformers[3].with must be a non-empty list of names", "transformers[4] needs key, to"
    ])
  end

  it "reports missing, unknown and invalid built-in options" do
    parse([
      { "type" => "concat", "from" => [] },
      { "type" => "map", "attribute" => "role", "values" => {}, "strict" => "yes", "extra" => 1 },
      { "type" => "normalize", "attributes" => [ "email" ], "with" => %w[ strip titleize ] },
      { "type" => "context", "key" => "", "to" => "x" },
      { "type" => "concat", "from" => [ "a" ], "to" => "b", "separator" => 1 }
    ])

    expect(errors).to contain_exactly(
      "transformers[0] needs to", "transformers[0].from must be a non-empty list of names",
      "transformers[1] has unknown keys: extra", "transformers[1].values must be a non-empty mapping",
      "transformers[1].strict must be true or false",
      "transformers[2].with has unknown operations: titleize",
      "transformers[3].key must be a name",
      "transformers[4].separator must be a string"
    )
  end

  describe ".resolve!" do
    it "resolves classes and rejects non transformers" do
      klass = stub_const("FullName", Class.new(ApplicationImport::Transformers::Base))
      specs = [ { class: "FullName" }, { class: "ApplicationImport::Transformers::Concat" } ]

      described_class.resolve!(specs)

      expect(specs.pluck(:class)).to eq([ klass, ApplicationImport::Transformers::Concat ])
      expect { described_class.resolve!([ { class: "String" } ]) }
        .to raise_error(ApplicationImport::Errors::InvalidTransformerError, "String must inherit from ApplicationImport::Transformers::Base")
    end
  end
end
