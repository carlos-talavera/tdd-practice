# frozen_string_literal: true

require "zlib"

module KVDatabase
  module Serializer
    DATA_TYPE_INTEGER = {
      Integer: 1,
      Float:  2,
      String: 3
    }.freeze

    DATA_TYPE_SYMBOL = {
      DATA_TYPE_INTEGER[:Integer] => :Integer,
      DATA_TYPE_INTEGER[:Float] => :Float,
      DATA_TYPE_INTEGER[:String] => :String
    }.freeze

    DATA_TYPE_FORMAT = {
      DATA_TYPE_INTEGER[:Integer] => "q<",
      DATA_TYPE_INTEGER[:Float] => "E"
    }.freeze

    CRC32_SIZE = 4
    CRC32_FORMAT = "L<"

    HEADER_SIZE = 14
    HEADER_FORMAT = "L<L<L<CC"

    def self.serialize(key:, value:, epoch: Time.now.to_i)
      key_type = type(key)
      value_type = type(value)

      key_size = size(data: key, type: key_type)
      value_size = size(data: value, type: value_type)

      size = CRC32_SIZE + HEADER_SIZE + key_size + value_size

      key_bytes = pack(data: key, type: key_type).force_encoding(Encoding::ASCII_8BIT)
      value_bytes = pack(data: value, type: value_type).force_encoding(Encoding::ASCII_8BIT)

      header = serialize_header(epoch: epoch, key_size: key_size, value_size: value_size, key_type: key_type, value_type: value_type)
      data = key_bytes + value_bytes

      crc32_bytes = [crc32(header + data)].pack(CRC32_FORMAT)

      return [size, crc32_bytes + header + data]
    end

    def self.serialize_header(epoch: Time.now.to_i, key_size:, value_size:, key_type:, value_type:)
      return [epoch, key_size, value_size, DATA_TYPE_INTEGER[key_type], DATA_TYPE_INTEGER[value_type]].pack(HEADER_FORMAT)
    end

    def self.deserialize(data)
      return 0, '', '' unless data.is_a?(String) && is_crc32_valid(deserialize_crc32(data[..CRC32_SIZE - 1]), data[CRC32_SIZE..])

      raw_data = data.dup.force_encoding(Encoding::ASCII_8BIT)

      epoch, key_size, _, key_type, value_type = deserialize_header(raw_data[CRC32_SIZE..CRC32_SIZE + HEADER_SIZE - 1])

      key_bytes = raw_data[CRC32_SIZE + HEADER_SIZE..CRC32_SIZE + HEADER_SIZE + key_size - 1]
      value_bytes = raw_data[CRC32_SIZE + HEADER_SIZE + key_size..]

      key = unpack(data: key_bytes.force_encoding(Encoding::UTF_8), type: key_type)
      value = unpack(data: value_bytes.force_encoding(Encoding::UTF_8), type: value_type)

      return [epoch, key, value]
    end

    def self.deserialize_header(header_data)
      header = header_data.unpack(HEADER_FORMAT)

      return [header[0], header[1], header[2], DATA_TYPE_SYMBOL[header[3]], DATA_TYPE_SYMBOL[header[4]]]
    end

    def self.deserialize_crc32(checksum_bytes)
      return checksum_bytes.unpack1(CRC32_FORMAT)
    end

    def self.pack(data:, type:)
      case type
      when :Integer, :Float
        return [data].pack(format(type))
      when :String
        return data.encode(Encoding::UTF_8)
      else
        raise StandardError, "Invalid type"
      end
    end

    def self.unpack(data:, type:)
      case type
      when :Integer, :Float
        return data.unpack1(format(type))
      when :String
        return data
      else
        raise StandardError, "Invalid type"
      end
    end

    def self.crc32(data)
      return Zlib.crc32(data)
    end

    def self.is_crc32_valid(checksum, data_bytes)
      return checksum == crc32(data_bytes)
    end

    private

    def self.size(data:, type:)
      return pack(data: data, type: type).bytes.length
    end

    def self.format(type)
      return DATA_TYPE_FORMAT[DATA_TYPE_INTEGER[type]]
    end

    def self.type(data)
      return data.class.to_s.to_sym
    end
  end
end