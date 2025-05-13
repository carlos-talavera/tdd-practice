# Thought process 2 (pair programming if you're reading this)

## Serializer

### Preventing name mangling

The last thing I did in the first part was to develop `serialize` and `deserialize` and implement some local constants that map data types to integers, symbols or formats. Now, I've had bad experiences with constants that are objects after building an application in JS (yeah, these maps are objects in my book, they map stuff, but they're good-ol'-fashioned objects with keys and values). Creating a build involves minifying the code, and turns out that the names of those constants can change because of [name mangling](https://en.wikipedia.org/wiki/Name_mangling). Mangling means that these constants would lose their original names and use some human-unreadable name, but the references to them would be preserved using the name I gave them. This, of course, makes the code no longer to work because I'm referencing something that doesn't exist. To me, in a development server, would work, but the production-minified code wouldn't work.

This is why I like to freeze the objects that are constant, so they cannot be mangled and they cannot be mutated, meaning that I cannot add, edit or delete values. This gives me the confidence that I won't get any unexpected behavior. In Ruby, this is as simple as just calling the `freeze` method on the object. I need to freeze all these constant objects, so I'll just apply it to all of them:

```rb
DATA_TYPE_SYMBOL = {
  Integer: :Integer,
  Float: :Float,
  String: :String
}.freeze

DATA_TYPE_INTEGER = {
  DATA_TYPE_SYMBOL[:Integer] => 1,
  DATA_TYPE_SYMBOL[:Float] =>  2,
  DATA_TYPE_SYMBOL[:String] => 3
}.freeze

DATA_TYPE_FORMAT = {
  DATA_TYPE_SYMBOL[:Integer] => "q<",
  DATA_TYPE_SYMBOL[:Float] => "E"
}.freeze
```

The tests still pass, of course. Let's remember that I did all of this so I could store the type of the key and the value as an integer.

### Creating a CRC-32-compliant checksum

Going back to what I need to store in a record:

- A CRC-32-compliant checksum
- An epoch timestamp
- The key size
- The value size
- The key type
- The value type
- Key
- Value

Now I have all I need to store everything, except the CRC-32-compliant checksum. I could focus on what I already know that I can serialize and deserialize, but if the data needs to be stored following the order above (as an array of bytes), then I think it's better to focus on creating a test for the CRC-32 checksum, find the way to make it pass and have this missing implementation. So I will create a test for it:

```rb
it "creates a CRC-32-compliant checksum" do
  expected = 123
  expect(KVDatabase::Serializer.crc32("Hello, world!")).to eq(expected)
end
```

The test will fail because `crc32` isn't implemented in the `Serializer` module. To make the test pass, I'll fake the implementation and just return what's expected.

```rb
def self.crc32(value)
  return 123
end
```

No keyword parameter because this function will only receive one. After this, the test will pass. To make the real implementation, as happened with the binary data packing and unpacking, Ruby provides a library called `Zlib` that includes a `crc32` method. Again, these functions might seem like simple wrappers, but they help me to see the path I should be following.

```rb
require "zlib" # Don't forget to import

def self.crc32(value)
  return Zlib.crc32(value)
end
```

Doing this will break the test, because the expected value is not actually the result of applying the algorithm to create the checksum (unless I was pretty lucky). There's a tool to [generate CRC-32-compliant checksums](https://crccalc.com/?crc=Hello,%20world!&method=CRC-32&datatype=ascii&outtype=hex), so I can find the expected value for a simple string in there. Ruby uses the `CRC-32/ISO-HDLC` algorithm, so that's the `result` value I'll pick.

```rb
it "creates a CRC-32-compliant checksum" do
  expected = 0xEBE6C6E6
  expect(KVDatabase::Serializer.crc32("Hello, world!")).to eq(expected)
end
```

Now the test pass. The expected value is a number expressed in hexadecimal, because that's how it's actually generated, but if I converted it to decimal, it would work as well:

