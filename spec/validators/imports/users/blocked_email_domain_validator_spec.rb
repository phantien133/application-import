RSpec.describe Imports::Users::BlockedEmailDomainValidator do
  subject(:validator) { described_class.new(definition, options) }

  let(:definition) { ApplicationImport.definition(:users) }
  let(:options) { { blocked_domains: [ "Mailinator.com", " tempmail.com " ] } }
  let(:result) { ApplicationImport::Result.new }

  def row(email)
    ApplicationImport::Row.new(line: 2, attributes: { email: }, raw: [ email ])
  end

  describe "#initialize" do
    it "needs blocked_domains" do
      [ {}, { blocked_domains: [] }, { blocked_domains: [ " " ] } ].each do |invalid|
        expect { described_class.new(definition, invalid) }.to raise_error(ApplicationImport::Errors::ConfigError, /blocked_domains/)
      end
    end
  end

  describe "#call" do
    it "adds blocked_domain for a blocked domain or one of its subdomains, whatever the case" do
      %w[ ann@mailinator.com ann@MAILINATOR.COM ann@eu.mailinator.com ann@tempmail.com ].each do |email|
        checked = row(email).tap { |subject| validator.call(subject, result) }

        expect(checked.errors.map { |error| error.to_h.slice(:column, :code) }).to eq([ { column: "email", code: :blocked_domain } ])
      end
    end

    it "names the domain in the message and details" do
      checked = row("ann@mailinator.com").tap { |subject| validator.call(subject, result) }

      expect(checked.errors.first).to have_attributes(message: "Email domain mailinator.com is not allowed",
        details: { domain: "mailinator.com" })
    end

    it "accepts other domains, including ones that only end with a blocked name" do
      %w[ ann@example.com ann@notmailinator.com ann@mailinator.com.vn ].each do |email|
        expect(row(email).tap { |subject| validator.call(subject, result) }.errors).to be_empty
      end
    end

    it "leaves rows without an email or a domain to the other rules" do
      [ nil, "", "no-at-sign" ].each do |email|
        expect(row(email).tap { |subject| validator.call(subject, result) }.errors).to be_empty
      end
    end

    it "does not add errors to the result itself (the runner records the row's errors)" do
      validator.call(row("ann@mailinator.com"), result)

      expect(result.errors).to be_empty
    end
  end
end
