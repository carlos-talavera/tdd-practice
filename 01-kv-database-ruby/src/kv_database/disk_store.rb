# frozen_string_literal: true

require_relative 'serializer'

module KVDatabase
  class DiskStore
    def initialize(file_path = 'kv_database.db')
      @db_file = File.open(file_path, 'a+b')
      @write_position = 0
      @map = {}

      initialize_from_file
    end

    def get(key)
      key_struct = @map[key]

      return '' if key_struct.nil?

      @db_file.seek(key_struct[:write_position])
      _, _, value = Serializer.deserialize(@db_file.read(key_struct[:size]))

      return value
    end

    def put(key:, value:, epoch: Time.now.to_i)
      size, data = Serializer.serialize(key: key, value: value, epoch: epoch)

      persist(data)
      @map[key] = { write_position: @write_position, size: size }
      increase_write_position(size)

      return nil
    end

    private

    def persist(data)
      @db_file.write(data)
      @db_file.flush
    end

    def increase_write_position(size)
      @write_position += size
    end

    def initialize_from_file
      while (crc32_and_header = @db_file.read(Serializer::CRC32_SIZE + Serializer::HEADER_SIZE))
        header_bytes = crc32_and_header[Serializer::CRC32_SIZE..]

        _, key_size, value_size, key_type, _ = Serializer.deserialize_header(header_bytes)

        key_bytes = @db_file.read(key_size)
        value_bytes = @db_file.read(value_size)

        crc32 = Serializer.deserialize_crc32(crc32_and_header[..Serializer::CRC32_SIZE - 1])
        raise StandardError, "File corrupted" unless Serializer.is_crc32_valid(crc32, header_bytes + key_bytes + value_bytes)

        key = Serializer.unpack(data: key_bytes, type: key_type)
        encoded_key = key_type == :String ? key.force_encoding(Encoding::UTF_8) : key

        size = Serializer::CRC32_SIZE + Serializer::HEADER_SIZE + key_size + value_size
        @map[encoded_key] = { write_position: @write_position, size: size }
        increase_write_position(size)
      end
    end
  end
end