```rb
it "creates a CRC-32-compliant checksum" do
  expected = 3957769958
  expect(KVDatabase::Serializer.crc32("Hello, world!")).to eq(expected)
end
```

However, I like to keep it as hexadecimal because it looks less messy. Once this test passes, I can start thinking about what's the actual goal of creating this checksum. What's its purpose? To maintain the integrity of the data by comparing if the checksum from the record is the expected checksum for that data. But how can I achieve creating a checksum that represents the record itself? I think that I can just use the data itself to generate the checksum. But if I have to use the data itself, then I would first need to know how that data would look like. So I should've started with the data instead of the checksum, but I only got to this conclusion because the test let me understood where I was going.

### Rerouting

I'll focus on creating the data of the record and then come back to the checksum. Remembering how data should be stored in a record following the Bitcask model (another shoutout to [Dinesh Gowda's article](https://dineshgowda.com/posts/build-your-own-persistent-kv-store/)):

![Bitcask model](./assets/03.svg "03 - Bitcask model")

I modified the original image because on one hand, it showed 4 bytes for key and value types, but the total of the header was 16 instead of 20, and on the other hand, if the types will be small integers (with what I have know, it's just from 1 to 3), I don't need 4 bytes, I just need 1 byte. So I need a 14-byte header, 4 bytes for the epoch timestamp, 4 bytes for the key size, 4 bytes for the value size, 1 byte for the key type and 1 byte for the value type. Now let's go bit by bit (no pun intended, because they're not actual bits).

### Thinking about the epoch timestamp

Let's create a test for the epoch timestamp:

```rb
it "creates an epoch timestamp" do
  expected = 1746984608
  expect(KVDatabase::Serializer.epoch_timestamp).to eq(expected)
end
```

It will fail because `epoch_timestamp` doesn't exist. Here I can skip the fake implementation because I know the obvious implementation, which is just using `Time.now.to_i`. `Time.now` will generate a string with date and time, but `to_i` will convert it into the milliseconds that we expect.

```rb
def self.epoch_timestamp
  return Time.now.to_i
end
```

And now the test... fails. Why? Because the time has changed. `Time.now` is dynamic, and `expected` is, of course, not dynamic. This test won't be useful then, because I would have to just fix the timestamp and it wouldn't actually tell me a thing. So I won't create this test now, but when I have a better understanding of the problem, I'll see what is needed to be tested in terms of time. The good thing is that this experiment allowed me to understand that I needed to use `Time.now.to_i` to create the timestamp.

### Rerouting one more time

I feel like I'm hitting a dead end here, what can I do next? Is it that I need to start thinking about the implementations instead of tests? No, that would defeat the purpose of TDD. If I want to go to the next part, the key size, what would I need? A function to generate the key size? What is the key size? I know the key size will be measured in bytes, but what the key will be? If the key was `"café"`, the size would be 4 because these are 4 characters? No, because "é" is more than 1 byte, so the number of bytes would be greater than the number of characters. Therefore, the size is the length of the array of bytes that represents the key. The same for the value size. So I think I can start by creating a test that generates the size from a given key.

### Understanding the key size

```rb
it "generates the size of a key" do
  expected = 5
  expect(KVDatabase::Serializer.key_size("café")).to eq(expected)
end
```

This will fail because `key_size` doesn't exist. The expected value comes from the previous test for serializing strings (5 "positions" in the string, so 5 bytes for `"café"`). I could do a fake implementation, but one thing I know is that if I encode `"café"` in UTF-8, and get an array of bytes, I can access a `.bytes.length` property. But that would only work for strings, but I already have a `serialize` method that handles different types. But it needs a type, so I would need to do this:

```rb
def self.key_size(key:, type:)
  return serialize(value: key, type: type).bytes.length
end
```

That seems messy because, why would `key_size` depend on `serialize`? If I want to create the whole record, the size would be calculated from the data that I want to serialize, so if anything, `serialize` would call `key_size`, not the other way around.

### Renaming `serialize` to `pack`

This makes me see a fundamental issue with `serialize`: this method should be responsible for converting the whole thing, not just one part, so right now it has a specific scope, but it should have a broader one. It only packs data in an array of bytes, but from the outside, I would assume `serialize` is the one that takes the data of the record to be stored, and creates the whole thing with the CRC, the header, the key and the value. It's not that the implementation is wrong, it's just that the name is wrong for what it does. I will comment the test and implementation for `key_size` first.

And now I will rename `serialize` to a more suitable name, `pack`, because that's literally what it does.

```rb
def self.pack(value:, type:)
  if type == :String
    return value.encode(Encoding::UTF_8)
  end

  return [value].pack(DATA_TYPE_FORMAT[type])
end
```

This will break the tests, so let's fix them:

```rb
it "packs integers" do
  expected = "\x14\x00\x00\x00\x00\x00\x00\x00"
  expect(KVDatabase::Serializer.pack(value: 20, type: :Integer)).to eq(expected)
end

it "packs floats" do
  expected = "\x8f\xc2\xf5\x28\x5c\x8f\x2c\x40".b
  expect(KVDatabase::Serializer.pack(value: 14.28, type: :Float)).to eq(expected)
end

it "packs strings" do
  expected = "\x63\x61\x66\xc3\xa9"
  expect(KVDatabase::Serializer.pack(value: "café", type: :String)).to eq(expected)
end
```

### Renaming `deserialize` to `unpack`

The same thing applies to `deserialize`, it should be a method to take the stored data, identify each part and return the value, but right now it just unpacks some value given its type.

```rb
def self.unpack(value:, type:)
  if type == :String
    return value
  end

  return value.unpack1(DATA_TYPE_FORMAT[type])
end
```

Let's fix the tests:

```rb
it "unpacks integers" do
  expected = 20
  expect(KVDatabase::Serializer.unpack(value: "\x14\x00\x00\x00\x00\x00\x00\x00", type: :Integer)).to eq(expected)
end

it "unpacks floats" do
  expected = 14.28
  expect(KVDatabase::Serializer.unpack(value: "\x8f\xc2\xf5\x28\x5c\x8f\x2c\x40", type: :Float)).to eq(expected)
end

it "unpacks strings" do
  expected = "café"
  expect(KVDatabase::Serializer.unpack(value: "\x63\x61\x66\xc3\xa9", type: :String)).to eq(expected)
end
```

### Refactoring to avoid name confusions between key and value

Now the names reflect their purposes better and the tests pass. But thinking about `key` and `value`, and that `key` would be passed as `value`, the names are a bit confusing, because of course `value` is just a general name, it could be the `key`, but I don't want that confusion, so I'll name `value` to `data`. `pack` first:

```rb
def self.pack(data:, type:)
  if type == :String
    return data.encode(Encoding::UTF_8)
  end

  return [data].pack(DATA_TYPE_FORMAT[type])
end
```

Fix the tests:

```rb
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
```

Now `unpack`:

```rb
def self.unpack(data:, type:)
  if type == :String
    return data
  end

  return data.unpack1(DATA_TYPE_FORMAT[type])
end
```

Fix the tests:

```rb
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
```

For `crc32` there's no keyword parameter, but internally it's called `value`, so to reflect better what will be used for the checksum is the whole data, let's rename it as well:

```rb
def self.crc32(data)
  return Zlib.crc32(data)
end
```

Of course the test still passes because no behavior exposed to the outside was modified.

### Handling errors when trying to pack invalid types

I want to make a pause here because after making these changes, I realized `pack` and `unpack` assume the type will be valid, which is not necessarily true. So I'll create a new test first for `pack` that checks that an error is thrown when the type is not valid.

```rb
it "throws an error when packing data of an invalid type" do
  expect{KVDatabase::Serializer.pack(data: :symbol, type: :Symbol)}.to raise_error(StandardError, "Invalid type")
end
```

Apparently I have to use `{}` instead of `()` because otherwise the code will not be "catchable".

To make the test pass, I can do an ugly (but not that much) thing:

```rb
def self.pack(data:, type:)
  if type != :String && type != :Integer && type != :Float
    raise StandardError, "Invalid type"
  end

  if type == :String
    return data.encode(Encoding::UTF_8)
  end

  return [data].pack(DATA_TYPE_FORMAT[type])
end
```

The test now will pass. This is not the best, but it's not that bad. I can use a `case` (a `switch` in Ruby syntax), but instead of hardcoding the symbols for the types, I can use my `DATA_TYPE_SYMBOL` map.

```rb
def self.pack(data:, type:)
  case type
  when DATA_TYPE_SYMBOL[:Integer], DATA_TYPE_SYMBOL[:Float]
    return [data].pack(DATA_TYPE_FORMAT[type])
  when DATA_TYPE_SYMBOL[:String]
    return data.encode(Encoding::UTF_8)
  else
    raise StandardError, "Invalid type"
  end
end
```

That way I keep my single source of truth and code easy to understand (I think). I know I don't need explicit `return` in Ruby, but I feel uncomfortable not using it, to me it's more readable to use it.

Of course, the test will still pass.

### Handling errors when trying to unpack invalid types

Now let's create the test for `unpack`:

```rb
it "throws an error when unpacking data of an invalid type" do
  expect{KVDatabase::Serializer.unpack(data: :symbol, type: :Symbol)}.to raise_error(StandardError, "Invalid type")
end
```

Of course it will fail. Now let's make a similar implementation to make it pass:

```rb
def self.unpack(data:, type:)
  case type
  when DATA_TYPE_SYMBOL[:Integer], DATA_TYPE_SYMBOL[:Float]
    return data.unpack1(DATA_TYPE_FORMAT[type])
  when DATA_TYPE_SYMBOL[:String]
    return data
  else
    raise StandardError, "Invalid type"
  end
end
```

And... the test is fine now. Okay, after addressing this missing case, let's keep going.

### Thinking about how `serialize` should actually work

Going back to `key_size`, I would still need to pass it the type, which seems like unnecessary coupling. When I feel like there's unnecessary coupling, I ask myself how this is supposed to be used and if it's worth it. If the key size will be calculated when serializing something, and that will be the only case and `key_size` is dead simple, do I really need an auxiliary function for it? I don't think so. Besides, I would also need a `value_size` if I'm going to keep `key_size`, but they do the same, and they're actually two names for the same thing: getting the size of some packed data. If my tests already check that the data is properly packed, and I'm not using my own implementation but Ruby's library for this, then a test for checking the size wouldn't really add to the level of confidence of the test suite. The current tests check that my understanding of how data is packed and unpacked is right, so I can trust in them.

So, what's next? After failed attempts to create more tests, I gained knowledge about how things should work internally, which is of course useful. I think I can now start thinking about the actual serialization process and see what I'm missing in my current implementation. How would this test look like? What information is needed for serializing in the expected format of the Bitcask model? If I was using a key-value database, to store a record I would just want to pass it a key and a value. So that's how the interface will look like: `serialize(key:, value:)`. But... what if I want a custom timestamp for some reason? I would like to have the possibility to specify it, but if it's not provided, default to `now`. Internally I can handle the checksum creation, generating the timestamp and getting the type and size of the key and the value. It should return something that allows me to test that it worked. Perhaps it could be the size of the record so I can check that it equals the size of the CRC + the header + the key + the value. And it could also return the packed key + value so I can check that they're not empty (because that wouldn't make sense for an array of bytes).

