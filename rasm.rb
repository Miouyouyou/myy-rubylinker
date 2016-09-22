# # Not efficient if you need execute two instructions anyway
# thumb = {sizes: [16, 32], align: 2, registers: {low_registers: :guaranteed, high_registers: :exceptional}}
# # Arm and Thumb can interwork freely
# # Change instruction set using BX, BLX, LDR, LDM
# change_to_thumb_if_rd_is_pc = [
#   :adc, :add, :and, :asr, :bic, :eor, :lsl, :lsr, :mov, :mvn, :orr, 
#   :ror, :rrx, :rsb, :rsc, :sbc, :sub
# ]
# # Conditional execution in Thumb : 
# # - 16 bits Conditional branch with a range of -256 +254 bytes
# # - 32 bits Conditional branch with a +-1MB range
# # - 16 bits Compare and Branch on (Non)Zero with a +4~+130 bytes range
# # - 4 instructions in a IT block
# 
# # Standard data processing instructions :
# # - Register, operand1: Register, operand2: Register
# # - Register, operand1: Register, operand2: Immediate
# # + Shift
# # ARM, Thumb : Immediate
# # ARM : Register
# # Available Shifts :
# # LSL - Logical Shift Left       1 to 31 bits
# # LSR - Logical Shift Right      1 to 32 bits
# # ASR - Arithmetic Shift Right   1 to 32 bits
# # ROR - Rotate Right             1 to 31 bits
# # RRX - Rotate Right with Extend ???
# #
# # In ARM, the destination register can be PC, causing a branch.
# # In Thumb, this is only permitted for some 16 bits forms of ADD and MOV.
# #
# # Conditional flags can be set
# # If no condition flags is set, the existing flags are preserved
# instructions {
#   sdpi: [
#     :adc, :add, :adr, :and, :bic, :cmn, :cmp, :eor, :mov, :mvn, :orn, :orr,
#     :rsb, :rsc, :sbc, :sub, :teq, :tst
#   ]
# }
# shifts:   [:asr, :lsl, :lsr, :ror, :rrx]
# multiply: {
#   standard: [:mla, :mls, :mul],
#   signed:   [:smlabb, :smlabt, :smlatb, :smlatt,
#              :smlad,
#              :smlal,
#              :smlalbb, :smlalbt, :smlaltb, :smlaltt,
#              :smlald,
#              :smlawb, :smlawt,
#              :smlsd,
#              :smlsld,
#              :smmla,
#              :smmls,
#              :smuad,
#              :smulbb, :smulbt, :smultb, :smultt,
#              :smull,
#              :smulwb, :smulwt,
#              :smusd],
#   unsigned: [:umaal, :umlal, :umull]
# }
# saturating: [:ssat, :ssat16, :usat, :usat16]
# packing: [:pkh, 
#           :sxtab, :sxtab16, :sxtah,
#           :sxtb, :sxtb16, :sxth,
#           :uxtab, :uxtab16, :uxtah,
#           :uxtb, :uxtb16, :uxth]
# miscellaneous: [:bfc, :bfi, :clz, :movt, :rbit, :rev, :rev16, :revsh, :sbfx, 
#                 :sel, :ubfx, :usad8, :usada8]
# prefixes: [s: "Signed arithmetic modulo 2**8 or 2**16",
#            q: "Signed saturating arithmetic",
#            sh: "Signed arithmetic, halving the results",
#            u: "Unsigned arithmetic modulo 2**8 or 2**16",
#            uq: "Unsigned saturating arithmetic",
#            uh: "Unsigned arithmetic, halving the results"]
# prefixable: [ :add16, :asx, :sax, :sub16, :add8, :sub8 ]
# divide: [:sdiv, :udiv]
# status_registers_access: [:mrs, :msr]
# load_prefixes: [
#   b: "Byte",
#   sb: "Signed Byte",
#   h: "Halfword",
#   sh: "Signed Halfword",
#   d: "Doubleword"
# ]
# load_store: [ldr: {"": [:h, :sh, :b, :sb, :d],
#                    t:  [:ht, :sht, :bt, :sbt],
#                    ex: [:exh, :exb, :exd]},
#              str: {"": [:h, :b, :d],
#                    t:  [:ht, :bt],
#                    ex: [:exh, :exb, :exd]}
#             ]
#              

