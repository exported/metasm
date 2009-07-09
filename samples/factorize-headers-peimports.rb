#    This file is part of Metasm, the Ruby assembly manipulation suite
#    Copyright (C) 2009 Yoann GUILLOT
#
#    Licence is LGPL, see LICENCE in the top-level directory

#
# this exemple illustrates the use of the cparser/preprocessor #factorize functionnality:
# it generates code that references to the functions imported by a windows executable
# usage: factorize-imports.rb <exe> <exe2> <path to visual studio installation> [<additional func names>... ^<func to exclude>]
#

require 'metasm'
include Metasm

require 'optparse'
opts = { :hdrs => [], :defs => {}, :path => [], :exe => [] }
OptionParser.new { |opt|
	opt.on('-o outfile') { |f| opts[:outfile] = f }
	opt.on('-H additional_header') { |f| opts[:hdrs] << f }
	opt.on('-e exe', '--exe executable') { |f| opts[:exe] << f }
	opt.on('-I path', '--includepath path') { |f| opts[:path] << f }
	opt.on('-D var') { |f| k, v = f.split('=', 2) ; opts[:defs].update k => (v || '') }
	opt.on('--ddk') { opts[:ddk] = true }
	opt.on('--vspath path') { |f| opts[:vspath] = f }
}.parse!(ARGV)

ARGV.delete_if { |e|
	next if not File.file? e
	opts[:exe] << e
}

if opts[:vspath] ||= ARGV.shift
	opts[:vspath] = opts[:vspath].tr('\\', '/')
	opts[:vspath] = opts[:vspath].chop if opts[:vspath][-1] == ?/
	if opts[:ddk]
		opts[:path] << opts[:vspath]
	else
		opts[:vspath] = opts[:vspath][0...-3] if opts[:vspath][-3..-1] == '/VC'
		opts[:path] << (opts[:vspath]+'/VC/platformsdk/include') << (opts[:vspath]+'/VC/include')
	end
end

funcnames = opts[:exe].map { |e|
	pe = PE.decode_file_header(e)
	pe.decode_imports
	pe.imports.map { |id| id.imports.map { |i| i.name } }
}.flatten.compact.uniq.sort

ARGV.each { |n|
	if n[0] == ?! or n[0] == ?- or n[0] == ?^
		funcnames.delete n[1..-1]
	else
		funcnames |= [n]
	end
}

src = <<EOS + opts[:hdrs].to_a.map { |h| "#include <#{h}>\n" }.join
#if DDK
 #define NO_INTERLOCKED_INTRINSICS
 typedef struct _CONTEXT CONTEXT;	// needed by ntddk.h, but this will pollute the factorized output..
 typedef CONTEXT *PCONTEXT;
 #define dllimport stdcall		// wtff
 #include <ntddk.h>
 #include <stdio.h>
#else
 #define WIN32_LEAN_AND_MEAN
 #include <windows.h>
 #include <winternl.h>
#endif
EOS

parser = Ia32.new.new_cparser
parser.prepare_visualstudio
pp = parser.lexer
pp.warn_redefinition = false
pp.define('_WIN32_WINNT', '0x0600')
pp.define('DDK') if opts[:ddk]
pp.include_search_path = opts[:path]
opts[:defs].each { |k, v| pp.define k, v }
parser.factorize_init
parser.parse src


# delete imports not present in the header files
funcnames.delete_if { |f|
	if not parser.toplevel.symbol[f]
		puts "// #{f.inspect} is not defined in the headers"
		true
	end
}

parser.parse "void *fnptr[] = { #{funcnames.map { |f| '&'+f }.join(', ')} };"

outfd = (opts[:outfile] ? File.open(opts[:outfile], 'w') : $stdout)
outfd.puts parser.factorize_final
outfd.close