### Making the test for `serialize` pass (no, not implementing `serialize`)

I see that Ruby has a `Faker` implementation, so I will use it for generating a random key and a value with a very long sentence. Since these two fake values will be expensive to compute, I'll memoize them and put them outside the test, inside the suite (`require 'faker'` is needed in `spec/spec_helper.rb` and the gem must be added in the `Gemfile`, but I'll skip those details from now on):

```rb
RSpec.describe KVDatabase::Serializer do
  describe "#serialize" do
    let(:key) { Faker::Lorem.word }
    let(:value) { Faker::Lorem.sentence(word_count: 5_000) }
  end

  # tests
end
```

And now the test:

```rb
it "serializes" do
  crc_size = 4
  header_size = 14
  crc_and_header_size = crc_size + header_size

  size, data = KVDatabase::Serializer.serialize(key: key, value: value)

  key_size = KVDatabase::Serializer.size(data: key, type: :String)
  value_size = KVDatabase::Serializer.size(data: value, type: :String)
  expected_size = crc_and_header_size + key_size + value_size

  expect(size).to eq(expected_size)
  expect(data).not_to be_empty
end
```

It will fail, of course, because neither `size` nor `serialize` are implemented. The implementation for `size` is obvious as we've seen it before.

```rb
def self.size(data:, type:)
  return pack(data: data, type: type).bytes.length
end
```

