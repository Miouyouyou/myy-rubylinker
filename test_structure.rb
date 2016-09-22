require 'minitest/autorun'
require_relative 'structure'

class TestStruct < Minitest::Test
  class TestHeader < CStruct
    EI_NIDENT = 16
    typedef :uint16_t, :Elf64_Half
    typedef :uint32_t, :Elf64_Word
    typedef :uint64_t, :Elf64_Addr
    typedef :uint64_t, :Elf64_Off
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

  def setup
  end

  def test_reading
    file = File.open("ohmydoginou", "r")
    elf = TestHeader.new
    elf.memset!(file)
    assert_equal 2,  elf.e_type
    assert_equal 62, elf.e_machine
    assert_equal 1,  elf.e_version
    assert_equal 0x0000000000400de0, elf.e_entry
    assert_equal 0x0000000000000040, elf.e_phoff
    assert_equal 0x000000000002b538, elf.e_shoff
    assert_equal 0, elf.e_flags
    assert_equal 0x40, elf.e_ehbits
    assert_equal 0x38, elf.e_phentbits
    assert_equal 0xa, elf.e_phnum
    assert_equal 0x40, elf.e_shentbits
    assert_equal 0x25, elf.e_shnum
    assert_equal 0x22, elf.e_shstrndx
    file.close
  end
  
  def test_write
    elf = TestHeader.new
    File.open("ohmydoginou", "r") do |f|
      elf.memset!(f)
    end
    File.open("testwrite", "w") do |f|
      elf.memwrite!(f)
    end
    new_elf = TestHeader.new
    File.open("testwrite", "r") do |f|
      new_elf.memset!(f)
    end
    TestHeader.elements!.each do |field_name, field_object|
      assert_equal elf.send(field_name.to_sym), new_elf.send(field_name.to_sym) 
    end
  end
  
  class AS < CStruct
    uint32_t :a;
    uint32_t :b;
    uint16_t :c;
    uint16_t :d;
  end
  
  def test_reading_blocks
    h = AS.new
    h.a = 2
    h.b = Proc.new {|header| header.a + 60 }
    h.c = Proc.new {h.b / 2}
    h.d   = Proc.new {h.b * 4 }
    assert_equal 2,  h.a
    assert_equal 62, h.b
    assert_equal 31, h.c
    assert_equal 248, h.d
    n = StringIO.new("", "w+")
    h.memwrite!(n)
    p n.string
  end
  
  def test_size!
    h = TestHeader.new
    assert_equal 64, TestHeader.size!
    assert_equal 64, h.size!
  end
end