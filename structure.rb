class Type
  attr_accessor :bytes

  def initialize(bytes: bytes)
    self.bytes = bytes
  end
end

class SimpleType < Type

  attr_accessor :unpack_string

  def initialize bytes:, unpack_string: unpack_string
    super(bytes: bytes)
    self.unpack_string = unpack_string
  end

end

class Element

  attr_accessor :type
  attr_reader :array

  def initialize(type, array: )
    self.type = type
    self.array = array
  end

  def array=(n)
    if (n.nil?)
      @reader = self.method(:read_simple)
      @writer = self.method(:write_simple)
    else
      if n.is_a? Integer
        @array = Proc.new { n }
      else
        @array = n
      end
      @reader = self.method(:read_array)
      @writer = self.method(:write_array)
    end
  end

  def read(stream)
    @reader.call(stream)
  end

  def write(stream, value)
    @writer.call(stream, value)
  end

  def size!
    if @array.nil?
      type.bytes
    else
      type.bytes * array.call(self)
    end
  end

end

class SimpleElement < Element

  def initialize(type, array: )
    super(type, array: array)
    @bytes         = type.bytes
    @unpack_string = type.unpack_string
  end

  def read_simple(stream)
    stream.read(@bytes).unpack(@unpack_string).first
  end

  def read_array(stream)
    n = array.call(self)
    stream.read(@bytes*n).unpack(@unpack_string+n.to_s)
  end

  def write_simple(stream, *value)
    stream.write(value.pack(@unpack_string))
  end

  def write_array(stream, value)
    n = array.call(self)
    stream.write(value.pack(@unpack_string+n.to_s))
  end

end

require 'delegate'
class EnumConstant < SimpleDelegator

  def inspect
    @constant_name.inspect
  end

  def value
    @constant_value
  end

  def name
    @constant_name
  end

  def initialize(name, value)
    super(value)
    @constant_value = value
    @constant_name  = name.to_sym
  end

end



