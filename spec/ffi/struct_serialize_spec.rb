#
# This file is part of ruby-ffi.
# For licensing, see LICENSE.SPECS
#

require File.expand_path(File.join(File.dirname(__FILE__), "spec_helper"))

# Define some sample structs for test purposes
class Inner < FFI::Struct
    packed
    layout  :one,   :uint8,
            :two,   :uint32,
            :three, :uint16
end
class Outer < FFI::Struct
    packed
    layout  :header, :uint8,
            :nested, Inner,
            :footer, :uint16
end
class Other < FFI::Struct
    packed
    # These types aren't fixed-width, so they can't be tested
    # against an expected byte sequence.
    layout  :f, :float,
            :z, :size_t,
            :l, :long,
            :p, :pointer,
            :u, :ushort,
            :c, :char
end

# Helper function to make some test cases simpler
class FFI::Struct
  # Initialize all fields of a structure with random values (assumes integral types)
  def randomize
    layout.members.each_with_index {|obj, idx|
      if self[obj].is_a? FFI::Struct
        self[obj].randomize
      elsif self[obj].is_a? Float
        self[obj] = rand(10_000) / 10_000.0
      elsif self[obj].is_a? FFI::Pointer
        self[obj] = FFI::Pointer.new(:uchar, rand(2 ** 32))
      else
        obj_size = layout.fields[idx].size * 8
        self[obj] = rand(2 ** (obj_size - 1))
      end
    }
    values
  end
end



describe FFI::Struct, ".to_bytes" do
  it "returns a String of the proper length" do
    x = Inner.new
    bytes = x.to_bytes
    expect(bytes).to be_a(String)
    expect(bytes.bytesize).to eql(x.size)
  end

  it "dumps fields in the correct order" do
    class Simple < FFI::Struct
      packed
      layout  :one,   :uint8,
              :two,   :uint8,
              :three, :uint8
    end
    x = Simple.new
    x[:one] = 1
    x[:two] = 2
    x[:three] = 3
    expect(x.to_bytes).to eql("\x01\x02\x03")
  end
end


describe FFI::Struct, ".to_h" do
  before :all do
    @x = Inner.new
    @x.load [3, 2, 1]
    @h = @x.to_h
  end

  it "generates the correct number of elements" do
    expect(@h.length).to eql @x.members.length
  end

  it "generates the correct sequence of keys" do
    expect(@h.keys).to match_array @x.members
  end

  it "generates the correct values" do
    @h.each {|k,v|
      expect(v).to eql @x[k]
    }
  end

  it "recursively encodes nested structures" do
    o = Outer.new
    h = o.to_h
    expect(h[:nested]).to be_a(Hash)
  end
end


describe FFI::Struct, ".to_a" do
  before :all do
    @x = Inner.new
    @x[:one] = 1
    @x[:two] = 2
    @x[:three] = 3
    @a = @x.to_a
  end

  it "generates the correct number of elements" do
    expect(@a.length).to eql @x.members.length
  end

  it "generates the correct sequence of values" do
    expect(@a).to match_array [1, 2, 3]
  end

  it "recursively encodes nested structures" do
    o = Outer.new
    a = o.to_a
    expect(a[0]).not_to be_a(::Array)
    expect(a[1]).to     be_a(::Array)
    expect(a[2]).not_to be_a(::Array)
  end
end


describe FFI::Struct, ".load [bytestring]" do
  it "can import data from a bytestring" do
    expect {
      @x = Inner.new
      @x.load("\x01\x02\x00\x00\x00\x03\x00")
    }.not_to raise_error
    expect(@x[:one]).to eql 1
    expect(@x[:two]).to eql 2
    expect(@x[:three]).to eql 3
  end
  it "will not import data from a bytestring with the wrong length" do
    @x = Inner.new
    expect {
      # Empty
      @x.load("")
    }.to raise_error(TypeError)
    expect {
      # Too long
      @x.load("\x00" * (@x.size + 1))
    }.to raise_error(TypeError)
    expect {
      # Too short
      @x.load("\x00" * (@x.size - 1))
    }.to raise_error(TypeError)
  end