Now things get interesting for this. How can I make the test pass? I know the size the CRC should have, and I know the size the header should have, so I can have constants for that inside `Serializer` as well:

```rb
CRC32_SIZE = 4
    
HEADER_SIZE = 14
```

And return the sum in the first position of `serialize`:

```rb
def self.serialize(key:, value:, epoch: Time.now.to_i)
  return [CRC32_SIZE + HEADER_SIZE, 0]
end
```

Now that first part is missing the size of the key and the value. So I'll compute them using `size` and add them to the sum:

```rb
def self.serialize(key:, value:, epoch: Time.now.to_i)
  key_size = size(data: key)
  value_size = size(data: value)

  return [CRC32_SIZE + HEADER_SIZE + key_size + value_size, 0]
end
```

Wait, but that won't work because `size` needs the type of `key` and `value`. How to get them? Having to pass them to `serialize` would be awful. Isn't there a nice way to do it? If the types are symbols using the actual name of the type in Ruby, can't I just get the type of `key` and `value` and convert it into a symbol? I see that since these types are `classes` in Ruby, I could do something like `key.class` and `value.class`, but that would give me the internal representation that Ruby uses, and I want them as symbols. I see I cannot get a symbol directly from there, so I need to first convert it into a string and then convert that string into a symbol, so I would have `key.class.to_s.to_sym` and `value.class.to_s.to_sym`:

