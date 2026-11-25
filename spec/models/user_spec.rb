RSpec.describe User do
  subject(:user) { build(:user) }

  describe "database" do
    it { is_expected.to have_db_column(:email).of_type(:string).with_options(null: false) }
    it { is_expected.to have_db_column(:name).of_type(:string).with_options(null: false) }
    it { is_expected.to have_db_column(:balance).of_type(:decimal).with_options(precision: 12, scale: 2, null: false, default: 0.0) }
    it { is_expected.to have_db_column(:active).of_type(:boolean).with_options(null: false, default: true) }
    it { is_expected.to have_db_column(:role).of_type(:string).with_options(null: false, default: "member") }
    it { is_expected.to have_db_index(:email).unique }
    it { is_expected.to have_db_index(:created_by_id) }
  end

  describe "normalizations" do
    it { is_expected.to normalize(:email).from("  John.Doe@Example.COM ").to("john.doe@example.com") }
    it { is_expected.to normalize(:role).from(" Admin ").to("admin") }
  end

  describe "validations" do
    describe "email" do
      it { is_expected.to validate_presence_of(:email) }
      it { is_expected.to validate_length_of(:email).is_at_most(255) }
      it { is_expected.to validate_uniqueness_of(:email).case_insensitive }
      it { is_expected.to allow_value("john.doe+tag@example.co.uk").for(:email) }
      it { is_expected.not_to allow_values("plain", "user@", "@example.com", "a b@example.com").for(:email) }
    end

    describe "name" do
      it { is_expected.to validate_presence_of(:name) }
      it { is_expected.to validate_length_of(:name).is_at_least(2).is_at_most(100) }
    end

    describe "birthday" do
      it { is_expected.to allow_values(nil, Date.current, 150.years.ago.to_date).for(:birthday) }
      it { is_expected.not_to allow_values(Date.current + 1, 150.years.ago.to_date - 1).for(:birthday) }
    end

    describe "balance" do
      it { is_expected.to validate_numericality_of(:balance).is_greater_than_or_equal_to(0) }
    end

    describe "active" do
      it { is_expected.to allow_values(true, false).for(:active) }
      it { is_expected.not_to allow_value(nil).for(:active) }
    end

    describe "role" do
      it { is_expected.to validate_inclusion_of(:role).in_array(described_class::ROLES) }
    end

    describe "phone" do
      it { is_expected.to validate_length_of(:phone).is_at_most(30).allow_blank }
    end

    describe "nickname" do
      it { is_expected.to validate_length_of(:nickname).is_at_most(50).allow_blank }
    end
  end
end
