RSpec.describe ApplicationError do
  it "uses the message and defaults derived from the class" do
    error = described_class.new("boom")

    expect([ error.message, error.error_message, error.code, error.status, error.details ])
      .to eq([ "boom", "boom", :application_error, :internal_server_error, nil ])
  end

  it "falls back to the class name as message while error_message stays nil" do
    error = described_class.new

    expect([ error.message, error.error_message, error.origin_error ]).to eq([ "ApplicationError", nil, nil ])
  end

  it "accepts code, status and details overrides" do
    error = described_class.new("nope", code: :custom, status: :conflict, details: { id: 1 })

    expect([ error.code, error.status, error.details ]).to eq([ :custom, :conflict, { id: 1 } ])
  end

  it "is raisable with keyword arguments" do
    expect { raise ForbiddenError.new("no access", details: { role: "guest" }) }
      .to raise_error(ForbiddenError, "no access")
  end

  it "derives the code from the class name without its namespace" do
    stub_const("Billing::PaymentDeclinedError", Class.new(described_class))

    expect(Billing::PaymentDeclinedError.new.code).to eq(:payment_declined_error)
  end

  describe "origin_error" do
    let(:origin) { ArgumentError.new("invalid date") }

    let(:date_error_class) do
      stub_const("DateError", Class.new(described_class) do
        private

        def format_origin_message(error)
          "Bad input: #{error.message}"
        end

        def format_origin_details(error)
          { reason: error.class.name }
        end
      end)
    end

    it "reuses the origin message when no message is given" do
      error = described_class.new(origin_error: origin)

      expect([ error.message, error.error_message, error.origin_error ]).to eq([ "invalid date", "invalid date", origin ])
    end

    it "prefers an explicit message over the origin message" do
      expect(described_class.new("Internal server error", origin_error: origin).message).to eq("Internal server error")
    end

    it "lets subclasses format the origin message and details" do
      error = date_error_class.new(origin_error: origin)

      expect([ error.message, error.details, error.code ]).to eq([ "Bad input: invalid date", { reason: "ArgumentError" }, :date_error ])
    end
  end

  describe "details from the origin error's record" do
    it "uses per-attribute errors of an invalid record" do
      error = described_class.new(origin_error: ActiveRecord::RecordInvalid.new(ValidatedRecord.invalid))

      expect(error.details).to eq(name: [ "can't be blank" ])
    end

    it "works for any library error that exposes a record" do
      library_error = Struct.new(:record, :message).new(ValidatedRecord.invalid, "rejected")

      expect(described_class.new(origin_error: library_error).details).to eq(name: [ "can't be blank" ])
    end

    it "is nil when the record has no errors" do
      error = described_class.new(origin_error: ActiveRecord::RecordInvalid.new(ValidatedRecord.valid))

      expect(error.details).to be_nil
    end

    it "is nil when the record does not respond to errors" do
      error = described_class.new(origin_error: ActiveRecord::StaleObjectError.new(Object.new, "update"))

      expect(error.details).to be_nil
    end

    it "is overridden by explicit details" do
      error = described_class.new(
        origin_error: ActiveRecord::RecordInvalid.new(ValidatedRecord.invalid),
        details: { custom: true }
      )

      expect(error.details).to eq(custom: true)
    end
  end

  describe "subclass defaults" do
    {
      ClientError => [ :client_error, :bad_request ],
      ForbiddenError => [ :forbidden_error, :forbidden ],
      UnexpectedError => [ :unexpected_error, :internal_server_error ]
    }.each do |klass, (code, status)|
      it "#{klass} => #{code} / #{status}" do
        error = klass.new

        expect([ error.code, error.status ]).to eq([ code, status ])
      end
    end
  end
end
