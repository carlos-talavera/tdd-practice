# frozen_string_literal: true

RSpec.describe KVDatabase::Serializer do
  let(:header_size) { 14 }

  describe "#serialize" do
    let(:key) { "café" }
    let(:value) { Faker::Lorem.sentence(word_count: 5_000) }

    it "serializes" do
      crc_size = 4
      crc_and_header_size = crc_size + header_size

      size, data = KVDatabase::Serializer.serialize(key: key, value: value)

      key_size = KVDatabase::Serializer.size(data: key, type: :String)
      value_size = KVDatabase::Serializer.size(data: value, type: :String)
      expected_size = crc_and_header_size + key_size + value_size

      expect(size).to eq(expected_size)
      expect(data).not_to be_empty
    end
  end

  it "serializes the header" do
    header = KVDatabase::Serializer.serialize_header(epoch: 1_747_005_652, key_size: 10, value_size: 100, key_type: :Integer, value_type: :Float)

    expect(header.length).to eq(header_size)
    expect(header).not_to be_empty
  end

  describe "#deserializes" do
    context "when serialized data is valid" do
      let(:serialized_data_1) { OpenStruct.new(
        raw: "\x1E+`K\xD20!h\x05\x00\x00\x00\b\x00\x00\x00\x03\x02caf\xC3\xA9\xAEG\xE1z\x14\xAE\xF3?",
        epoch: 1_747_005_650,
        key: "café",
        value: 1.23
      )}
      let(:serialized_data_2) { OpenStruct.new(
        raw: "\xC8M\xD9M\xD30!h\x06\x00\x00\x00\x11\x00\x00\x00\x03\x03\xC3\xA9liteRandom expression",
        epoch: 1_747_005_651,
        key: "élite",
        value: "Random expression"
      )}
      let(:serialized_data_3) { OpenStruct.new(
        raw: "\x8D\xBB\xA9\x93\xD40!h\b\x00\x00\x00\b\x00\x00\x00\x01\x01\x18\x00\x00\x00\x00\x00\x00\x00\n\x00\x00\x00\x00\x00\x00\x00",
        epoch: 1_747_005_652,
        key: 24,
        value: 10
      )}

      it "deserializes" do
        epoch, key, value = KVDatabase::Serializer.deserialize(serialized_data_1.raw)

        expect(epoch).to eq(serialized_data_1.epoch)
        expect(key).to eq(serialized_data_1.key)
        expect(value).to eq(serialized_data_1.value)
      end

      it "deserializes" do
        epoch, key, value = KVDatabase::Serializer.deserialize(serialized_data_2.raw)

        expect(epoch).to eq(serialized_data_2.epoch)
        expect(key).to eq(serialized_data_2.key)
        expect(value).to eq(serialized_data_2.value)
      end

      it "deserializes" do
        epoch, key, value = KVDatabase::Serializer.deserialize(serialized_data_3.raw)

        expect(epoch).to eq(serialized_data_3.epoch)
        expect(key).to eq(serialized_data_3.key)
        expect(value).to eq(serialized_data_3.value)
      end
    end

    context "when binary string is empty" do
      it "returns expected values for empty binary string" do
        epoch, key, value = KVDatabase::Serializer.deserialize("")

        expect(epoch).to eq(0)
        expect(key).to eq('')
        expect(value).to eq('')
      end
    end

    context "when binary string is not a string" do
      it "returns expected values for non-string input" do
        epoch, key, value = KVDatabase::Serializer.deserialize(nil)

        expect(epoch).to eq(0)
        expect(key).to eq('')
        expect(value).to eq('')
      end
    end

    context "when checksum is invalid" do
      it "returns expected values for invalid CRC-32-compliant checksum" do
        epoch, key, value = KVDatabase::Serializer.deserialize("\x2E+`K\xD20!h\x05\x00\x00\x00\b\x00\x00\x00\x03\x02caf\xC3\xA9\xAEG\xE1z\x14\xAE\xF3?")

        expect(epoch).to eq(0)
        expect(key).to eq('')
        expect(value).to eq('')
      end
    end
  end

  it "packs integers" do
    expected = "\x14\x00\x00\x00\x00\x00\x00\x00"
    expect(KVDatabase::Serializer.pack(data: 20, type: :Integer)).to eq(expected)
  end

  it "packs floats" do
    expected = "\x8f\xc2\xf5\x28\x5c\x8f\x2c\x40".b
    expect(KVDatabase::Serializer.pack(data: 14.28, type: :Float)).to eq(expected)
  end

  it "packs strings" do
    expected = "\x63\x61\x66\xc3\xa9"
    expect(KVDatabase::Serializer.pack(data: "café", type: :String)).to eq(expected)
  end

  it "throws an error when packing data of an invalid type" do
    expect{KVDatabase::Serializer.pack(data: :symbol, type: :Symbol)}.to raise_error(StandardError, "Invalid type")
  end

  it "unpacks integers" do
    expected = 20
    expect(KVDatabase::Serializer.unpack(data: "\x14\x00\x00\x00\x00\x00\x00\x00", type: :Integer)).to eq(expected)
  end

  it "unpacks floats" do
    expected = 14.28
    expect(KVDatabase::Serializer.unpack(data: "\x8f\xc2\xf5\x28\x5c\x8f\x2c\x40", type: :Float)).to eq(expected)
  end

  it "unpacks strings" do
    expected = "café"
    expect(KVDatabase::Serializer.unpack(data: "\x63\x61\x66\xc3\xa9", type: :String)).to eq(expected)
  end

  it "throws an error when unpacking data of an invalid type" do
    expect{KVDatabase::Serializer.unpack(data: :symbol, type: :Symbol)}.to raise_error(StandardError, "Invalid type")
  end

  it "creates a CRC-32-compliant checksum" do
    expected = 0xEBE6C6E6
    expect(KVDatabase::Serializer.crc32("Hello, world!")).to eq(expected)
  end
end