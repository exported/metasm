require 'metasm/ia32/decode'
require 'metasm/ia32/render'
require 'metasm/exe_format/elf.rb'

if ARGV.empty?
	ARGV << '/lib/libc.so.6' << 'ispunct'
end

class Metasm::CPU ; def inspect ; 'cpu' end end

pgm, opts = Metasm::ELF.decode File.read(ARGV.shift)
ARGV.each { |exp|
	pgm.desasm pgm.export[exp]
}

#pgm.blocks_to_source
#puts pgm.sections.map { |s| s.source }
p pgm.block
pgm.block.sort.each { |addr, block|
	s = pgm.sections.find { |s| s.base <= addr and s.base + s.encoded.virtsize > addr }
	s.encoded.export.each { |e, off| puts "#{e}:" if off == addr - s.base }
	block.list.each { |di|
		print '%08X ' % addr
		print s.encoded.data[addr-s.base, di.bin_length].unpack('C*').map { |c| '%02x' % c }.join.ljust(16) + ' '
		print di.instruction
		puts

		addr += di.bin_length
	}
	puts
}