end


describe FFI::Struct, ".load [hash]" do
  before :all do
    @hash = { :one => 1, :two => 2, :three => 3 }
    @other_hash = { :f => 3.14, :z => 789, :l => 123456, :p => 0x56781234,
                    :u => 42, :c => 'm'.ord }
  end

  it "loads the correct values" do
    x = Inner.new
    x.load @hash

    expect(x[:one]).to eql 1
    expect(x[:two]).to eql 2
    expect(x[:three]).to eql 3

    y = Other.new
    y.load @other_hash

    expect(y[:f]).to be_within(0.001).of @other_hash[:f]
    expect(y[:z]).to eql @other_hash[:z]
    expect(y[:l]).to eql @other_hash[:l]
    expect(y[:p].address).to eql @other_hash[:p]
    expect(y[:u]).to eql @other_hash[:u]
    expect(y[:c]).to eql @other_hash[:c]
  end

  it "only alters the specified fields" do
    x = Inner.new
    x.load @hash.reject{|z| z == :two}

    expect(x[:one]).to eql 1
    expect(x[:two]).to eql 0
    expect(x[:three]).to eql 3
  end

  it "rejects unknown fields" do
    expect {
      h = @hash.merge({ :dummy => 0 })
      x = Inner.new
      x.load h
     }.to raise_error(NoMethodError)
  end

  it "can be used to re-constitute the original hash (simple)" do
    h1 = {:one => rand(250),
          :two => rand(250),
          :three => rand(250)
         }
    x = Inner.new
    x.load h1
    h2 = x.to_h
    expect(h2).to eql h1
  end

  it "can be used to re-constitute the original structure (simple)" do
    x = Inner.new
    x.randomize
    h = x.to_h

    y = Inner.new
    y.load h

    expect(y[:one]).to eql x[:one]
    expect(y[:two]).to eql x[:two]
    expect(y[:three]).to eql x[:three]
  end

  it "can be used to re-constitute the original hash (nested)" do
    h1 = {:header => rand(250),
          :nested => {:one => rand(250), :two => rand(250), :three => rand(250)},
          :footer => rand(250)
         }
    x = Outer.new
    x.load h1
    h2 = x.to_h
    expect(h2).to eql h1
  end

  it "can be used to re-constitute the original structure (nested)" do
    x = Outer.new
    x.randomize
    h = x.to_h

    y = Outer.new
    y.load h

    expect(y[:header]).to eql x[:header]
    expect(y[:footer]).to eql x[:footer]
    expect(y[:nested][:one]).to eql x[:nested][:one]
    expect(y[:nested][:two]).to eql x[:nested][:two]
    expect(y[:nested][:three]).to eql x[:nested][:three]
  end

  it "can be used to re-constitute the original hash (other types)" do
    x = Other.new
    x.load @other_hash
    h2 = x.to_h

    expect(h2[:f]).to be_within(0.001).of @other_hash[:f]
    expect(h2[:z]).to eql @other_hash[:z]
    expect(h2[:l]).to eql @other_hash[:l]
    expect(h2[:p].address).to eql @other_hash[:p]
    expect(h2[:u]).to eql @other_hash[:u]
    expect(h2[:c]).to eql @other_hash[:c]
  end

  it "can be used to re-constitute the original structure (other types)" do
    x = Other.new
    x.randomize
    h = x.to_h

    y = Other.new
    y.load h

    expect(y[:f]).to be_within(0.00001).of x[:f]
    expect(y[:z]).to eql x[:z]
    expect(y[:l]).to eql x[:l]
    expect(y[:p].address).to eql x[:p].address
    expect(y[:u]).to eql x[:u]
    expect(y[:c]).to eql x[:c]
  end

  it "can handle being passed an empty hash" do
    expect {
      x = Inner.new
      h = {}
      x.load h
    }.not_to raise_error
  end
end