class Instruction
  
  attr_accessor :mnemonic
  attr_accessor :args
  attr_accessor :size
  
  def initialize(mnemonic, args: , size: 4)
    @mnemonic = mnemonic
    @args     = args
    @size     = size
  end
  
  def assemble
    ARM::Opcodes.send(mnemonic, *args)
  end
  
  def size!
    self.size
  end
  
  def to_s
    "#{mnemonic} #{args}"
  end
  
end

# The current point of Address is to help the delayed assembly of the
# code by the Assembler.
# It MUST convert to a Fixnum when used in an arithmetic operation
class Address
  
  @@value_methods = { true => Proc.new {|v| v.call}, false => Proc.new {|v| v} }

  def initialize(v)
    self.value = v
  end
  
  def value=(v)
    @value  = v
    @vblock = @@value_methods[v.respond_to?(:call)]
  end
  
  def value
    @vblock.call(@value)
  end
  
  def inspect
    value
  end
  
  def coerce(other)
    return value, other
  end
  
  def method_missing(meth, *args)
    self.value.send(meth, *args)
  end
  
  def ==(o)
    self.value == o
  end
  
  def part(bottom = 0, top = 0)
    if top > bottom
      Address.new(Proc.new { (self.value >> bottom) & (2**(top - bottom)-1)})
    else
      self
    end
  end
  
  def [](argument)
    if argument.is_a? Range
      fin = argument.end - (argument.exclude_end? ? 1 : 0)
      self.part(argument.begin, fin)
    else
      self.value[argument]
    end
  end
  
  def inspect
    "#{self.value} (Address)"
  end
  
  def to_s(*args)
    self.value.to_s(*args)
  end
  
  def hash
    self.value.hash
  end
  
#   def inspect
#     self.value
#   end
#   
end

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
    p obj.type
    obj.instance_variable_set(:@pack_string, @@ps[obj.type])
  end
  
  def packed_value
    [value].pack(@pack_string)
  end
  def packed_size
    packed_value.bytesize
  end

end


class DataSection
  attr_writer :start_address
  attr_accessor :default_alignment
  
  def start_address
    (!@start_address.respond_to?(:call) && @start_address) || @start_address.call
  end
  
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
    addr = Address.new(Proc.new { addr_at(@metadata[name].position) })
    puts "Address of #{name} : #{addr}"
    addr
  end
  
  def addr_at(pos)
    @metadata.values[0...pos].inject(start_address) do |address, mdata|
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
    puts "start_address : #{start_address}"
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

# def assembly(&instructions)
#   a = Assembler.new
#   a.instance_eval(&instructions)
#   a.encoded_instructions
# end

# TODO : Assemble when required
class Assembler
  
  attr_reader   :instructions
  attr_accessor :data
  
  def initialize(architecture:, data: ::DataSection.new, &block)
    @architecture = architecture
    @instructions = []
    assemble(&block) if block
  end
  
  def method_missing(meth, *args)
    if @architecture::Opcodes.respond_to? meth
      @instructions << ::Instruction.new(meth, args: args)
    else
      ::Kernel.p meth
      super(*args)
    end
  end
  
  def assemble(&block)
    instance_eval(&block)
  end
  
  def size!
    @instructions.map(&:size!).inject(&:+)
  end
  
  def to_s
    @instructions.map(&:to_s).inspect
  end
  
  def data!
    @instructions.map(&:assemble)
  end
  
  def memwrite!(stream)
    data = self.data!
    ::Kernel.p self.to_s
    stream.write(data.pack("I<*"))
  end

end

class Program
  DATA = ::DataSection.new
  DATA[:miaou]       = "The best cochon d'inde of the ze planet !\n"
  DATA[:hello_world] = "It's me POUIPPOUIPOSAURUSREX ! Catch me !\n"

  TEXT = Assembler.new(architecture: ARM, data: DATA) do
    mov  :r0, 1
    movw :r1, DATA.v_address(:hello_world)[0..16]
    movt :r1, DATA.v_address(:hello_world)[16..32]
    mov  :r2, DATA[:hello_world].packed_size
    mov  :r7, 4
    svc  0

    mov  :r0, 1
    movw :r1, DATA.v_address(:miaou)[0..16]
    movt :r1, DATA.v_address(:miaou)[16..32]
    svc 0

    mov :r0, 0
    mov :r7, 1
    svc 0
  end
end

