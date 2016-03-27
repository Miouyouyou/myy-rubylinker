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

# NWJ454G3
# DJ2PXKG3

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
		
		def size!
			@elements.values.map(&:size!).inject(0) {|total,size| total + size}
		end
		
		def type(nom_type, *args, bytes:, type_impl: SimpleType, element_impl: SimpleElement, **named_args)
			type = types![nom_type.to_sym] = type_impl.new(*args, bytes: bytes, **named_args)
			
			(class << self; self; end).instance_eval do
				# class S; type :uchar; end defines S.uchar :element_name[, array: n] ...
				define_method(nom_type.to_sym) do |nom_element, array: nil|
					
					# ... which add the element to @elements on invocation
					elements![nom_element.to_sym] = element_impl.new(type, array: array)
					# ... which defines an instance method 'element_name', for S instances
					attr_accessor nom_element.to_sym
					
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
	
	def memset!(stream)
		self.class.elements!.each do |field_name, field_object|
			self.__send__ :"#{field_name}=", field_object.read(stream)
		end
	end
	
	def memwrite!(stream)
		self.class.elements!.each do |field_name, field_object|
			value = self.__send__(:"#{field_name}")
			field_object.write(stream, value)
		end
	end
  
  def set!(hsh)
    hsh.each {|field, value| self.send(:"#{field}=", value) }
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
class ElfReader32
	
	attr_reader :header
	attr_reader :program_sections
	attr_reader :sections
	attr_reader :named_sections
	attr_reader :symbols
	attr_reader :relocations
	
	
	class SectionInformations
		INVALID = ""
		attr_accessor :name
		attr_accessor :header
		attr_accessor :data
		
		def data!
			StringIO.new(data)
		end
	end
	
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

class ArmElf
	
	attr_accessor :data
  attr_accessor :text
  
  attr_accessor :main_header
  attr_accessor :program_headers
  attr_accessor :program_data
  attr_accessor :sections_headers
  attr_accessor :sections_data
  
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
    sh = ElfSHdr32.new
    sh.set!(@@empty_pshdr.merge(params))
    sh
  end
  
	def initialize
    
    @layout = [:main_header, :program_headers, :program_data, 
               :sections_headers, :sections_data]
    
		@header = ElfHdr32.new
		@header.e_ident   = [127, 69, 76, 70, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0]
		@header.e_type    = 2
		@header.e_machine = 40
		@header.e_version = 1
    @header.e_flags   = 0x5000202
    @header.e_ehbits  = ElfHdr32.size!
    
    @phdr = {}
    # dh : data header
    dh = ElfPHdr32.new
    dh.p_type   = ElfPHdr32::PT_LOAD
    dh.p_offset = ElfHdr32.size! + ElfPHdr32.size! * 2
    dh.p_vaddr  = 0x20000 + dh.p_offset
    dh.p_paddr  = dh.p_vaddr
    dh.p_flags  = 6
    dh.p_align  = 0x10000
    
    th = ElfPHdr32.new
    th.p_type   = ElfPHdr32::PT_LOAD
    th.p_offset = 0
    th.p_vaddr  = 0x10000
    th.p_paddr  = 0x10000
    th.p_flags  = 5
    th.p_align  = 0x10000
    
    @phdr[".data"] = dh
    @phdr[".text"] = th
    
    # Are empty and shstrtab useful ?
    @shdr = {}
    @shdr[""] = init_shdr
    #<ElfSHdr32:0x0055d04949cf18 @sh_name=17, @sh_type=1, @sh_flags=3, @sh_addr=131268, @sh_offset=196, @sh_size=24, @sh_link=0, @sh_info=0, @sh_addralign=1, @sh_entsize=0>
    #<ElfPHdr32:0x0055d04949e7c8 @p_type=1, @p_offset=196, @p_vaddr=131268, @p_paddr=131268, @p_filesz=24, @p_memsz=24, @p_flags=6, @p_align=65536>

    dsh = init_shdr(
      sh_type: ElfSHdr32::SHT_PROGBITS,
      sh_flags: ElfSHdr32::SHF_ALLOC | ElfSHdr32::SHF_WRITE, 
      sh_addr: dh.p_vaddr + dh.p_offset,
      sh_offset: dh.p_offset,
      sh_align: 1
    )

    #<ElfSHdr32:0x0055d04949d580 @sh_name=11, @sh_type=1, @sh_flags=6, @sh_addr=65684, @sh_offset=148, @sh_size=48, @sh_link=0, @sh_info=0, @sh_addralign=4, @sh_entsize=0>
    #<ElfPHdr32:0x0055d04949ee30 @p_type=1, @p_offset=0, @p_vaddr=65536, @p_paddr=65536, @p_filesz=196, @p_memsz=196, @p_flags=5, @p_align=65536>
    tsh = init_shdr(
      sh_type: ElfSHdr32::SHT_PROGBITS,
      sh_flags: ElfSHdr32::SHF_ALLOC | ElfSHdr32::SHF_EXECINSTR, 
      sh_addr: th.p_vaddr,
      sh_offset: th.p_offset,
      sh_align: 4
    )
    
    shstrtab = init_shdr(
      sh_type: ElfSHdr32::SHT_STRTAB,
      sh_addralign: 1
    )
    
    @shdr[".data"] = dsh
    @shdr[".text"] = tsh
    @shdr[".shstrtab"] = shstrtab
  end
  
  def data=(d)
    @data = d
    d.start_address = @phdr[".data"].p_vaddr
  end
  
  def generate
    dh = @phdr[".data"]
    dsh = @shdr[".data"]
    dsh.sh_size = dh.p_filesz = dh.p_memsz = data.size!
        
    th = @phdr[".text"]
    tsh = @shdr[".text"]
    tsh.sh_size = text.size!
    tsh.sh_addr += tsh.sh_offset = ElfHdr32.size! + ElfPHdr32.size! * @phdr.length + dh.p_filesz
    th.p_memsz = th.p_filesz = tsh.sh_offset + text.size!
    
    keynames = ""
    @shdr.keys.each do |name|
      @shdr[name].sh_name = keynames.length
      keynames << name
      keynames << "\0"
    end
    keynames << ("\0" * (keynames.length % 4))
    @shdr[".shstrtab"].sh_size = keynames.length
    
    @header.e_entry  = tsh.sh_addr
    @header.e_phoff  = ElfHdr32.size!
    @header.e_shoff  = th.p_memsz
    @header.e_ehbits = ElfHdr32.size!
    @header.e_phentsize = ElfPHdr32.size!
    @header.e_phnum  = @phdr.length
    @header.e_shentsize = ElfSHdr32.size!
    @header.e_shnum  = @shdr.length
    @header.e_shstrndx = @shdr.keys.index(".shstrtab")
    
    @shdr[".shstrtab"].sh_offset = @header.e_shoff + @header.e_shentsize * @header.e_shnum
    puts "%x" % th.p_memsz
    puts "%x" % @header.e_shoff
    puts "%x" % @shdr[".shstrtab"].sh_offset
    
    elf = StringIO.new("", "w+")
    @header.memwrite!(elf)
    @phdr.values.each {|h| h.memwrite!(elf)}
    data.write!(elf)
    text.write!(elf)
    @shdr.values.each {|h| h.memwrite!(elf)}
    elf.write(keynames)
    
    File.write("elf_test", elf.string)
    elf.close
#   
#   Elf64_Half :e_shstrndx;
  end
end

# out_file.write("\x00")