class CStruct

  module ClassMethods

    def types!
      return @types if @types
      @types = super rescue @types = {}
    end

    def type!(type)
      types!(type)
    end

    def elements!
      @elements ||= (superclass.elements!.clone rescue {})
    end

    # TODO
    #
    # If a C structure contains pointers, that is addresses pointing
    # to allocated data, the size of the C structure must only take
    # into account the size of the address.
    def size!
      @elements.values.map(&:size!).inject(0) {|total,size| total + size}
    end

    def type(nom_type, *args, bytes:, type_impl: SimpleType, element_impl: SimpleElement, **named_args)
      type = types![nom_type.to_sym] = type_impl.new(*args, bytes: bytes, **named_args)

      (class << self; self; end).instance_eval do
        # class S; type :uchar; end defines S.uchar :element_name[, array: n] ...
        define_method(nom_type.to_sym) do |raw_nom_element, array: nil|

          nom_element = raw_nom_element.to_sym
          # ... which add the element to @elements on invocation
          elements![nom_element] = element_impl.new(type, array: array)
          # ... which defines an instance method 'element_name', for S instances

          attr_writer nom_element

          # This add the possibility to use blocks as values
          define_method(nom_element) do
            v = instance_variable_get(:"@#{nom_element}")
            return v unless v.respond_to? :call
            v.call(self)
          end

        end
      end
    end

    def typedef(nom_type, nouveau_nom)
      (class << self; self; end).instance_eval do
        define_method(nouveau_nom.to_sym) do |*simple_args, **named_args|
          self.__send__(nom_type.to_sym, *simple_args, **named_args)
        end
      end
    end

    def from!(stream)
      structure = self.new
      structure.memset!(stream)
      structure
    end

    def enum(symbols)
      i = 0
      symbols.each do |s|
        case s
        when Symbol
          self.const_set(s, EnumConstant.new(s,i))
          i += 1
        when Fixnum
          i = s
        end
      end
    end

    def set!(hsh)
      s = self.new
      s.set!(hsh)
    end

  end

  extend ClassMethods

  type :ubyte, unpack_string: "C", bytes: 1
  type :sbyte,  unpack_string: "c", bytes: 1
  type :le_uhword, unpack_string: "S<", bytes: 2
  type :le_shword, unpack_string: "s<", bytes: 2
  type :be_uhword, unpack_string: "S>", bytes: 2
  type :be_shword, unpack_string: "S<", bytes: 2
  type :le_uword, unpack_string: "L<", bytes: 4
  type :le_sword, unpack_string: "l<", bytes: 4
  type :be_uword, unpack_string: "L>", bytes: 4
  type :be_sword, unpack_string: "l>", bytes: 4
  type :le_udword, unpack_string: "Q<", bytes: 8
  type :le_sdword, unpack_string: "q<", bytes: 8
  type :be_udword, unpack_string: "Q>", bytes: 8
  type :be_sdword, unpack_string: "q>", bytes: 8

  type :le_float, unpack_string: "e", bytes: 4
  type :be_float, unpack_string: "E", bytes: 4
  type :le_double, unpack_string: "g", bytes: 8
  type :be_double, unpack_string: "G", bytes: 8

  typedef :sbyte,     :int8_t
  typedef :ubyte,     :uint8_t
  typedef :ubyte,     :uchar
  typedef :le_shword, :int16_t
  typedef :le_shword, :short
  typedef :le_uhword, :uint16_t
  typedef :le_sword,  :int32_t
  typedef :le_sword,  :int
  typedef :le_uword,  :uint32_t
  typedef :le_sdword, :int64_t
  typedef :le_udword, :uint64_t
  typedef :le_float,  :float
  typedef :le_double, :double

  def initialize(fail_fast: false)
    @fail_fast = fail_fast
    @failures = {
      false => Proc.new do |field_name, exception, failed_fields|
        failed_fields << {field_name: field_name, exception: exception}
    end,
      true =>  Proc.new do |field_name, exception|
        raise e, "The following exception occured when dealing with #{field_name}"<<
                 exception.message
    end
    }
  end

  def memset!(stream)
    self.class.elements!.each do |field_name, field_object|
      self.__send__ :"#{field_name}=", field_object.read(stream)
    end
  end

  class NullStream
    def write(*args)
    end
  end
  @@null_stream = NullStream.new

  def memwrite!(stream)

    # 75% of the complexity is due to error management.

    failed_fields = []
    fail_procedure = @failures[@fail_fast]

    self.class.elements!.each do |field_name, field_object|
      begin
        current_field = field_name
        value = self.__send__(:"#{current_field}")
        field_object.write(stream, value)
      rescue => e
        fail_procedure.call(field_name, e, failed_fields)
        stream = @@null_stream
      end
    end

    if failed_fields.empty?
      return
    else
      error = "Could not write the structure after the following field : #{failed_fields.first[:field_name]}\n"<<
              "The following exceptions happened during the operation.\n"
      failed_fields.each do |problems|
        error << "#{problems[:field_name]} : #{problems[:exception].class} - #{problems[:exception].message} (#{problems[:exception].backtrace[0]})\n"
      end
      raise RuntimeError, error
    end

  end

  def set!(hsh)
    hsh.each {|field, value| self.send(:"#{field}=", value) }
    self
  end

  def size!
    self.class.size!
  end

end



class ElfHdr64 < CStruct
  EI_NIDENT = 16;
  typedef :uint16_t, :Elf64_Half;
  typedef :uint32_t, :Elf64_Word;
  typedef :uint64_t, :Elf64_Addr;
  typedef :uint64_t, :Elf64_Off;
  uchar :e_ident, array: EI_NIDENT;
  Elf64_Half :e_type;
  Elf64_Half :e_machine;
  Elf64_Word :e_version;
  Elf64_Addr :e_entry;
  Elf64_Off :e_phoff;
  Elf64_Off :e_shoff;
  Elf64_Word :e_flags;
  Elf64_Half :e_ehbits;
  Elf64_Half :e_phentbits;
  Elf64_Half :e_phnum;
  Elf64_Half :e_shentbits;
  Elf64_Half :e_shnum;
  Elf64_Half :e_shstrndx;
end

class Elf32 < CStruct
  typedef :uint16_t, :Elf_Half;
  typedef :uint32_t, :Elf_Word;
  typedef :int32_t,  :Elf_Sword;
  typedef :uint32_t, :Elf_Addr;
  typedef :uint32_t, :Elf_Off;
end

class ElfHdr32 < Elf32
  enum [
    :ET_NONE,
    :ET_REL,
    :ET_EXEC,
    :ET_DYN,
    :ET_CORE
  ]
  EI_NIDENT = 16;
  uchar :e_ident, array: EI_NIDENT;
  Elf_Half :e_type;
  Elf_Half :e_machine;
  Elf_Word :e_version;
  Elf_Addr :e_entry;
  Elf_Off :e_phoff;
  Elf_Off :e_shoff;
  Elf_Word :e_flags;
  Elf_Half :e_ehbits;
  Elf_Half :e_phentsize;
  Elf_Half :e_phnum;
  Elf_Half :e_shentsize;
  Elf_Half :e_shnum;
  Elf_Half :e_shstrndx;