```rb
def self.serialize(key:, value:, epoch: Time.now.to_i)
  key_type = key.class.to_s.to_sym
  value_type = value.class.to_s.to_sym

  key_size = size(data: key, type: key_type)
  value_size = size(data: value, type: value_type)

  return [CRC32_SIZE + HEADER_SIZE + key_size + value_size, 0]
end
```

If I run the tests now, I can see that the size test passes, but the empty one keeps failing, so it means that my approach worked to get the size and type of the key and the value. Let's focus on a little refactor here first. I'm doing the same for getting the type of the key and the value, so let's introduce a little helper for this:

```rb
def self.type(data)
  return data.class.to_s.to_sym
end
```

And now use it:

```rb
def self.serialize(key:, value:, epoch: Time.now.to_i)
  key_type = type(key)
  value_type = type(value)

  key_size = size(data: key, type: key_type)
  value_size = size(data: value, type: value_type)

  return [CRC32_SIZE + HEADER_SIZE + key_size + value_size, 0]
end
```

That's better and the test still works. Now, to make the data not be empty and make the test pass, the only thing I need to do is to create pack both `key` and `value` and return the resultant array of bytes of adding them:

```rb
def self.serialize(key:, value:, epoch: Time.now.to_i)
  key_type = type(key)
  value_type = type(value)

  key_size = size(data: key, type: key_type)
  value_size = size(data: value, type: value_type)

  key_bytes = pack(data: key, type: key_type)
  value_bytes = pack(data: value, type: value_type)

  return [CRC32_SIZE + HEADER_SIZE + key_size + value_size, key_bytes + value_bytes]
end
```

And... now the test will pass! But... is this the right implementation? It isn't, because the second value of the array should be the whole serialized data, not only key and value. It lacks the checksum and the header. But, as any respectable cliffhanger, I'll solve that in the next part.
