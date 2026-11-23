RSpec.describe ApplicationImport::Configs::ValidatorParser do
  let(:errors) { [] }

  def parse(config)
    described_class.new(config, %i[ email name ], errors).parse
  end

  it "returns every stage empty by default" do
    expect(parse(nil)).to eq(file: [], row: [], rows: [], verify: [])
    expect(errors).to be_empty
  end

  it "parses built-in and custom validators per stage" do
    result = parse({
      "file" => [ { "class" => "Imports::FileDate" } ],
      "row" => [ { "type" => "model", "context" => "import" } ],
      "rows" => [ { "type" => "unique_in_file", "keys" => [ "email" ], "case_sensitive" => false } ],
      "verify" => [ { "class" => "Imports::ManagersExist", "batch" => 100 } ]
    })

    expect(result).to eq(
      file: [ { type: nil, class: "Imports::FileDate", options: {} } ],
      row: [ { type: :model, class: "ApplicationImport::Validators::ModelValidator", options: { context: "import" } } ],
      rows: [ { type: :unique_in_file, class: "ApplicationImport::Validators::UniqueInFile",
                options: { keys: [ :email ], case_sensitive: false } } ],
      verify: [ { type: nil, class: "Imports::ManagersExist", options: { batch: 100 } } ]
    )
    expect(errors).to be_empty
  end

  it "rejects unknown stages, non-list stages and non-mapping entries" do
    parse({ "cells" => [], "row" => {}, "rows" => [ "unique_in_file" ] })

    expect(errors).to eq([
      "validators has unknown keys: cells",
      "validators.row must be a list",
      "validators.rows[0] must be a mapping"
    ])
  end

  it "rejects a validators value that is not a mapping" do
    expect(parse([])).to eq(file: [], row: [], rows: [], verify: [])
    expect(errors).to eq([ "validators must be a mapping" ])
  end

  it "requires exactly one of type and class" do
    parse({ "row" => [ {}, { "type" => "model", "class" => "X" } ] })

    expect(errors).to eq([
      "validators.row[0] needs exactly one of type, class",
      "validators.row[1] needs exactly one of type, class"
    ])
  end

  it "rejects a null class" do
    parse({ "row" => [ { "class" => nil } ] })

    expect(errors).to eq([ "validators.row[0].class must be a class name" ])
  end

  it "only accepts built-in types of the same stage" do
    parse({ "row" => [ { "type" => "unique_in_file" } ], "file" => [ { "type" => "model" } ] })

    expect(errors).to eq([
      "validators.file[0].type is not available for file validators",
      "validators.row[0].type must be one of model"
    ])
  end

  it "checks unique_in_file options" do
    parse({ "rows" => [ { "type" => "unique_in_file", "keys" => [ "phone" ], "strict" => true, "case_sensitive" => "no" } ] })

    expect(errors).to contain_exactly(
      "validators.rows[0] has unknown keys: strict",
      "validators.rows[0].keys references unknown columns: phone",
      "validators.rows[0].case_sensitive must be true or false"
    )
  end

  it "requires unique_in_file keys" do
    parse({ "rows" => [ { "type" => "unique_in_file" } ] })

    expect(errors).to eq([ "validators.rows[0].keys must be a non-empty list of names" ])
  end
end
