require_relative '/home/gamer/プログラミング/structure.rb'
s = StringIO.new(File.read('elf_test'))
elf = ElfReader32.new(stream: s)
p elf.header
puts "-----------------"

#p elf.named_sections[".text"].header
#p elf.program_sections[0]
#p elf.named_sections[".data"].header
#p elf.program_sections[1]

p elf.named_sections

