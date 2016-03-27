module ARM
  module Opcodes
    module Conditions
      [:eq, :ne, :cs, :cc, :mi, :pl, :vs, :vc, :hi, :ls, :ge, :lt, :gt, :le, :al].each_with_index do |condition, i|
        self.const_set(condition.upcase, i)
      end
    end
    def self.mov(register, *args, condition: Conditions::AL)
      condition <<= 28
      constant_part = (0b001110100000 << 16)
      rd = (register.to_s[1..-1].to_i) << 12
      imm12 = args[0] & 0xfff
      condition | constant_part | rd | imm12
    end
    def self.movw(register, value, condition: Conditions::AL)
      puts "register : #{register} - value : #{value}"
      condition <<= 28
      constant_part = (0b00110000 << 20)
      immediate = ("%016b" % value)[0..15]
      imm4 = immediate[0..3].to_i(2) << 16
      rd = (register.to_s[1..-1].to_i) << 12
      imm12 = immediate[4..16].to_i(2)
      condition | constant_part | imm4 | rd | imm12
    end
    def self.movt(register, value, condition: Conditions::AL)
      condition <<= 28
      constant_part = (0b00110100 << 20)
      immediate = ("%016b" % value)[0..15]
      imm4 = immediate[0..3].to_i(2) << 16
      rd = (register.to_s[1..-1].to_i) << 12
      imm12 = immediate[4..16].to_i(2)
      condition | constant_part | imm4 | rd | imm12
    end
    def self.svc(*args)
      0xef000000
    end
  end
  
end

module SimpleDataPacker
  attr_writer :pack_string

  @@ps = {
    ascii: "a*",
    int8_t: "c*",
    uint8_t: "C*",
    int16_t: "s<*",
    uint16_t: "S<*",
    int32_t: "i<*",
    uint32_t: "I<*",
    int64_t: "q<*",
    uint64_t: "Q<*",
    float: "e*",
    double: "E*",
    utf8: "U*"
  }
  
  { 
    String => :ascii,
    Fixnum => :uint32_t,
    Float  => :float
  }.each {|cl, type| @@ps[cl] = @@ps[type]}
  
  def self.extended(obj)
    puts "extended ! @@ps[obj.type] == #{@@ps[obj.type]}"
    p obj.type
    obj.instance_variable_set(:@pack_string, @@ps[obj.type])
    puts "@pack_string : #{obj.instance_variable_get(:@pack_string)}"
  end
  
  def packed_value
    puts "value : #{value} - @pack_string : #@pack_string"
    [value].pack(@pack_string)
  end
  def packed_size
    packed_value.bytesize
  end

end

class DataSection
  attr_accessor :start_address
  attr_accessor :default_alignment
  
  class MetaData
    attr_accessor :position
    attr_accessor :alignment
    attr_accessor :value
    attr_accessor :type

    # Implicitly requires
    # packed_size
    # packed_value
    def initialize(pos:, alignment:, value:, type:)
      @position  = pos
      @alignment = alignment
      @value     = value
      @type      = type
    end
  end
  
  def []=(name, data, type: data.class, type_mod: SimpleDataPacker)
    mdata = MetaData.new(
      pos: @metadata.length, 
      alignment: @default_alignment,
      value: data,
      type: type
    )
    
    mdata.extend(type_mod)
    @metadata[name] = mdata
  end
  
  def [](name)
    @metadata[name]
  end
  
  def v_address(name)
    addr_at(@metadata[name].position)
  end
  
  def addr_at(pos)
    @metadata.values[0...pos].inject(@start_address) do |address, mdata|
      #puts "address : #{address}"
      address += mdata.packed_size
      [mdata.alignment, default_alignment].each do |alignment|
        remain = address % alignment
        address += remain if remain != 0
        #puts "Realigned address : #{address}"
      end
      #puts "New address : #{address}"
      address
    end
  end
  
  def initialize(alignment: 4, start_address: 0)
    @metadata      = {}
    @start_address = start_address
    @default_alignment = alignment
  end
  
  def remove(name)
    p = @metadata[name].position
    @metadata.delete(name)
    @order.delete_at(p)
  end
  
  def size!
    addr_at(@metadata.length) - start_address
  end
  
  def write!(stream)
    infos = ::StringIO.new("", "w+")
    infos.write("\0" * size!)
    @metadata.each do |name,md|
      infos.seek(v_address(name) - start_address)
      infos.write(md.packed_value)
    end
    stream.write(infos.string)
  end
end

def assembly(&instructions)
  a = Assembler.new
  a.instance_eval(&instructions)
  a.encoded_instructions
end

class Assembler < BasicObject
  DATA = ::DataSection.new(start_address: 0x20000)
  DATA[:hello_world] = "Welcome to the cochon d'inde\n"
  DATA[:miaou]       = "Wow, it's a fucking miaou !!\n"

  def d(name, bottom = 0, top = 0)
    addr = DATA.v_address(name)
    return addr unless top > 0
    (addr >> bottom) & (2**(top - bottom)-1)
  end

  def size(name)
    DATA[name].packed_size
  end
  
  attr_reader :encoded_instructions
  def initialize
    @encoded_instructions = []
    
    def @encoded_instructions.size!
      self.map(&:machine_code).join("").length
    end
    def @encoded_instructions.write!(stream)
      stream.write(self.map(&:machine_code).join(""))
    end
  end
  def method_missing(name, *args)
    @encoded_instructions << Instruction.new(
      assembly: %Q|#{name} #{args.map(&:inspect).join(", ")}|,
      machine_code: ::ARM::Opcodes.send(name, *args)
    )
  end
  class Instruction
    attr_accessor :assembly
    attr_writer :machine_code
    def machine_code
      [@machine_code].pack("L<")
    end
    def inspect
      self.assembly
    end
    def to_s
      self.machine_code
    end
    def initialize(assembly: "", machine_code: "")
      @assembly     = assembly
      @machine_code = machine_code
    end
  end
  
end

TEXT = Proc.new { assembly do
  mov  :r0, 1
  movw :r1, d(:hello_world, 0,  16)
  movt :r1, d(:hello_world, 16, 32)
  mov  :r2, size(:hello_world)
  mov  :r7, 4
  svc  0
  
  mov  :r0, 1
  movw :r1, d(:miaou, 0, 16)
  movt :r1, d(:miaou, 16, 32)
  svc 0
  
  mov :r0, 0
  mov :r7, 1
  svc 0
end
                }