end

class ElfPHdr32 < Elf32
  enum [
    :PT_NULL,
    :PT_LOAD,
    :PT_DYNAMIC,
    :PT_INTERP,
    :PT_NOTE,
    :PT_SHLIB,
    :PT_PHDR,
    :PT_TLS
  ]
  PF_X = 0x1
  PF_W = 0x2
  PF_R = 0x4
  Elf_Word :p_type;
  Elf_Off  :p_offset;
  Elf_Addr :p_vaddr;
  Elf_Addr :p_paddr;
  Elf_Word :p_filesz;
  Elf_Word :p_memsz;
  Elf_Word :p_flags;
  Elf_Word :p_align;
end



class ElfSHdr32 < Elf32
  SHT_NULL =           0
  SHT_PROGBITS =       1
  SHT_SYMTAB =         2
  SHT_STRTAB =         3
  SHT_RELA =           4
  SHT_HASH =           5
  SHT_DYNAMIC =        6
  SHT_NOTE =           7
  SHT_NOBITS =         8
  SHT_REL =            9
  SHT_SHLIB =          10
  SHT_DYNSYM =         11
  SHT_INIT_ARRAY =     14
  SHT_FINI_ARRAY =     15
  SHT_PREINIT_ARRAY =  16
  SHT_GROUP =          17
  SHT_SYMTAB_SHNDX =   18
  SHT_NUM =            19
  SHT_LOOS =           0x60000000
  SHT_GNU_ATTRIBUTES = 0x6ffffff5
  SHT_GNU_HASH =       0x6ffffff6
  SHT_GNU_LIBLIST =    0x6ffffff7
  SHT_CHECKSUM =       0x6ffffff8
  SHT_LOSUNW =         0x6ffffffa
  SHT_SUNW_move =      0x6ffffffa
  SHT_SUNW_COMDAT =    0x6ffffffb
  SHT_SUNW_syminfo =   0x6ffffffc
  SHT_GNU_verdef =     0x6ffffffd
  SHT_GNU_verneed =    0x6ffffffe
  SHT_GNU_versym =     0x6fffffff
  SHT_HISUNW =         0x6fffffff
  SHT_HIOS =           0x6fffffff
  SHT_LOPROC =         0x70000000
  SHT_HIPROC =         0x7fffffff
  SHT_LOUSER =         0x80000000
  SHT_HIUSER =         0x8fffffff

  SHF_WRITE = 1
  SHF_ALLOC = 2
  SHF_EXECINSTR = 4
  SHF_MASKPROC = 0xf0000000

  Elf_Word :sh_name;
  Elf_Word :sh_type;
  Elf_Word :sh_flags;
  Elf_Addr :sh_addr;
  Elf_Off  :sh_offset;
  Elf_Word :sh_size;
  Elf_Word :sh_link;
  Elf_Word :sh_info;
  Elf_Word :sh_addralign;
  Elf_Word :sh_entsize;
end

class Elf32_Sym < Elf32
  Elf_Word :st_name;
  Elf_Addr :st_value;
  Elf_Word :st_size;
  uchar    :st_info;
  uchar    :st_other;
  Elf_Half :st_shndx;
  def st_bind
    bind = st_info >> 4
    Elf32_Sym.binds[bind] || bind
  end
  def st_type
    type = st_info & 0xf
    Elf32_Sym.types[st_info & 0xf] || type
  end
  def self.binds
    @@binds
  end
  def self.types
    @@types
  end

  @@binds = Hash[0, :STB_LOCAL, 1, :STB_GLOBAL, 2, :STB_WEAK, 13, :STB_LOPROC, 15, :STB_HIPROC]
  @@types = Hash[0, :STT_NOTYPE, 1, :STT_OBJECT, 2, :STT_FUNC, 3, :STT_SECTION, 4, :STT_FILE, 13, :STT_LOPROC, 15, :STT_HIPROC]
end

class Elf32_Rel < Elf32
  Elf_Addr :r_offset;
  Elf_Word :r_info;
end

class Elf32_Rela < Elf32_Rel
  Elf_Sword :r_addend;
end

require 'stringio'
class SectionInformations
  INVALID = ""
  attr_accessor :name
  attr_accessor :header
  attr_accessor :data

  def initialize(name: nil, header: nil, data: nil)
    @name   = name
    @header = header
    @data   = data
  end

  def data!
    StringIO.new(data)
  end
