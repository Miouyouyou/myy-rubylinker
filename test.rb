require_relative 'structure'
require_relative 'rasm'

a = ArmElf.new
a.data = Assembler::DATA
a.text = TEXT.call
a.generate
