# frozen_string_literal: true

RSpec.describe KVDatabase::DiskStore do
  describe "#put" do
    let(:test_db_file) { "test_db_file.db" }
    let(:subject) { described_class.new(test_db_file) }

    after do
      File.delete(test_db_file)
    end

    it 'puts a kv pair on the disk' do
      expect(subject.put(key: Faker::Lorem.word, value: Faker::Lorem.sentence)).to be_nil
      expect(subject.put(key: "café", value: Faker::Lorem.sentence(word_count: 10))).to be_nil
      expect(subject.put(key: "élite", value: Faker::Lorem.sentence(word_count: 100))).to be_nil
      expect(subject.put(key: Faker::Lorem.word, value: Faker::Lorem.sentence(word_count: 1000))).to be_nil
      expect(subject.put(key: rand(20..128), value: Faker::Lorem.sentence(word_count: 10_000))).to be_nil
      expect(subject.put(key: rand(5.3..40.2345), value: rand(1..10_000))).to be_nil
      expect(subject.put(key: rand(1..102), value: rand(10.2..100.234))).to be_nil
    end
  end

  describe "#get" do
    let(:test_db_fixture_file) { 'spec/fixtures/1747099356_kv_database.db' }
    let(:subject) { described_class.new(test_db_fixture_file) }

    it "gets the values from the keys" do
      expect(subject.get("café")).to eq("Super long expression that is not that long")
      expect(subject.get("élite")).to eq("Some other random expression to say stuff")
      expect(subject.get(1)).to eq(18)
      expect(subject.get("ipsum")).to eq(7.23)
    end

    it "returns empty string when key doesn't exist" do
      expect(subject.get("nonexistent key")).to eq('')
      expect(subject.get(48)).to eq('')
      expect(subject.get(2.90)).to eq('')
      expect(subject.get("nonexistent key 2")).to eq('')
    end
  end
end