end
class ElfReader32

  attr_reader :header
  attr_reader :program_sections
  attr_reader :sections
  attr_reader :named_sections
  attr_reader :symbols
  attr_reader :relocations

  def initialize(stream:)
    @header = ElfHdr32.from!(stream)
    @sections = []
    @program_sections = []
    stream.seek(@header.e_phoff)
    @header.e_phnum.times { @program_sections << ElfPHdr32.from!(stream) }
    stream.seek(@header.e_shoff)
    @header.e_shnum.times { @sections << ElfSHdr32.from!(stream) }
    @named_sections = {}
    strtab = @sections[@header.e_shstrndx]
    if strtab && strtab.sh_type = ElfSHdr32::SHT_STRTAB
      stream.seek(strtab.sh_offset)
      names = stream.read(strtab.sh_size)
      @sections.each do |section|
        if section.sh_type != ElfSHdr32::SHT_NULL
          infos = SectionInformations.new
          names_i = section.sh_name
          infos.name   = names[names_i...names.index("\x00", names_i)].freeze
          infos.header = section
          if section.sh_offset + section.sh_size < stream.length
            stream.seek(section.sh_offset)
            infos.data = stream.read(section.sh_size)
          else
            infos.data = SectionInformations::INVALID
          end
          @named_sections[infos.name] = infos
        end
      end
    end
    @symbols = {}
    @relocations = {}

    parsed_headers = {
      ElfSHdr32::SHT_SYMTAB => [Elf32_Sym, @symbols],
      ElfSHdr32::SHT_REL => [Elf32_Rel, @relocations]
    }

    @named_sections.each do |name, infos|
      header = infos.header
      data = []
      ref_structure, name_dict = *parsed_headers[header.sh_type]

      if name_dict
        stream.seek(header.sh_offset)
        (header.sh_size / ref_structure.size!).times do
          data << ref_structure.from!(stream)
        end
        name_dict[name] = data
      end
    end
  end
end

class Structures < Hash
  def initialize(structures_type)
    @structures_type = structures_type
  end

  def []=(name, value)
    if value.is_a? @structures_type
      super(name, value)
    else
      raise ArgumentError, "Expected a #{@structures_type.inspect} value, got a #{value.class.inspect}"
    end
  end

  def size!
    @structures_type.size! * self.length
  end
end

