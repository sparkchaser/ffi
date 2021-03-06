#
# Copyright (C) 2008-2010 Wayne Meissner
# Copyright (C) 2008, 2009 Andrea Fazzi
# Copyright (C) 2008, 2009 Luc Heinrich
#
# This file is part of ruby-ffi.
#
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# * Redistributions of source code must retain the above copyright notice, this
#   list of conditions and the following disclaimer.
# * Redistributions in binary form must reproduce the above copyright notice
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
# * Neither the name of the Ruby FFI project nor the names of its contributors
#   may be used to endorse or promote products derived from this software
#   without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#

require 'ffi/platform'
require 'ffi/struct_layout_builder'
require 'json'

module FFI

  class StructLayout

    # @return [Array<Array(Symbol, Numeric)>
    # Get an array of tuples (field name, offset of the field).
    def offsets
      members.map { |m| [ m, self[m].offset ] }
    end

    # @return [Numeric]
    # Get the offset of a field.
    def offset_of(field_name)
      self[field_name].offset
    end

    # An enum {Field} in a {StructLayout}.
    class Enum < Field

      # @param [AbstractMemory] ptr pointer on a {Struct}
      # @return [Object]
      # Get an object of type {#type} from memory pointed by +ptr+.
      def get(ptr)
        type.find(ptr.get_int(offset))
      end

      # @param [AbstractMemory] ptr pointer on a {Struct}
      # @param  value
      # @return [nil]
      # Set +value+ into memory pointed by +ptr+.
      def put(ptr, value)
        ptr.put_int(offset, type.find(value))
      end

    end

    class InnerStruct < Field
      def get(ptr)
        type.struct_class.new(ptr.slice(self.offset, self.size))
      end

     def put(ptr, value)
       raise TypeError, "wrong value type (expected #{type.struct_class})" unless value.is_a?(type.struct_class)
       ptr.slice(self.offset, self.size).__copy_from__(value.pointer, self.size)
     end
    end

    class Mapped < Field
      def initialize(name, offset, type, orig_field)
        super(name, offset, type)
        @orig_field = orig_field
      end

      def get(ptr)
        type.from_native(@orig_field.get(ptr), nil)
      end

      def put(ptr, value)
        @orig_field.put(ptr, type.to_native(value, nil))
      end
    end
  end

  
  class Struct

    # Get struct size
    # @return [Numeric]
    def size
      self.class.size
    end

    # @return [Fixnum] Struct alignment
    def alignment
      self.class.alignment
    end
    alias_method :align, :alignment

    # (see FFI::StructLayout#offset_of)
    def offset_of(name)
      self.class.offset_of(name)
    end

    # (see FFI::StructLayout#members)
    def members
      self.class.members
    end

    # @return [Array]
    # Get array of values from Struct fields.
    def values
      members.map { |m| self[m] }
    end

    # (see FFI::StructLayout#offsets)
    def offsets
      self.class.offsets
    end

    # Clear the struct content.
    # @return [self]
    def clear
      pointer.clear
      self
    end

    # Get {Pointer} to struct content.
    # @return [AbstractMemory]
    def to_ptr
      pointer
    end

    # Recursively dump this structure's data as a Hash.
    # @return [Hash] Hash containing member/data pairs for every member in the struct
    #
    # @example
    #   z = Rect.new
    #   z[:x] = 1
    #   z[:y] = 2
    #   z[:w] = 3
    #   z[:h] = 4
    #   z.to_h => {:h=>4, :w=>3, :x=>1, :y=>2}
    def to_h
      m_list = {}
      members.collect do |m|
        if self[m].is_a?(FFI::Struct)
          m_list[m] = self[m].to_h
        else
          m_list[m] = self[m]
        end
      end
      return m_list
    end

    # Recursively dump this structure's data as an Array.
    # The array contains only the data, not the member names.
    # @return [Array] array of data
    #
    # @note the order of data in the array always matches the
    #   order of members given in #layout. 
    #
    # @example
    #   z = Rect.new
    #   z[:x] = 1
    #   z[:y] = 2
    #   z[:w] = 3
    #   z[:h] = 4
    #   z.to_a => [1,2,3,4]
    def to_a
      members.collect do |m|
          if self[m].is_a?(FFI::Struct)
              self[m].to_a
          else
              self[m]
          end
      end
    end

    # Dump this structure's data as a raw bytestring.
    # @return [String] raw byte sequence
    def to_bytes
      return self.pointer.get_bytes(0, self.size)
    end

    # Serialize data to JSON format
    def to_json
      JSON.generate(to_h)
    end

    # Serialize data for use with the Ruby standard 'Marshal' library.
    # This function will be invoked when 'Marshal.dump' is called.
    def marshal_dump
      to_h
    end

    # De-serialize data generated by the standard 'Marshal.dump' method.
    # This function will be invoked when 'Marshal.load' is called.
    def marshal_load data
      initialize
      init_from_hash data
    end

    # Load data from a variety of different formats.
    # Currently supports Array, Hash, Bytestring, and JSON.
    def load(data)
      case data
      when Hash
        init_from_hash data
      when ::Array
        init_from_array data
      when String
        if data.bytesize == size
          init_from_bytes data
        else
          begin
            init_from_json data
          rescue JSON::ParserError
            # This typically occurs because the string was not JSON at all.
            # Displaying a JSON-specific exception can be misleading, so use
            # a generic message instead.
            raise TypeError, "cannot initialize #{self.class} with the given #{data.class}"
          end
        end
      else
        raise TypeError, "cannot initialize #{self.class} with type #{data.class}"
      end
    end

    # Get struct size
    # @return [Numeric]
    def self.size
      defined?(@layout) ? @layout.size : defined?(@size) ? @size : 0
    end

    # set struct size
    # @param [Numeric] size
    # @return [size]
    def self.size=(size)
      raise ArgumentError, "Size already set" if defined?(@size) || defined?(@layout)
      @size = size
    end

    # @return (see Struct#alignment)
    def self.alignment
      @layout.alignment
    end

    # (see FFI::Type#members)
    def self.members
      @layout.members
    end

    # (see FFI::StructLayout#offsets)
    def self.offsets
      @layout.offsets
    end

    # (see FFI::StructLayout#offset_of)
    def self.offset_of(name)
      @layout.offset_of(name)
    end

    def self.in
      ptr(:in)
    end

    def self.out
      ptr(:out)
    end

    def self.ptr(flags = :inout)
      @ref_data_type ||= Type::Mapped.new(StructByReference.new(self))
    end

    def self.val
      @val_data_type ||= StructByValue.new(self)
    end

    def self.by_value
      self.val
    end

    def self.by_ref(flags = :inout)
      self.ptr(flags)
    end

    class ManagedStructConverter < StructByReference

      # @param [Struct] struct_class
      def initialize(struct_class)
        super(struct_class)

        raise NoMethodError, "release() not implemented for class #{struct_class}" unless struct_class.respond_to? :release
        @method = struct_class.method(:release)
      end

      # @param [Pointer] ptr
      # @param [nil] ctx
      # @return [Struct]
      def from_native(ptr, ctx)
        struct_class.new(AutoPointer.new(ptr, @method))
      end
    end

    def self.auto_ptr
      @managed_type ||= Type::Mapped.new(ManagedStructConverter.new(self))
    end

    protected

    # Initialize the contents of this structure using data from a hash.
    # @param val [Hash] hash containing field symbols and associated data
    def init_from_hash(val)
      clear
      val.each do |sym, value|
        raise NoMethodError unless self.members.member?(sym)
        if self[sym].is_a?(FFI::Struct)
          self[sym] = self[sym].class.new
          self[sym].init_from_hash(value)
        else
          self[sym] = value
        end
      end
    end

    # Initialize the contents of this structure using elements from an array.
    # Array data must be in the same order as was used with #layout.
    # @param ary [Array] array of structure member data
    def init_from_array(ary)
      unless ary.length == members.length
        raise IndexError, "expected #{members.length} items, got #{ary.length}"
      end
      clear
      members.each_with_index do |member, i|
        if self[member].is_a?(FFI::Struct)
          self[member] = self[member].class.new
          self[member].init_from_array(ary[i])
        else
          self[member] = ary[i]
        end
      end
    end

    # Initialize the contents of this structure using a bytestring.
    # @param data [String] byte sequence encoded as a String
    def init_from_bytes(data)
      unless data.bytesize == size
        raise ArgumentError, "string of length #{data.bytesize} cannot initialize a structure with size #{size}"
      end
      clear
      self.pointer.put_bytes(0, data)
    end

    # De-serialize data from a JSON record
    def init_from_json(data)
      h = JSON.parse(data, opts={:symbolize_names => true})
      init_from_hash h
    end


    class << self
      public

      # @return [StructLayout]
      # @overload layout
      #  @return [StructLayout]
      #  Get struct layout.
      # @overload layout(*spec)
      #  @param [Array<Symbol, Integer>,Array(Hash)] spec
      #  @return [StructLayout]
      #  Create struct layout from +spec+.
      #  @example Creating a layout from an array +spec+
      #    class MyStruct < Struct
      #      layout :field1, :int,
      #             :field2, :pointer,
      #             :field3, :string
      #    end
      #  @example Creating a layout from an array +spec+ with offset
      #    class MyStructWithOffset < Struct
      #      layout :field1, :int,
      #             :field2, :pointer, 6,  # set offset to 6 for this field
      #             :field3, :string
      #    end
      #  @example Creating a layout from a hash +spec+ (Ruby 1.9 only)
      #    class MyStructFromHash < Struct
      #      layout :field1 => :int,
      #             :field2 => :pointer,
      #             :field3 => :string
      #    end
      #  @example Creating a layout with pointers to functions
      #    class MyFunctionTable < Struct
      #      layout :function1, callback([:int, :int], :int),
      #             :function2, callback([:pointer], :void),
      #             :field3, :string
      #    end
      #  @note Creating a layout from a hash +spec+ is supported only for Ruby 1.9.
      def layout(*spec)
        #raise RuntimeError, "struct layout already defined for #{self.inspect}" if defined?(@layout)
        return @layout if spec.size == 0

        builder = StructLayoutBuilder.new
        builder.union = self < Union
        builder.packed = @packed if defined?(@packed)
        builder.alignment = @min_alignment if defined?(@min_alignment)

        if spec[0].kind_of?(Hash)
          hash_layout(builder, spec)
        else
          array_layout(builder, spec)
        end
        builder.size = @size if defined?(@size) && @size > builder.size
        cspec = builder.build
        @layout = cspec unless self == Struct
        @size = cspec.size
        return cspec
      end


      protected

      def callback(params, ret)
        mod = enclosing_module
        FFI::CallbackInfo.new(find_type(ret, mod), params.map { |e| find_type(e, mod) })
      end

      def packed(packed = 1)
        @packed = packed
      end
      alias :pack :packed
      
      def aligned(alignment = 1)
        @min_alignment = alignment
      end
      alias :align :aligned

      def enclosing_module
        begin
          mod = self.name.split("::")[0..-2].inject(Object) { |obj, c| obj.const_get(c) }
          (mod < FFI::Library || mod < FFI::Struct || mod.respond_to?(:find_type)) ? mod : nil
        rescue Exception
          nil
        end
      end


      def find_field_type(type, mod = enclosing_module)
        if type.kind_of?(Class) && type < Struct
          FFI::Type::Struct.new(type)

        elsif type.kind_of?(Class) && type < FFI::StructLayout::Field
          type

        elsif type.kind_of?(::Array)
          FFI::Type::Array.new(find_field_type(type[0]), type[1])

        else
          find_type(type, mod)
        end
      end

      def find_type(type, mod = enclosing_module)
        if mod
          mod.find_type(type)
        end || FFI.find_type(type)
      end

      private

      # @param [StructLayoutBuilder] builder
      # @param [Hash] spec
      # @return [builder]
      # @raise if Ruby 1.8
      # Add hash +spec+ to +builder+.
      def hash_layout(builder, spec)
        raise "Ruby version not supported" if RUBY_VERSION =~ /1\.8\.*/
        spec[0].each do |name, type|
          builder.add name, find_field_type(type), nil
        end
      end

      # @param [StructLayoutBuilder] builder
      # @param [Array<Symbol, Integer>] spec
      # @return [builder]
      # Add array +spec+ to +builder+.
      def array_layout(builder, spec)
        i = 0
        while i < spec.size
          name, type = spec[i, 2]
          i += 2

          # If the next param is a Integer, it specifies the offset
          if spec[i].kind_of?(Integer)
            offset = spec[i]
            i += 1
          else
            offset = nil
          end

          builder.add name, find_field_type(type), offset
        end
      end
    end
  end
end
