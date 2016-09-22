require_relative 'rasm'
require 'minitest/autorun'

class TestAddress < Minitest::Test
  def test_arithmetic
    a = Address.new(0x10000)
    assert_equal 0x10000, a.value
    assert_equal 0x10000, a
  end
  
  def test_part
    a = Address.new(0xffffffff)
    b = a.part(0,16)
    assert_equal 0xffff, b
    
    c = Address.new(0x12345678)
    assert_equal 0x1234, c[16..32]
    assert_equal 0x2468, c[15..31]
    
    c.value = 0x2468ace0
    assert_equal 0xace0, c[0..16]
    assert_equal 0x2468, c[16..32]
  end
end