class ArmElf

  EM_ARM = 40

  attr_accessor :data
  attr_accessor :text

  attr_accessor :header
  attr_accessor :phdr
  attr_accessor :shdr
  attr_accessor :sections_names

  @@defaults = {
    data_offset: 0x20000,
    text_offset: 0x10000
    }

  @@empty_pshdr = {
    sh_name: 0,
    sh_type: 0,
    sh_flags: 0,
    sh_addr: 0,
    sh_offset: 0,
    sh_size: 0,
    sh_link: 0,
    sh_info: 0,
    sh_addralign: 0,
    sh_entsize: 0
  }
  def init_shdr(params = {})
    ElfSHdr32.set!(@@empty_pshdr.merge(params))
  end

  def section_names
    keynames = ""
    @shdr.keys.each do |name|
      @shdr[name].sh_name = keynames.length
      keynames << name
      keynames << "\0"
    end
    keynames << ("\0" * (keynames.length % 4))
    keynames
  end

  def initialize

    @layout = [:header, :phdr, :text, :data,
               :shdr, :shstrtab]

    @header = ElfHdr32.new
    @header.set!(
      e_ident:   [127, 69, 76, 70, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      e_type:    ElfHdr32::ET_EXEC,
      e_machine: EM_ARM,
      e_version: 1,
      e_flags:   0x5000202,
      e_ehbits:  ElfHdr32.size!
    )

    @program_headers = {}
    @phdr = Structures.new(ElfPHdr32)
    # dh : data header
    dh = ElfPHdr32.set!(
      p_type:  ElfPHdr32::PT_LOAD,
      p_flags: ElfPHdr32::PF_W | ElfPHdr32::PF_R,
      p_align: 0x10000
    )

    th = ElfPHdr32.set!(
      p_type:  ElfPHdr32::PT_LOAD,
      p_flags: ElfPHdr32::PF_X | ElfPHdr32::PF_R,
      p_align: 0x10000
    )

    @phdr[".data"] = dh
    @phdr[".text"] = th

    # Are empty and shstrtab useful ?
    @sections_headers = {}
    @shdr = Structures.new(ElfSHdr32)
    @shdr[""] = init_shdr

    dsh = init_shdr(
      sh_type: ElfSHdr32::SHT_PROGBITS,
      sh_flags: ElfSHdr32::SHF_ALLOC | ElfSHdr32::SHF_WRITE,
      sh_addralign: 1
    )

    tsh = init_shdr(
      sh_type: ElfSHdr32::SHT_PROGBITS,
      sh_flags: ElfSHdr32::SHF_ALLOC | ElfSHdr32::SHF_EXECINSTR,
      sh_addralign: 4
    )

    sections_strtab = init_shdr(
      sh_type: ElfSHdr32::SHT_STRTAB,
      sh_addralign: 1
    )

    @shdr[".data"] = dsh
    @shdr[".text"] = tsh
    @shdr[".shstrtab"] = sections_strtab

    [@phdr, @program_headers, @shdr, @sections_headers].each_slice(2) do |headers, metadata|
      headers.each do |name, properties|
        metadata[name] = SectionInformations.new(name: name, header: properties)
      end
    end
    @program_headers.each do |section, metadata|
      metadata.header.p_filesz = metadata.header.p_memsz =
          Proc.new { metadata.data.size! }
      metadata.header.p_offset = Proc.new { self.offset_of(section[1..-1].to_sym) }
    end
    @sections_headers.each do |section, metadata|
      if section != ""
        metadata.header.sh_size = Proc.new { sizeof(metadata.data) }
        metadata.header.sh_name = Proc.new { i = shstrtab.index(section); puts "Index : #{i}"; i }
        metadata.header.sh_offset = Proc.new { self.offset_of(section[1..-1].to_sym) }
      end
    end
    @shstrtab = ""
    @sections_headers[".shstrtab"].data = @shstrtab

  end

  def data=(d)
    @program_headers[".data"].data = @sections_headers[".data"].data = @data = d
    d.start_address =
        @sections_headers[".data"].header.sh_addr =
        @program_headers[".data"].header.p_vaddr =
        @program_headers[".data"].header.p_paddr =
        Proc.new { @@defaults[:data_offset] + offset_of(:data) }

  end

  def text=(t)
    @program_headers[".text"].data = @sections_headers[".text"].data = @text = t
    @program_headers[".text"].header.p_filesz = @program_headers[".text"].header.p_memsz =
        Proc.new { self.offset_of(:text) + t.size! }
    @program_headers[".text"].header.p_vaddr =
        @program_headers[".text"].header.p_paddr =
        @@defaults[:text_offset]
    @sections_headers[".text"].header.sh_addr =
        @@defaults[:text_offset] + offset_of(:text)
    @program_headers[".text"].header.p_offset = 0
  end

  def shstrtab
    names = ""
    @sections_headers.keys.each do |name|
      names << name + "\0"
      names << "\0" * (names.length % 4)
    end
    @shstrtab.replace names
    @shstrtab
  end


  def offset_of(element)
    @layout[0...@layout.index(element)].inject(0) do |total_size, part|
      puts "Offset of : #{element}"
      total_size + sizeof(self.send(part))
    end
  end

  def sizeof(element)
    return element.size! if element.respond_to? :size!
    case element
    when String
      element.length
    when Hash
      values = element.values
      values.length * values.first.class.size!
    else
      puts "Unknown type : #{element.class}"
      0
    end
  end

  def write(element, stream)
    return element.memwrite!(stream) if element.respond_to? :memwrite!
    return element.write!(stream) if element.respond_to? :write!

    case element
    when Hash
      element.values.each {|h| h.memwrite!(stream)}
    when String
      stream.write(element)
    else
      raise ArgumentError, "Don't know how to write #{element.class}"
    end
  end

  def generate

    p ElfSHdr32.size!
    # 1st pass : Calculate sizes
    sizes = {}
    @layout.each do |part_name|
      p part_name
      sizes[part_name] = sizeof(self.send(part_name))

    end

    p sizes

    self.shstrtab

    @header.e_entry  = @shdr[".text"].sh_addr
    @header.e_phoff  = offset_of(:phdr)
    @header.e_shoff  = offset_of(:shdr)
    @header.e_ehbits = ElfHdr32.size!
    @header.e_phentsize = ElfPHdr32.size!
    @header.e_phnum  = @phdr.length
    @header.e_shentsize = ElfSHdr32.size!
    @header.e_shnum  = @shdr.length
    @header.e_shstrndx = @shdr.keys.index(".shstrtab")

#     puts "%x" % th.p_memsz
#     puts "%x" % @header.e_shoff
#     puts "%x" % @shdr[".shstrtab"].sh_offset

    elf = StringIO.new("", "w+")
    @layout.each do |part|
      d = self.send(part)
      puts "#{part} : #{p.inspect}"
      write(d, elf)
    end

    File.write("elf_test", elf.string)
    elf.close
#
#   Elf64_Half :e_shstrndx;
  end
end

# out_file.write("\x00")
