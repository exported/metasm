require 'metasm/exe_format/main'
require 'metasm/exe_format/mz'
require 'metasm/exe_format/coff_encode'
require 'metasm/exe_format/coff_decode'

module Metasm
class PE < COFF
	PESIG = "PE\0\0"

	attr_accessor :coff_offset, :signature, :mz

	def self.decode(str)
		pe = new
		pe.encoded = EncodedData.new << str
		pe.decode
		pe.mz.encoded = pe.encoded[0...pe.coff_offset-4]
		pe.mz.encoded.ptr = 0
		pe.mz.decode_header
		pe
	end

	def initialize
		@mz = MZ.new
		super
	end

	def decode_header
		@encoded.ptr = 0x3c
		@encoded.ptr = decode_word
		@signature = @encoded.read(4)
		raise InvalidExeFormat, "Invalid PE signature #{@signature.inspect}" if @signature != PESIG
		@coff_offset = @encoded.ptr
		super
	end

	def encode_default_mz_header
		mzstubp = Program.new(Ia32.new(386, 16))
		mzstubp.parse <<'EOMZSTUB'
_str	db "Needs Win32!\r\n$"
start:
	push cs
	pop  ds
	xor  dx, dx	  ; ds:dx = addr of $-terminated string
	mov  ah, 9
	int  21h
	mov  ax, 4c01h    ; exit code in al
	int  21h
EOMZSTUB
		mzstubp.encode
		@mz = MZ.from_program mzstubp
		mzparts = @mz.pre_encode

		@mz.encoded = EncodedData.new << mzparts.shift
		raise 'OH NOES !!1!!!1!' if @mz.encoded.virtsize > 0x3c	# MZ header is too long, cannot happen
		# put as much as we can before 0x3c
		until mzparts.empty?
			break if mzparts.first.virtsize + @mz.encoded.virtsize > 0x3c
			@mz.encoded << mzparts.shift
		end

		# set PE signature pointer at 0x3c
		@mz.encoded.align 0x3c
		@mz.encoded << Expression['pesigptr'].encode(:u32, :little)

		# add the end of the MZ program
		until mzparts.empty?
			@mz.encoded << mzparts.shift
		end

		# ensure the sig is 8-aligned
		@mz.encoded.align 8

		# fixup the MZ program's relocs and the PE sig ptr
		start = @mz.label_at @mz.encoded, 0
		@mz.encoded.fixup 'pesigptr' => @mz.encoded.virtsize
		@mz.encoded.fixup @mz.encoded.export.inject({}) { |binding, (name, offset)| binding.update name => Expression[start, :+, offset] }

		# fixup the MZ checksum
		@mz.encoded.fill
		@mz.encode_fix_checksum
	end

	def encode_header(*a)
		# @mz.encoded must be an EncodedData with 0x3c pointing beyond its last byte, which should be 8-aligned, and its 2 1st bytes should be 'MZ'
		encode_default_mz_header if not @mz.encoded

		@encoded << @mz.encoded.dup

		# append the PE signature
		@signature ||= PESIG
		@encoded << @signature

		super
	end
end

class LoadedPE < PE
	def rva_to_off(rva)
		rva if rva and rva > 0 and rva <= @encoded.virtsize
	end

	def decode_sections
		@sections.each { |s|
			s.encoded = @encoded[s.virtaddr, s.virtsize]
		}
	end
end
end
