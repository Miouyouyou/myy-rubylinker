require_relative 'structure'
require_relative 'rasm'

a = ArmElf.new
a.data = Program::DATA
a.text = Program::TEXT
a.generate