describe FFI::Struct, ".load [array]" do
  before :all do
    @init_data = [rand(250), rand(250), rand(250)]
    @init_data_outer = [rand(250), @init_data, rand(250)]
    @init_data_other = [3.14, 789, 123456, 0x56781234, 42, 'm'.ord]
  end

  it "loads the correct values" do
    x = Inner.new
    x.load [1, 2, 3]

    expect(x[:one]).to eql 1
    expect(x[:two]).to eql 2
    expect(x[:three]).to eql 3
  end

  it "rejects arrays that are the wrong size" do
    x = Inner.new
    expect {
      # empty
      x.load []
    }.to raise_error(IndexError)
    expect {
      # too small
      x.load @init_data[0...-1]
    }.to raise_error(IndexError)
    expect {
      # too large
      x.load @init_data + [5]
    }.to raise_error(IndexError)
  end

  it "can be used to re-constitute the original array (simple)" do
    x = Inner.new
    x.load @init_data
    expect(x.to_a).to match_array @init_data
  end

  it "can be used to re-constitute the original structure (simple)" do
    x = Inner.new
    x.load @init_data

    y = Inner.new
    y.load x.to_a

    expect(y[:one]).to eql x[:one]
    expect(y[:two]).to eql x[:two]
    expect(y[:three]).to eql x[:three]
  end

  it "can be used to re-constitute the original array (nested)" do
    x = Outer.new
    x.load @init_data_outer
    expect(x.to_a).to match_array @init_data_outer
  end

  it "can be used to re-constitute the original structure (nested)" do
    x = Outer.new
    x.load @init_data_outer

    y = Outer.new
    y.load x.to_a

    expect(y[:header]).to eql x[:header]
    expect(y[:footer]).to eql x[:footer]
    expect(y[:nested][:one]).to eql x[:nested][:one]
    expect(y[:nested][:two]).to eql x[:nested][:two]
    expect(y[:nested][:three]).to eql x[:nested][:three]
  end

  it "can be used to re-constitute the original array (other types)" do
    x = Other.new
    x.load @init_data_other

    expect(x[:f]).to be_within(0.00001).of @init_data_other[0]
    expect(x[:z]).to eql @init_data_other[1]
    expect(x[:l]).to eql @init_data_other[2]
    expect(x[:p].address).to eql @init_data_other[3]
    expect(x[:u]).to eql @init_data_other[4]
    expect(x[:c]).to eql @init_data_other[5]
  end

  it "can be used to re-constitute the original structure (other types)" do
    x = Other.new
    x.randomize

    y = Other.new
    y.load x.to_a

    expect(y[:f]).to be_within(0.00001).of x[:f]
    expect(y[:z]).to eql x[:z]
    expect(y[:l]).to eql x[:l]
    expect(y[:p].address).to eql x[:p].address
    expect(y[:u]).to eql x[:u]
    expect(y[:c]).to eql x[:c]
  end
end


describe "Struct JSON support" do
  describe FFI::Struct, ".to_json" do
    it "can dump a struct object" do
      x = Inner.new
      j = x.to_json
      expect(j).to be_a(String)
    end
  end


  describe FFI::Struct, ".load [json]" do
    it "can reconstitute a structure" do
      x = Outer.new
      x.randomize
      j = x.to_json

      y = Outer.new
      y.load j

      expect(y[:header]).to eql x[:header]
      expect(y[:footer]).to eql x[:footer]
      expect(y[:nested][:one]).to eql x[:nested][:one]
      expect(y[:nested][:two]).to eql x[:nested][:two]
      expect(y[:nested][:three]).to eql x[:nested][:three]
    end
  end
end


describe "Struct Marshal support" do
  describe FFI::Struct, ".marshal_dump" do
    it "can dump a struct object" do
      x = Inner.new
      expect {
        @dump = Marshal.dump x
      }.not_to raise_error
      expect(@dump).to be_a(String)
    end
  end


  describe FFI::Struct, ".marshal_load" do
    it "can reconstitute a structure" do
      x = Inner.new
      x.randomize
      dump = Marshal.dump x

      y = Marshal.load dump

      expect(y[:one]).to eql x[:one]
      expect(y[:two]).to eql x[:two]
      expect(y[:three]).to eql x[:three]
    end
  end
end
