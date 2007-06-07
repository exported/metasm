require 'metasm/exe_format/coff'
require 'metasm/encode'

module Metasm
class COFF
	class Header
		# encodes a COFF Header, using coff.sections.length and opth.virtsize
		def encode(coff, opth)
			set_default_values coff, opth

			coff.encode_half(coff.int_from_hash(@machine, MACHINE)) <<
			coff.encode_half(@num_sect) <<
			coff.encode_word(@time) <<
			coff.encode_word(@ptr_sym) <<
			coff.encode_word(@num_sym) <<
			coff.encode_half(@size_opthdr) <<
			coff.encode_half(coff.bits_from_hash(@characteristics, CHARACTERISTIC_BITS))
		end

		# finds good default values for header
		def set_default_values(coff, opth)
			@machine     ||= 'UNKNOWN'
			@num_sect    ||= coff.sections.length
			@time        ||= Time.now.to_i
			@ptr_sym     ||= 0
			@num_sym     ||= 0
			@size_opthdr ||= opth.virtsize
			@characteristics ||= 0
		end
	end

	class OptionalHeader
		# encodes an Optional header and the directories
		def encode(coff)
			set_default_values coff

			opth = \
			coff.encode_half(coff.int_from_hash(@signature, SIGNATURE)) <<
			coff.encode_uchar(@link_ver_maj) <<
			coff.encode_uchar(@link_ver_min) <<
			coff.encode_word(@code_size)  <<
			coff.encode_word(@data_size)  <<
			coff.encode_word(@udata_size) <<
			coff.encode_word(@entrypoint) <<
			coff.encode_word(@base_of_code) <<
			(coff.encode_word(@base_of_data) if @signature != 'PE+') <<
			coff.encode_xword(@image_base) <<
			coff.encode_word(@sect_align) <<
			coff.encode_word(@file_align) <<
			coff.encode_half(@os_ver_maj) <<
			coff.encode_half(@os_ver_min) <<
			coff.encode_half(@img_ver_maj) <<
			coff.encode_half(@img_ver_min) <<
			coff.encode_half(@subsys_maj) <<
			coff.encode_half(@subsys_min) <<
			coff.encode_word(@reserved)   <<
			coff.encode_word(@image_size) <<
			coff.encode_word(@headers_size) <<
			coff.encode_word(@checksum) <<
			coff.encode_half(coff.int_from_hash(@subsystem, SUBSYSTEM)) <<
			coff.encode_half(coff.bits_from_hash(@dll_characts, DLL_CHARACTERISTIC_BITS)) <<
			coff.encode_xword(@stack_reserve) <<
			coff.encode_xword(@stack_commit) <<
			coff.encode_xword(@heap_reserve) <<
			coff.encode_xword(@heap_commit) <<
			coff.encode_word(@ldrflags) <<
			coff.encode_word(@numrva)

			DIRECTORIES[0, @numrva].each { |d|
				if d = coff.directory[d]
					d = d.dup
					d[0] = Expression[d[0], :-, coff.label_at(coff.encoded, 0)] if d[0].kind_of? String
				else
					d = [0, 0]
				end
				opth << coff.encode_word(d[0]) << coff.encode_word(d[1])
			}

			opth
		end

		# find good default values for optheader members, based on coff.sections
		def set_default_values(coff)
			@signature    ||= 'PE'
			@link_ver_maj ||= 1
			@link_ver_min ||= 0
			@sect_align   ||= 0x1000
			align = proc { |sz| EncodedData.align_size(sz, @sect_align) }
			@code_size    ||= coff.sections.find_all { |s| s.characteristics.include? 'CONTAINS_CODE' }.inject(0) { |sum, s| sum + align[s.virtsize] }
			@data_size    ||= coff.sections.find_all { |s| s.characteristics.include? 'CONTAINS_DATA' }.inject(0) { |sum, s| sum + align[s.virtsize] }
			@udata_size   ||= coff.sections.find_all { |s| s.characteristics.include? 'CONTAINS_UDATA' }.inject(0) { |sum, s| sum + align[s.virtsize] }
			@entrypoint = Expression[@entrypoint, :-, coff.label_at(coff.encoded, 0)] if @entrypoint.kind_of? String
			@entrypoint   ||= 0
			@base_of_code ||= (Expression[coff.label_at(coff.sections.find { |s| s.characteristics.include? 'CONTAINS_CODE' }.encoded, 0), :-, coff.label_at(coff.encoded, 0)] rescue 0)
			@base_of_data ||= (Expression[coff.label_at(coff.sections.find { |s| s.characteristics.include? 'CONTAINS_DATA' }.encoded, 0), :-, coff.label_at(coff.encoded, 0)] rescue 0)
			@image_base   ||= coff.label_at(coff.encoded, 0)
			@file_align   ||= 0x200
			@os_ver_maj   ||= 4
			@os_ver_min   ||= 0
			@img_ver_maj  ||= 0
			@img_ver_min  ||= 0
			@subsys_maj   ||= 4
			@subsys_min   ||= 0
			@reserved     ||= 0
			@image_size   ||= coff.new_label('image_size')
			@headers_size ||= coff.new_label('headers_size')
			@checksum     ||= coff.new_label('checksum')
			@subsystem    ||= 'WINDOWS_GUI'
			@dll_characts ||= 0
			@stack_reserve||= 0x100000
			@stack_commit ||= 0x1000
			@heap_reserve ||= 0x100000
			@heap_commit  ||= 0x1000
			@ldrflags     ||= 0
			@numrva       ||= DIRECTORIES.length
		end
	end

	class Section
		# encodes a section header
		def encode(coff)
			set_default_values(coff)

			EncodedData.new(@name[0, 8].ljust(8, "\0")) <<
			coff.encode_word(@virtsize) <<
			coff.encode_word(@virtaddr) <<
			coff.encode_word(@rawsize) <<
			coff.encode_word(@rawaddr) <<
			coff.encode_word(@relocaddr) <<
			coff.encode_word(@linenoaddr) <<
			coff.encode_half(@relocnr) <<
			coff.encode_half(@linenonr) <<
			coff.encode_word(coff.bits_from_hash(@characteristics, SECTION_CHARACTERISTIC_BITS))
		end

		# find good default values for section header members, defines rawaddr/rawsize as new_label for later fixup
		def set_default_values(coff)
			@name     ||= ''
			@virtsize ||= @encoded.virtsize
			@virtaddr ||= Expression[coff.label_at(@encoded, 0, 'sect_start'), :-, coff.label_at(coff.encoded, 0)]
			@rawsize  ||= coff.new_label('sect_rawsize')
			@rawaddr  ||= coff.new_label('sect_rawaddr')
			@relocaddr ||= 0
			@linenoaddr ||= 0
			@relocnr  ||= 0
			@linenonr ||= 0
			@characteristics ||= 0
		end
	end

	class ExportDirectory
		# encodes an export directory
		def encode(coff)
			set_default_values coff

			edata = {}
			%w[edata addrtable namptable ord_table libname nametable].each { |name|
				edata[name] = EncodedData.new
			}
			label = proc { |n| coff.label_at(edata[n], 0, n) }
			rva = proc { |n| Expression[label[n], :-, coff.label_at(coff.encoded, 0)] }
			rva_end = proc { |n| Expression[[label[n], :-, coff.label_at(coff.encoded, 0)], :+, edata[n].virtsize] }

			edata['edata'] <<
			coff.encode_word(@reserved) <<
			coff.encode_word(@timestamp) <<
			coff.encode_half(@version_major) <<
			coff.encode_half(@version_minor) <<
			coff.encode_word(rva['libname']) <<
			coff.encode_word(@ordinal_base) <<
			coff.encode_word(@exports.length) <<
			coff.encode_word(@exports.find_all { |e| e.name }.length) <<
			coff.encode_word(rva['addrtable']) <<
			coff.encode_word(rva['namptable']) <<
			coff.encode_word(rva['ord_table'])

			edata['libname'] << @libname << 0

			# TODO handle e.ordinal (force export table order, or invalidate @ordinal)
			@exports.sort_by { |e| e.name.to_s }.each { |e|
				if e.forwarder_lib
					edata['addrtable'] << coff.encode_word(rva_end['nametable'])
					edata['nametable'] << e.forwarder_lib << ?. <<
					if not e.forwarder_name
						"##{e.forwarder_ordinal}"
					else
						e.forwarder_name
					end << 0
				else
					edata['addrtable'] << coff.encode_word(Expression[e.target, :-, coff.label_at(coff.encoded, 0)])
				end
				if e.name
					edata['ord_table'] << coff.encode_half(edata['addrtable'].virtsize/4 - @ordinal_base)
					edata['namptable'] << coff.encode_word(rva_end['nametable'])
					edata['nametable'] << e.name << 0
				end
			}
			
			# sorted by alignment directives
			%w[edata addrtable namptable ord_table libname nametable].inject(EncodedData.new) { |ed, name| ed << edata[name] }
		end

		def set_default_values(coff)
			@reserved ||= 0
			@timestamp ||= Time.now.to_i
			@version_major ||= 0
			@version_minor ||= 0
			@libname ||= 'metalib'
			@ordinal_base ||= 1
		end
	end

	class ImportDirectory
		# encodes all import directories + iat
		def self.encode(coff, ary)
			edata = {}
			ary.each { |i| i.encode(coff, edata) }

			it = edata['idata'] <<
			coff.encode_word(0) <<
			coff.encode_word(0) <<
			coff.encode_word(0) <<
			coff.encode_word(0) <<
			coff.encode_word(0) <<
			edata['ilt'] <<
			edata['nametable']

			iat = edata['iat']	# why not fragmented ?

			[it, iat]
		end

		# encodes an import directory + iat + names in the edata hash received as arg
		def encode(coff, edata)
			%w[idata iat ilt nametable].each { |name| edata[name] ||= EncodedData.new }
			# edata['ilt'] = edata['iat']
			label = proc { |n| coff.label_at(edata[n], 0, n) }
			rva = proc { |n| Expression[label[n], :-, coff.label_at(coff.encoded, 0)] }
			rva_end = proc { |n| Expression[[label[n], :-, coff.label_at(coff.encoded, 0)], :+, edata[n].virtsize] }

			edata['idata'] <<
			coff.encode_word(rva_end['ilt']) <<
			coff.encode_word(@timestamp ||= 0) <<
			coff.encode_word(@firstforwarder ||= 0) <<
			coff.encode_word(rva_end['nametable']) <<
			coff.encode_word(rva_end['iat'])

			edata['nametable'] << @libname << 0

			ord_mask = 1 << (coff.optheader.signature == 'PE+' ? 63 : 31)
			@imports.each { |i|
				if i.ordinal
					edata['ilt'] << coff.encode_xword(Expression[i.ordinal, :|, ord_mask])
					edata['iat'] << coff.encode_xword(Expression[i.ordinal, :|, ord_mask])
				else
					edata['iat'].export[i.name] = edata['iat'].virtsize

					edata['nametable'].align 2
					edata['ilt'] << coff.encode_xword(rva_end['nametable'])
					edata['iat'] << coff.encode_xword(rva_end['nametable'])
					edata['nametable'] << coff.encode_half(i.hint || 0) << i.name << 0
				end
			}
			edata['ilt'] << coff.encode_xword(0)
			edata['iat'] << coff.encode_xword(0)
		end
	end

	class RelocationTable
		# encodes a COFF relocation table
		def encode(coff)
			setup_default_values coff

			# encode table header
			rel = coff.encode_word(@base_addr) << coff.encode_word(8 + 2*@relocs.length)

			# encode table content
			@relocs.each { |r|
				raw = coff.int_from_hash(r.type, BASE_RELOCATION_TYPE)
				raw = (raw << 12) | (r.offset & 0xfff)
				rel << coff.encode_half(raw)
			}

			rel
		end

		def setup_default_values(coff)
			# @base_addr is an rva
			@base_addr = Expression[@base_addr, :-, coff.label_at(coff.encoded, 0)] if @base_addr.kind_of? String

			# align relocation table size
			if @relocs.length % 2 != 0
				r = Relocation.new
				r.type = 0
				r.offset = 0
				@relocs << r
			end
		end
	end

	class ResourceDirectory
		# compiles ressource directories
		def encode(coff, edata = nil)
			if not edata
				# init recursion
				edata = {}
				subtables = %w[table names dataentries data]
				subtables.each { |n| edata[n] = EncodedData.new }
				encode(coff, edata)
				return subtables.inject(EncodedData.new) { |sum, n| sum << edata[n] }
			end

			label = proc { |n| coff.label_at(edata[n], 0, n) }
			# data 'rva' are real rvas (from start of COFF)
			rva_end = proc { |n| Expression[[label[n], :-, coff.label_at(coff.encoded, 0)], :+, edata[n].virtsize] }
			# names and table 'rva' are relative to the beginning of the resource directory
			off_end = proc { |n| Expression[[label[n], :-, coff.label_at(edata['table'], 0)], :+, edata[n].virtsize] }

			# build name_w if needed
			@entries.each { |e| e.name_w = e.name.unpack('C*').pack('v*') if e.name and not e.name_w }

			# fixup forward references to us, as subdir
			edata['table'].fixup @curoff_label => edata['table'].virtsize if defined? @curoff_label

			# encode resource directory table
			edata['table'] <<
			coff.encode_word(@characteristics ||= 0) <<
			coff.encode_word(@timestamp ||= 0) <<
			coff.encode_half(@major_version ||= 0) <<
			coff.encode_half(@minor_version ||= 0) <<
			coff.encode_half(@entries.find_all { |e| e.name_w }.length) <<
			coff.encode_half(@entries.find_all { |e| e.id }.length)

			# encode entries, sorted by names nocase, then id
			@entries.sort_by { |e| e.name_w ? [0, e.name_w.downcase] : [1, e.id] }.each { |e|
				if e.name_w
					edata['table'] << coff.encode_word(Expression[off_end['names'], :|, 1 << 31])
					edata['names'] << coff.encode_half(e.name_w.length/2) << e.name_w
				else
					edata['table'] << coff.encode_word(e.id)
				end

				if e.subdir
					e.subdir.curoff_label = coff.new_label('rsrc_curoff')
					edata['table'] << coff.encode_word(Expression[e.subdir.curoff_label, :|, 1 << 31])
				else # data entry
					edata['table'] << coff.encode_word(off_end['dataentries'])

					edata['dataentries'] <<
					coff.encode_word(rva_end['data']) <<
					coff.encode_word(e.data.length) <<
					coff.encode_word(e.codepage || 0) <<
					coff.encode_word(e.reserved || 0)

					edata['data'] << e.data
				end
			}

			# recurse
			@entries.find_all { |e| e.subdir }.each { |e| e.subdir.encode(coff, edata) }
		end
	end


	def encode_uchar(w)  Expression[w].encode(:u8,  @endianness) end
	def encode_half(w)   Expression[w].encode(:u16, @endianness) end
	def encode_word(w)   Expression[w].encode(:u32, @endianness) end
	def encode_xword(w)  Expression[w].encode((@optheader.signature == 'PE+' ? :u64 : :u32), @endianness) end


	# adds a new compiler-generated section
	def encode_append_section(s)
		if (s.virtsize || s.encoded.virtsize) < 4096
			# find section to merge with
			# XXX check following sections for hardcoded base address ?

			char = s.characteristics.dup
			secs = @sections.dup
			# do not merge non-discardable in discardable
			if not char.delete 'MEM_DISCARDABLE'
				secs.delete_if { |ss| ss.characteristics.include? 'MEM_DISCARDABLE' }
			end
			# do not merge shared w/ non-shared
			if char.delete 'MEM_SHARED'
				secs.delete_if { |ss| not ss.characteristics.include? 'MEM_SHARED' }
			else
				secs.delete_if { |ss| ss.characteristics.include? 'MEM_SHARED' }
			end
			secs.delete_if { |ss| ss.virtsize.kind_of?(Integer) or ss.rawsize.kind_of?(Integer) }

			# try to find superset of characteristics
			if target = secs.find { |ss| (ss.characteristics & char) == char }
				target.encoded << s.encoded
			else
				@sections << s
			end
		else
			@sections << s
		end
	end

	# encodes the export table as a new section, updates directory['export_table']
	def encode_exports
		edata = @export.encode self

		# must include name tables (for forwarders)
		@directory['export_table'] = [label_at(edata, 0, 'export_table'), edata.virtsize]

		s = Section.new
		s.name = '.edata'
		s.encoded = edata
		s.characteristics = %w[MEM_READ]
		encode_append_section s
	end

	# encodes the import tables as a new section, updates directory['import_table'] and directory['iat']
	def encode_imports
		idata, iat = ImportDirectory.encode(self, @imports)

		@directory['import_table'] = [label_at(idata, 0, 'idata'), idata.virtsize]

		s = Section.new
		s.name = '.idata'
		s.encoded = idata
		s.characteristics = %w[MEM_READ MEM_WRITE MEM_DISCARDABLE]
		encode_append_section s

		@directory['iat'] = [label_at(iat, 0, 'iat'), iat.virtsize]
	
		s = Section.new
		s.name = '.iat'
		s.encoded = iat
		s.characteristics = %w[MEM_READ MEM_WRITE]
		encode_append_section s
	end

	# encodes relocation tables in a new section .reloc, updates @directory['base_relocation_table']
	def encode_relocs
		if @relocations.empty?
			rt = RelocationTable.new
			rt.base_addr = 0
			rt.relocs = []
			@relocations << rt
		end
		relocs = @relocations.inject(EncodedData.new) { |edata, rt| edata << rt.encode(self) }

		@directory['base_relocation_table'] = [label_at(relocs, 0, 'reloc_table'), relocs.virtsize]

		s = Section.new
		s.name = '.reloc'
		s.encoded = relocs
		s.characteristics = %w[MEM_READ MEM_DISCARDABLE]
		encode_append_section s
	end

	# creates the @relocations from sections.encoded.reloc
	def create_relocation_tables
		@relocations = []

		# create a fake binding with all exports, to find only-image_base-dependant relocs targets
		# not foolproof, but work standard cases
		startaddr = curaddr = Expression[label_at(@encoded, 0, 'coff_start')]
		binding = {}
		@sections.each { |s|
			binding.update s.encoded.binding(curaddr)
			curaddr = Expression[curaddr, :+, s.encoded.virtsize]
		}

		# for each section.encoded, make as many RelocationTables as needed
		@sections.each { |s|

			# rt.base_addr temporarily holds the offset from section_start, and is fixed up to rva before '@reloc << rt'
			rt = RelocationTable.new

			s.encoded.reloc.each { |off, rel|
				# check that the relocation looks like "program_start + integer" when bound using the fake binding
				# XXX allow :i32 etc
				if rel.endianness == @endianness and (rel.type == :u32 or rel.type == :u64) and \
				Expression[rel.target, :-, startaddr].bind(binding).reduce.kind_of? Integer
					# winner !

					# build relocation
					r = RelocationTable::Relocation.new
					r.offset = off & 0xfff
					r.type = { :u32 => 'HIGHLOW', :u64 => 'DIR64' }[rel.type]

					# check if we need to start a new relocation table
					if rt.base_addr and (rt.base_addr & ~0xfff) != (off & ~0xfff)
						rt.base_addr = Expression[[label_at(s.encoded, 0, 'sect_start'), :-, label_at(@encoded, 0, 'coff_start')], :+, rt.base_addr]
						@relocations << rt
						rt = RelocationTable.new
					end

					# initialize reloc table base address if needed
					if not rt.base_addr
						rt.base_addr = off & ~0xfff
					end

					(rt.relocs ||= []) << r
				else
					puts "W: COFF: Ignoring weird relocation #{rel.inspect} when building relocation tables" if $DEBUG
				end
			}

			if rt and rt.relocs
				rt.base_addr = Expression[[label_at(s.encoded, 0, 'sect_start'), :-, label_at(@encoded, 0, 'coff_start')], :+, rt.base_addr]
				@relocations << rt
			end
		}
	end

	def encode_resource
		res = @resource.encode self

		@directory['resource_table'] = [label_at(res, 0, 'resource_table'), res.virtsize]

		s = Section.new
		s.name = '.rsrc'
		s.encoded = res
		s.characteristics = %w[MEM_READ]
		encode_append_section s
	end

	# appends the header/optheader/directories/section table to @encoded
	# initializes some flags based on the target arg ('exe' / 'dll' / 'kmod' / 'obj')
	def encode_header(target = 'dll')
		# setup header flags
		tmp = %w[LINE_NUMS_STRIPPED LOCAL_SYMS_STRIPPED DEBUG_STRIPPED] +
			case target
			when 'exe':  %w[EXECUTABLE_IMAGE]
			when 'dll':  %w[EXECUTABLE_IMAGE DLL]
			when 'kmod': %w[EXECUTABLE_IMAGE]
			when 'obj':  []
			end
		tmp << 'x32BIT_MACHINE'		# XXX
		tmp << 'RELOCS_STRIPPED' if not @directory['base_relocation_table']
		@header.characteristics ||= tmp

		@optheader.subsystem ||= case target
		when 'exe', 'dll': 'WINDOWS_GUI'
		when 'kmod': 'NATIVE'
		end
		@optheader.dll_characts = ['DYNAMIC_BASE'] if @directory['base_relocation_table']

		# encode section table, add CONTAINS_* flags from other characteristics flags
		s_table = EncodedData.new
		@sections.each { |s|
			if s.characteristics.kind_of? Array and s.characteristics.include? 'MEM_READ'
				if s.characteristics.include? 'MEM_EXECUTE'
					s.characteristics |= ['CONTAINS_CODE']
				elsif s.encoded
					if s.encoded.rawsize == 0
						s.characteristics |= ['CONTAINS_UDATA']
					else
						s.characteristics |= ['CONTAINS_DATA']
					end
				end
			end
			s.rawaddr = nil if s.rawaddr.kind_of? Integer	# XXX allow to force rawaddr ?
			s_table << s.encode(self)
		}

		# encode optional header
		@optheader.headers_size = nil
		@optheader.image_size = nil
		@optheader.numrva = nil
		opth = @optheader.encode(self)

		# encode header
		@header.num_sect = nil
		@header.size_opthdr = nil
		@encoded << @header.encode(self, opth) << opth << s_table
	end

	# append the section bodies to @encoded, and link the resulting binary
	def encode_sections_fixup
		@encoded.align @optheader.file_align
		if @optheader.headers_size.kind_of? String
			@encoded.fixup! @optheader.headers_size => @encoded.virtsize
			@optheader.headers_size = @encoded.virtsize
		end

		baseaddr = @optheader.image_base.kind_of?(Integer) ? @optheader.image_base : 0x400000
		binding = @encoded.binding(baseaddr)

		curaddr = baseaddr + @optheader.headers_size
		@sections.each { |s|
			# align
			curaddr = EncodedData.align_size(curaddr, @optheader.sect_align)
			if s.rawaddr.kind_of? String
				@encoded.fixup! s.rawaddr => @encoded.virtsize
				s.rawaddr = @encoded.virtsize
			end
			if s.virtaddr.kind_of? Integer
				raise "E: COFF: cannot encode section #{s.name}: hardcoded address too short" if curaddr > baseaddr + s.virtaddr
				curaddr = baseaddr + s.virtaddr
			end
			binding.update s.encoded.binding(curaddr)
			curaddr += s.virtsize

			pre_sz = @encoded.virtsize
			@encoded << s.encoded[0, s.encoded.rawsize]
			@encoded.align @optheader.file_align
			if s.rawsize.kind_of? String
				@encoded.fixup! s.rawsize => (@encoded.virtsize - pre_sz)
				s.rawsize = @encoded.virtsize - pre_sz
			end
		}

		# not aligned
		binding[@optheader.image_size] = curaddr - baseaddr if @optheader.image_size.kind_of? String

		@encoded.fill
		@encoded.fixup! binding

		if @optheader.checksum.kind_of? String
			checksum = 0 # TODO checksum
			@encoded.fixup @optheader.checksum => checksum
			@optheader.checksum = checksum
		end
	end

	# encode a COFF file, building export/import/reloc tables if needed
	# creates the base relocation tables (need for references to IAT not known before)
	def encode(target = 'exe')
		@encoded = EncodedData.new
		label_at(@encoded, 0, 'coff_start')
		encode_exports if @export
		encode_imports if @imports
		encode_resource if @resource
		create_relocation_tables if target != 'exe'
		encode_relocs if @relocations
		encode_header(target)
		encode_sections_fixup
		@encoded.data
	end

	def self.from_program(program)
		coff = new
		coff.endianness = program.cpu.endianness

		coff.header.machine = 'I386' if program.cpu.kind_of? Ia32 rescue nil
		coff.optheader.entrypoint = 'entrypoint'

		program.sections.each { |ps|
			s = Section.new
			s.name = ps.name
			s.encoded = ps.encoded
			s.characteristics = {
				:exec => 'MEM_EXECUTE', :read => 'MEM_READ', :write => 'MEM_WRITE', :discard => 'MEM_DISCARDABLE', :shared => 'MEM_SHARED'
			}.values_at(*ps.mprot).compact
			coff.sections << s
			# relocs
		}

		program.import.each { |libname, list|
			coff.imports ||= []
			id = ImportDirectory.new
			id.libname = libname
			id.imports = []
			list.each { |name, thunk|
				i = ImportDirectory::Import.new
				i.name = name
				id.imports << i
			}
			coff.imports << id
		}

		if not program.export.empty?
			coff.export = ExportDirectory.new
			coff.export.libname = 'kikoo'
			coff.export.exports = []
			program.export.each { |name, label|
				e = ExportDirectory::Export.new
				e.name = name
				e.target = label
				coff.export.exports << e
			}
		end

		coff
	end
end
end

__END__
	def encode_fix_checksum(data, endianness = :little)
		# may not work with overlapping sections
		off = data[0x3c, 4].unpack(long).first
		off += 4

		# read some header information
		csumoff = off + 0x14 + 0x40
		secoff  = off + 0x14 + data[off+0x10, 2].unpack(short).first
		secnum  = data[off+2, 2].unpack(short).first

		sum = 0
		flen = 0

		# header
		# patch csum at 0
		data[csumoff, 4] = [0].pack(long)
		curoff  = 0
		cursize = data[off+0x14+0x3c, 4].unpack(long).first
		data[curoff, cursize].unpack(shorts).each { |s|
			sum += s
			sum = (sum & 0xffff) + (sum >> 16) if (sum >> 16) > 0
		}
		flen += cursize

		# sections
		secnum.times { |n|
			cursize, curoff = data[secoff + 0x28*n + 0x10, 8].unpack(long + long)
			data[curoff, cursize].unpack(shorts).each { |s|
				sum += s
				sum = (sum & 0xffff) + (sum >> 16) if (sum >> 16) > 0
			}
			flen += cursize
		}
		sum += flen

		# patch good value
		data[csumoff, 4] = [sum].pack(long)
	end
