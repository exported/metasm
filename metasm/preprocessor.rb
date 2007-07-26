#    This file is part of Metasm, the Ruby assembly manipulation suite
#    Copyright (C) 2007 Yoann GUILLOT
#
#    Licence is LGPL, see LICENCE in the top-level directory


require 'metasm/main'
require 'metasm/parse'

module Metasm
class Token
	# array of macros name
	attr_accessor :expanded_from
end

class Preprocessor
	class Macro
		attr_accessor :name, :body

		def initialize(name)
			@name = name
			@body = []
			@args = nil
			@varargs = false	# macro is of type #define foo(a1, ...)
		end

		# applies a preprocessor macro
		# parses arguments if needed 
		# returns an array of tokens
		# macros are lazy
		# fills token.expanded_from
		def apply(lexer, name)
			if @args
				# if defined with arg list (even empty), then must be followed by parenthesis, otherwise do not replace
				unr = []
				while tok = lexer.readtok_nopp and tok.type == :space
					unr << tok
				end
				if not tok or tok.type != :punct or tok.raw != '('
					lexer.unreadtok tok
					unr.reverse_each { |t| lexer.unreadtok t }
					tok = name.dup
						(tok.expanded_from ||= []) << name.raw
					return [tok]
				end
				args = []
				# each argument is any token sequence
				# if it includes an '(' then find the matching ')', whatever is inside (handle nesting)
				# arg cannot include ',' in the top-level
				# convert any space/eol sequence to a single space, strips them at begin/end of argument
				loop do
					arg = []
					nest = 0
					loop do
						raise name, 'unterminated arg list' if not tok = lexer.readtok
						case tok.type
						when :eol, :space
							next if arg.last and arg.last.type == :space
							tok = tok.dup
							tok.type = :space
							tok.raw = ' '
						when :punct
							case tok.raw
							when ',': break if nest == 0
							when ')': break if nest == 0 ; nest -= 1
							when '(': nest += 1
							end
						end
						arg << tok
					end
					arg.pop if arg.last and arg.last.type == :space
					args << arg
					break if tok.raw == ')'
				end
				if @varargs
					raise name, 'invalid argument count' if args.length < @args.length
					virg = name.dup
					virg.type = :punct
					virg.raw = ','
					va = args[@args.length..-1].map { |a| a + [virg] }.flatten
					va.pop
				else
					raise name, 'invalid argument count' if args.length != @args.length
				end

				# map name => token list
				hargs = @args.zip(args).inject({}) { |h, (af, ar)| h.update af.raw => ar }
				hargs['__VA_ARGS__'] = va if va
			else
				hargs = {}
			end

			# apply macro
			res = []
			b = @body.reverse
			hargs.each_value { |a| a.map! { |t| t = t.dup ; (t.expanded_from ||= []) << name.raw ; t } }
			while t = b.pop
				t = t.dup
				t.expanded_from = (name.expanded_from || []) << name.raw
				if a = hargs[t.raw]
					res.pop if res.last and res.last.type == :space and a.first and a.first.type == :space
					res.concat a
					next
				elsif t.type == :punct and t.raw == '##'
					# the '##' operator: concat the next token to the last in body
					t = b.pop
					t = b.pop while t and t.type == :space
					res.pop while res.last and res.last.type == :space
					if not a = hargs[t.raw]
						a = [t]
					end
					if @varargs and t.raw == '__VA_ARGS__' and res.last and res.last.type == :punct and res.last.raw == ','
						if args.length == @args.length
							# pop last , if no vararg passed
							# XXX poof(1, 2,) != poof(1, 2)
							res.pop
						else
							# allow merging with ',' without warning
							res.concat a
						end
					else
						a = a[1..-1] if a.first and a.first.type == :space
						if not res.last or res.last.type != :string or not a.first or a.first.type != :string
							puts "W: preprocessor: in #{name.raw}: cannot merge token #{res.last.raw} with #{a.first ? a.first.raw : 'nil'}" if not a.first or (a.first.raw != '.' and res.last.raw != '.') if $VERBOSE
							res.concat a
						else
							res[-1] = res[-1].dup
							res.last.raw << a.first.raw
							res.concat a[1..-1]
						end
					end
					next

				elsif @args and t.type == :punct and t.raw == '#'
					# the '#' operator: transforms an argument to the quotedstring of its value
					t = b.pop.dup
					t = b.pop.dup if t and t.type == :space
					raise name, "internal error, bad macro:\n #{dump}\n near #{t.inspect}" if not t or t.type == :space or not hargs[t.raw]	# should have been filtered on parse_definition
					a = hargs[t.raw]
					t.type = :quoted
					t.value = a.map { |aa| aa.raw }.join
					t.value = t.value[1..-1] if t.value[0] == ?\ 	# delete leading space
					t.raw = t.value.inspect
					res << t
					next
				end
				t.backtrace += name.backtrace[-2, 2]	# don't modify inplace
				res << t
			end
			res
		end

		# parses the argument list and the body from lexer
		# converts # + # to ## in body
		def parse_definition(lexer)
			varg = nil
			if tok = lexer.readtok_nopp and tok.type == :punct and tok.raw == '('
				@args = []
				loop do
					nil while tok = lexer.readtok_nopp and tok.type == :space
					# check '...'
					if tok and tok.type == :punct and tok.raw == '.'
						t1 = lexer.readtok_nopp
						t2 = lexer.readtok_nopp
						t3 = lexer.readtok_nopp
						t3 = lexer.readtok_nopp while t3 and t3.type == :space
						raise @name, 'booh'  if not t1 or t1.type != :punct or t1.raw != '.' or
									not t2 or t2.type != :punct or t2.raw != '.' or
									not t3 or t3.type != :punct or t3.raw != ')'
						@varargs = true
						break
					end
					break if tok and tok.type == :punct and tok.raw == ')' and @args.empty?	# allow empty list
					raise @name, 'invalid arg definition' if not tok or tok.type != :string
					@args << tok
					nil while tok = lexer.readtok_nopp and tok.type == :space
					# check '...'
					if tok and tok.type == :punct and tok.raw == '.'
						t1 = lexer.readtok_nopp
						t2 = lexer.readtok_nopp
						t3 = lexer.readtok_nopp
						t3 = lexer.readtok_nopp while t3 and t3.type == :space
						raise @name, 'booh'  if not t1 or t1.type != :punct or t1.raw != '.' or
									not t2 or t2.type != :punct or t2.raw != '.' or
									not t3 or t3.type != :punct or t3.raw != ')'
						@varargs = true
						varg = @args.pop.raw
						break
					end
					raise @name, 'invalid arg separator' if not tok or tok.type != :punct or (tok.raw != ')' and tok.raw != ',')
					break if tok.raw == ')'
				end
			else lexer.unreadtok tok
			end

			nil while tok = lexer.readtok_nopp and tok.type == :space
			lexer.unreadtok tok

			while tok = lexer.readtok_nopp
				tok = tok.dup
				case tok.type
				when :eol
					lexer.unreadtok tok
					break
				when :space
					next if @body.last and @body.last.type == :space
					tok.raw = ' '
				when :string
					tok.raw = '__VA_ARGS__' if varg and tok.raw == varg
				when :punct
					if tok.raw == '#'
						ntok = lexer.readtok_nopp
						if ntok and ntok.type == :punct and ntok.raw == '#'
							tok.raw << '#'
						else
							lexer.unreadtok ntok
						end
					end
				end
				@body << tok
			end
			@body.pop if @body.last and @body.last.type == :space

			# check macro is correct
			invalid_body = nil
			if (@body[-1] and @body[-1].raw == '##') or (@body[0] and @body[0].raw == '##')
				invalid_body ||= 'cannot have ## at begin or end of macro body'
				lexer.definition.delete(name.raw)
			end
			if @args
				if @args.map { |a| a.raw }.uniq.length != @args.length
					invalid_body ||= 'duplicate macro parameter'
				end
				@body.each_with_index { |tok, i|
					if tok.type == :punct and tok.raw == '#'
						a = @body[i+1]
						a = @body[i+2] if not a or a.type == :space
						if not a.type == :string or (not @args.find { |aa| aa.raw == a.raw } and (not @varargs or a.raw != '__VA_ARGS__'))
							invalid_body ||= 'cannot have # followed by non-argument'
						end
					end
				}
				
			end
			if invalid_body
				puts "W: #{lexer.filename}:#{lexer.lineno}, in #{@name.raw}: #{invalid_body}" if $VERBOSE
				lexer.definition.delete(name.raw)
			end
		end

		def dump
			str = "// from #{@name.backtrace[-2, 2] * ':'}\n"
			str << "#define #{@name.raw}"
			if @args
				str << '(' << (@args.map { |t| t.raw } + (@varargs ? ['...'] : [])).join(', ') << ')'
			end
			str << ' ' << @body.map { |t| t.raw }.join << "\n"
		end
	end

	# special object, handles __FILE__ and __LINE__ macros
	class SpecialMacro
		def name
		end
		def body
			[]
		end

		def apply(lexer, name)
			tok = name.dup
			(tok.expanded_from ||= []) << name.raw
			case name.raw
			when '__FILE__'
				# keep tok.raw
				tok.type = :quoted
				tok.value = tok.backtrace[-2].to_s
			when '__LINE__'
				# keep tok.raw
				tok.type = :string
				tok.value = tok.backtrace[-1]
			else raise name, 'internal error'
			end
			[tok]
		end
	end

	attr_accessor :pragma_pack
	# visual studio default
	def default_pragma_pack_value
		8
	end

	def initialize
		@queue = []
		@backtrace = []
		@definition = {'__FILE__' => SpecialMacro.new, '__LINE__' => SpecialMacro.new}
		@include_search_path = @@include_search_path
		# stack of :accept/:discard/:discard_all/:testing, represents the current nesting of #if..#endif
		@ifelse_nesting = []
		@text = ''
		@pos = 0
		@filename = nil
		@lineno = nil
		@pragma_pack = default_pragma_pack_value
		# TODO setup standard macro names ? see $(gcc -dM -E - </dev/null)
	end

	# outputs the preprocessed source
	def dump
		while not eos?
			print readtok.raw rescue nil
		end
	end

	# preprocess text, and retrieve all macros defined in #included <files> and used in the text
	# returns a C source-like string
	def trace_macros(text, filename='unknown', lineno=1)
		feed(text, filename, lineno)
		@traced_macros = []
		readtok while not eos?

		depend = {}
		# build dependency graph (we can output macros in any order, but it's more human-readable)
		walk = proc { |mname|
			depend[mname] ||= []
			@definition[mname].body.each { |t|
				name = t.raw
				if @definition[name]
					depend[mname] << name
					if not depend[name]
						depend[name] = []
						walk[name]
					end
				end
			}
		}
		@traced_macros.each { |mname| walk[mname] }

		res = []
		while not depend.empty?
			leafs = depend.keys.find_all { |k| depend[k].empty? }
			leafs.each { |l|
				res << @definition[l].dump
				depend.delete l
			}
			depend.each_key { |k| depend[k] -= leafs }
		end
		res.join("\n")
	end

	# starts a new lexer, with the specified initial filename/line number (for backtraces)
	def feed(text, filename='unknown', lineno=1)
		raise ParseError, 'cannot start new text, did not finish current source' if not eos?
		@text = text
		# @filename[-1] used in trace_macros to distinguish generic/specific files
		@filename = "\"#{filename}\""
		@lineno = lineno
		@pos = 0
	end

	Trigraph = {	?= => ?#, ?) => ?], ?! => ?|,
			?( => ?[, ?' => ?^, ?> => ?},
			?/ => ?\\,?< => ?{, ?- => ?~ }
	
	# reads one character from self.text
	# updates self.lineno
	# handles trigraphs and \-continued lines
	def getchar
		@ungetcharpos = @pos
		@ungetcharlineno = @lineno
		c = @text[@pos]
		@pos += 1

		# check trigraph
		if c == ?? and @text[@pos] == ?? and Trigraph[@text[@pos+1]]
			puts "can i has trigraf plox ??#{c.chr} (#@filename:#@lineno)" if $VERBOSE
			c = Trigraph[@text[@pos+1]]
			@pos += 2
		end

		# check line continuation
		if c == ?\\ and (@text[@pos] == ?\n or (@text[@pos] == ?\r and @text[@pos+1] == ?\n))
			@lineno += 1
			@pos += 1 if @text[@pos] == ?\r
			@pos += 1
			return getchar
		end

		if c == ?\r and @text[@pos] == ?\n
			@pos += 1
			c = ?\n
		end

		# update lineno
		if c == ?\n
			@lineno += 1
		end

		c
	end

	def ungetchar
		@pos = @ungetcharpos
		@lineno = @ungetcharlineno
	end

	# returns true if no more data is available
	def eos?
		@pos >= @text.length and @queue.empty? and @backtrace.empty?
	end

	# push back a token, will be returned on the next readtok
	# lifo
	def unreadtok(tok)
		@queue << tok if tok
	end

	# calls readtok_nopp and handles preprocessor directives
	def readtok_cpp
		lastpos = @pos
		tok = readtok_nopp

		if not tok
			# end of file: resume parent
			if not @backtrace.empty?
				raise ParseError, "parse error in #@filename: unmatched #if/#endif" if @backtrace.last.pop != @ifelse_nesting.length
				puts "metasm preprocessor: end of include #@filename" if $DEBUG
				@filename, @lineno, @text, @pos, @queue = @backtrace.pop
				tok = readtok
			end

		elsif (tok.type == :eol or lastpos == 0) and @ifelse_nesting.last != :testing
			unreadtok tok if lastpos == 0
			# detect preprocessor directive
			# state = 1 => seen :eol, 2 => seen #
			pretok = []
			rewind = true
			state = 1
			loop do
				pretok << (ntok = readtok_nopp)
				break if not ntok
				if ntok.type == :space	# nothing
				elsif state == 1 and ntok.type == :punct and ntok.raw == '#' and not ntok.expanded_from
					state = 2
				elsif state == 2 and ntok.type == :string and not ntok.expanded_from
					rewind = false if preprocessor_directive(ntok)
					break
				else break
				end
			end
			if rewind
				# false alarm: revert
				pretok.reverse_each { |t| unreadtok t }
			end
			tok = readtok if lastpos == 0	# else return the :eol

		elsif tok.type == :string and @definition[tok.raw] and (not tok.expanded_from or not tok.expanded_from.include? tok.raw)
			# expand macros
			if defined? @traced_macros
				if tok.backtrace[-2].to_s[0] == ?" and @definition[tok.raw].name and @definition[tok.raw].name.backtrace[-2].to_s[0] == ?<
					# are we in a normal file and expand to an header-defined macro ?
					@traced_macros |= [tok.raw]
				end
			end

			body = @definition[tok.raw].apply(self, tok)
			body.reverse_each { |t| unreadtok t }
			tok = readtok
		end

		tok
	end
	alias readtok readtok_cpp

	# read and return the next token
	# parses quoted strings (set tok.value) and C/C++ comments (:space/:eol)
	def readtok_nopp
		return @queue.pop unless @queue.empty?

		tok = Token.new((@backtrace.map { |bt| bt[0, 2] } + [@filename, @lineno]).flatten)

		case c = getchar
		when nil
			return nil
		when ?', ?"
			# read quoted string value
			tok.type = :quoted
			delimiter = c
			tok.raw << c
			tok.value = ''
			loop do
				raise tok, 'unterminated string' if not c = getchar
				tok.raw << c
				case c
				when delimiter: break
				when ?\\
					raise tok, 'unterminated escape' if not c = getchar
					tok.raw << c
					tok.value << \
					case c
					when ?n: ?\n
					when ?r: ?\r
					when ?t: ?\t
					when ?a: ?\a
					when ?b: ?\b
					# ruby's str.inspect chars
					when ?v: ?\v
					when ?f: ?\f
					when ?e: ?\e
					when ?#, ?\\, ?', ?": c
					when ?\n: ''	# already handled by getchar
					when ?x:
						hex = ''
						while hex.length < 2
							raise tok, 'unterminated escape' if not c = getchar
							case c
							when ?0..?9, ?a..?f, ?A..?F
							else ungetchar; break
							end
							hex << c
							tok.raw << c
						end
						raise tok, 'unterminated escape' if hex.empty?
						hex.hex
					when ?0..?7:
						oct = '' << c
						while oct.length < 3
							raise tok, 'unterminated escape' if not c = getchar
							case c
							when ?0..?7
							else ungetchar; break
							end
							oct << c
							tok.raw << c
						end
						oct.oct
					else b	# raise tok, 'unknown escape sequence'
					end
				when ?\n: ungetchar ; raise tok, 'unterminated string'
				else tok.value << c
				end
			end

		when ?a..?z, ?A..?Z, ?0..?9, ?$, ?_
			tok.type = :string
			tok.raw << c
			loop do
				case c = getchar
				when nil: ungetchar; break		# avoids 'no method "coerce" for nil' warning
				when ?a..?z, ?A..?Z, ?0..?9, ?$, ?_
					tok.raw << c
				else ungetchar; break
				end
			end

		when ?\ , ?\t, ?\r, ?\n
			tok.type = :space
			tok.raw << c
			loop do
				case c = getchar
				when nil: ungetchar; break
				when ?\ , ?\t, ?\r, ?\n
					tok.raw << c
				else ungetchar; break
				end
			end
			tok.type = :eol if tok.raw.index(?\n)

		when ?/
			tok.raw << c
			# comment
			case c = getchar
			when ?/
				# till eol
				tok.type = :eol
				tok.raw << c
				while c = getchar
					tok.raw << c
					break if c == ?\n
				end
			when ?*
				tok.type = :space
				tok.raw << c
				seenstar = false
				loop do
					raise tok, 'unterminated c++ comment' if not c = getchar
					tok.raw << c
					case c
					when ?*: seenstar = true
					when ?/: break if seenstar	# no need to reset seenstar, already false
					else seenstar = false
					end
				end
			else
				# just a slash
				ungetchar
				tok.type = :punct
			end

		else
			tok.type = :punct
			tok.raw << c
		end

		tok
	end

	# defines a simple preprocessor macro (expands to 0 or 1 token)
	def define(name, value=nil)
		raise "redefinition of #{name}" if @definition[name]
		t = Token.new([])
		t.type = :string
		t.raw = name.dup
		@definition[name] = Macro.new(t)
		if value
			t = Token.new([])
			t.type = :string
			t.raw = value.to_s
			@definition[name].body << t
		end
	end

	# handles #directives
	# returns true if the command is valid
	# second parameter for internal use
	def preprocessor_directive(cmd, ocmd = cmd)
		# read spaces, returns the next token
		# XXX for all commands that may change @ifelse_nesting, ensure last element is :testing to disallow any other preprocessor directive to be run in a bad environment (while looking ahead)
		skipspc = proc {
			loop do
				tok = readtok_nopp
				break tok if not tok or tok.type != :space
			end
		}

		eol = tok = nil
		case cmd.raw
		when 'if'
			case @ifelse_nesting.last
			when :accept, nil
				@ifelse_nesting << :testing
				test = PPExpression.parse(self)
				eol = skipspc[]
				raise eol, 'pp syntax error' if eol and eol.type != :eol
				unreadtok eol
				case test.reduce
				when 0:       @ifelse_nesting[-1] = :discard
				when Integer: @ifelse_nesting[-1] = :accept
				else          @ifelse_nesting[-1] = :discard
#				else raise cmd, 'pp cannot evaluate condition ' + test.inspect
				end
			when :discard, :discard_all
				@ifelse_nesting << :discard_all
			end

		when 'ifdef'
			case @ifelse_nesting.last
			when :accept, nil
				@ifelse_nesting << :testing
				raise eol || tok || cmd, 'pp syntax error' if not tok = skipspc[] or tok.type != :string or (eol = skipspc[] and eol.type != :eol)
				unreadtok eol
				@ifelse_nesting[-1] = (@definition[tok.raw] ? :accept : :discard)
			when :discard, :discard_all
				@ifelse_nesting << :discard_all
			end

		when 'ifndef'
			case @ifelse_nesting.last
			when :accept, nil
				@ifelse_nesting << :testing
				raise eol || tok || cmd, 'pp syntax error' if not tok = skipspc[] or tok.type != :string or (eol = skipspc[] and eol.type != :eol)
				unreadtok eol
				@ifelse_nesting[-1] = (@definition[tok.raw] ? :discard : :accept)
			when :discard, :discard_all
				@ifelse_nesting << :discard_all
			end

		when 'elif'
			case @ifelse_nesting.last
			when :accept
				@ifelse_nesting[-1] = :discard_all
			when :discard
				@ifelse_nesting[-1] = :testing
				test = PPExpression.parse(self)
				raise eol, 'pp syntax error' if eol = skipspc[] and eol.type != :eol
				unreadtok eol
				case test.reduce
				when 0:       @ifelse_nesting[-1] = :discard
				when Integer: @ifelse_nesting[-1] = :accept
				else          @ifelse_nesting[-1] = :discard
#				else raise cmd, 'pp cannot evaluate condition ' + test.inspect
				end
			when :discard_all
			else raise cmd, 'pp syntax error'
			end

		when 'else'
			@ifelse_nesting << :testing
			@ifelse_nesting.pop
			raise eol || cmd, 'pp syntax error' if @ifelse_nesting.empty? or (eol = skipspc[] and eol.type != :eol)
			unreadtok eol
			case @ifelse_nesting.last
			when :accept
				@ifelse_nesting[-1] = :discard_all
			when :discard
				@ifelse_nesting[-1] = :accept
			when :discard_all
			end

		when 'endif'
			@ifelse_nesting << :testing
			@ifelse_nesting.pop
			raise eol || cmd, 'pp syntax error' if @ifelse_nesting.empty? or (eol = skipspc[] and eol.type != :eol)
			unreadtok eol
			@ifelse_nesting.pop

		when 'define'
			return if @ifelse_nesting.last and @ifelse_nesting.last != :accept

			raise tok || cmd, 'pp syntax error' if not tok = skipspc[] or tok.type != :string
			puts "W: pp: redefinition of #{tok.raw} #{tok.backtrace_str}, prev def at #{@definition[tok.raw].name.backtrace_str}" if @definition[tok.raw] and $VERBOSE
			@definition[tok.raw] = Macro.new(tok)
			@definition[tok.raw].parse_definition(self)

		when 'undef'
			return if @ifelse_nesting.last and @ifelse_nesting.last != :accept

			raise eol || tok || cmd, 'pp syntax error' if not tok = skipspc[] or tok.type != :string or (eol = skipspc[] and eol.type != :eol)
			@definition.delete tok.raw
			unreadtok eol

		when 'include'
			return if @ifelse_nesting.last and @ifelse_nesting.last != :accept

			raise cmd, 'nested too deeply' if backtrace.length > 200	# gcc
	
			# gcc seems to discard @queue on input, but we'll prolly use this in include_c

			# allow preprocessing
			nil while tok = readtok and tok.type == :space
			raise tok || cmd, 'pp syntax error' if not tok or (tok.type != :quoted and (tok.type != :punct or tok.raw != '<'))
			if tok.type == :quoted
				ipath = tok.value
				if @backtrace.find { |btf, *a| btf[0] == ?< }
					# XXX local include from a std include... (kikoo windows.h !)
					dir = @include_search_path.find { |d| File.exist? File.join(d, ipath) }
					path = File.join(dir, ipath) if dir
				elsif ipath[0] != ?/
					path = File.join(File.dirname(@filename[1..-2]), ipath) if ipath[0] != ?/
				else
					path = ipath
				end
			else
				# no more preprocessing : allow comments/multiple space/etc
				ipath = ''
				while tok = readtok_nopp and (tok.type != :punct or tok.raw != '>')
					raise cmd, 'syntax error' if tok.type == :eol
					ipath << tok.raw
				end
				raise cmd, 'pp syntax error, unterminated path' if not tok
				if ipath[0] != ?/
					dir = @include_search_path.find { |d| File.exist? File.join(d, ipath) }
					path = File.join(dir, ipath) if dir
				end
			end
			nil while tok = readtok_nopp and tok.type == :space
			raise tok if tok and tok.type != :eol
			unreadtok tok

			if not defined? @pragma_once or not @pragma_once or not @pragma_once[path]
				puts "metasm preprocessor: including #{path}" if $DEBUG
				raise cmd, "No such file or directory #{ipath.inspect}" if not path or not File.exist? path
				raise cmd, 'filename too long' if path.length > 4096		# gcc

				@backtrace << [@filename, @lineno, @text, @pos, @queue, @ifelse_nesting.length]
				# @filename[-1] used in trace_macros to distinguish generic/specific files
				if tok.type == :quoted
					@filename = '"' + path + '"'
				else
					@filename = '<' + path + '>'
				end
				@lineno = 1
				@text = File.read(path)
				@pos = 0
				@queue = []
			else
				puts "metasm preprocessor: not reincluding #{path} (pragma once)" if $DEBUG
			end

		when 'error', 'warning'
			return if @ifelse_nesting.last and @ifelse_nesting.last != :accept
			msg = ''
			while tok = readtok_nopp and tok.type != :eol
				msg << tok.raw
			end
			unreadtok tok
			if cmd.raw == 'warning'
				puts cmd.exception("#warning#{msg}").message if $VERBOSE
			else
				raise cmd, "#error#{msg}"
			end

		when 'line'
			return if @ifelse_nesting.last and @ifelse_nesting.last != :accept

			nil while tok = readtok_nopp and tok.type == :space
			raise tok || cmd if not tok or tok.type != :string or tok.raw != tok.raw.to_i.to_s
			@lineno = tok.raw.to_i
			nil while tok = readtok_nopp and tok.type == :space
			raise tok if tok and tok.type != :eol
			unreadtok tok

		when 'pragma'
			return if @ifelse_nesting.last and @ifelse_nesting.last != :accept

			nil while tok = readtok and tok.type == :space
			raise tok || cmd if not tok or tok.type != :string

			case tok.raw
			when 'once'
				(@pragma_once ||= {})[@filename[1..-2]] = true
			when 'push_macro'
				@pragma_macro_stack ||= []
				nil while lp = readtok and lp.type == :space
				nil while m = readtok and m.type == :space
				nil while rp = readtok and rp.type == :space
				raise cmd if not rp or lp.type != :punct or rp.type != :punct or lp.raw != '(' or rp.raw != ')' or m.type != :quoted
				mbody = @definition[m.value]
				@pragma_macro_stack << mbody

			when 'pop_macro'
				@pragma_macro_stack ||= []
				nil while lp = readtok and lp.type == :space
				nil while m = readtok and m.type == :space
				nil while rp = readtok and rp.type == :space
				raise cmd if not rp or lp.type != :punct or rp.type != :punct or lp.raw != '(' or rp.raw != ')' or m.type != :quoted
				raise cmd, "macro stack empty" if @pragma_macro_stack.empty?
				# pushing undefined macro name is allowed, handled here
				mbody = @pragma_macro_stack.pop
				if mbody
					@definition[m.value] = mbody
				else
					@definition.delete m.value
				end
			
			when 'pack'
				nil while lp = readtok and lp.type == :space
				nil while rp = readtok and rp.type == :space
				if not rp or rp.type != :punct or rp.raw != ')'
					v1 = rp
					nil while rp = readtok and rp.type == :space
				end
				if rp and rp.type == :punct and rp.raw == ','
					nil while v2 = readtok and v2.type == :space
					nil while rp = readtok and rp.type == :space
				end
				raise cmd if not rp or lp.type != :punct or rp.type != :punct or lp.raw != '(' or rp.raw != ')'
				raise cmd if (v1 and v1.type != :string) or (v2 and (v2.type != :string or v2.raw =~ /[^\d]/))
				if not v1
					@pragma_pack = default_pragma_pack_value
				elsif v1.raw == 'push'
					@pragma_pack_stack ||= []
					@pragma_pack_stack << @pragma_pack
					@pragma_pack = v2.raw.to_i if v2
				elsif v1.raw == 'pop'
					@pragma_pack_stack ||= []
					raise cmd, "pack stack empty" if @pragma_pack_stack.empty?
					@pragma_pack = @pragma_pack_stack.pop
					@pragma_pack = v2.raw.to_i if v2 and v2.raw	# #pragma pack(pop, 4) => pop stack, but use 4 as pack value (imho)
				elsif v1.raw !~ /[^\d]/  
					raise cmd if v2
					@pragma_pack = v1.raw.to_i
				else
					raise cmd
				end

			else
				str = tok.raw.dup
				str << tok.raw while tok = readtok and tok.type != :eol
				unreadtok tok
				puts cmd.exception("unhandled #pragma #{str}").message if $VERBOSE
			end

			nil while tok = readtok and tok.type == :space
			raise tok if tok and tok.type != :eol
			unreadtok tok

		else return false
		end

		# skip #undef'd parts of the source
		state = 1	# just seen :eol
		while @ifelse_nesting.last == :discard or @ifelse_nesting.last == :discard_all
			begin 
				tok = skipspc[]
			rescue ParseError
				# react as gcc -E: " unterminated in #undef => ok, /* unterminated => error (the " will fail at eol)
				retry
			end

			if not tok: raise ocmd, 'pp unterminated conditional'
			elsif tok.type == :eol: state = 1
			elsif state == 1 and tok.type == :punct and tok.raw == '#': state = 2
			elsif state == 2 and tok.type == :string: state = preprocessor_directive(tok, ocmd) ? 1 : 0
			else state = 0
			end
		end

		true
	end
end

# parses a preprocessor expression (similar to Expression, + handles "defined(foo)")
class PPExpression
	class << self
		# reads an operator from the lexer, returns the corresponding symbol or nil
		def readop(lexer)
			if not tok = lexer.readtok or tok.type != :punct
				lexer.unreadtok tok
				return
			end

			op = tok
			case op.raw
			# may be followed by itself or '='
			when '>', '<'
				if ntok = lexer.readtok and ntok.type == :punct and (ntok.raw == op.raw or ntok.raw == '=')
					op = op.dup
					op.raw << ntok.raw
				else
					lexer.unreadtok ntok
				end
			# may be followed by itself
			when '|', '&'
				if ntok = lexer.readtok and ntok.type == :punct and ntok.raw == op.raw
					op = op.dup
					op.raw << ntok.raw
				else
					lexer.unreadtok ntok
				end
			# must be followed by '='
			when '!', '='
				if not ntok = lexer.readtok or ntok.type != :punct and ntok.raw != '='
					lexer.unreadtok ntok
					lexer.unreadtok tok
					return
				end
				op = op.dup
				op.raw << ntok.raw
			# ok
			when '^', '+', '-', '*', '/', '%'
			# unknown
			else
				lexer.unreadtok tok
				return
			end
			op.value = op.raw.to_sym
			op
		end

		# handles floats and "defined" keyword
		def parse_intfloat(lexer, tok)
			if tok.type == :string and tok.raw == 'defined'
				nil while ntok = lexer.readtok_nopp and ntok.type == :space
				raise tok if not ntok
				if ntok.type == :punct and ntok.raw == '('
					nil while ntok = lexer.readtok_nopp and ntok.type == :space
					nil while rtok = lexer.readtok_nopp and rtok.type == :space
					raise tok if not rtok or rtok.type != :punct or rtok.raw != ')'
				end
				raise tok if not ntok or ntok.type != :string
				tok.value = lexer.definition[ntok.raw] ? 1 : 0
				return 
			end

			Expression.parse_num_value(lexer, tok)
		end

		# returns the next value from lexer (parenthesised expression, immediate, variable, unary operators)
		# single-line only, and does not handle multibyte char string
		def parse_value(lexer)
			nil while tok = lexer.readtok and tok.type == :space
			return if not tok
			case tok.type
			when :string
				parse_intfloat(lexer, tok)
				val = tok.value || tok.raw
			when :quoted
				if tok.raw[0] != ?' or tok.value.length > 1	# allow single-char
					lexer.unreadtok tok
					return
				end
				val = tok.value[0]
			when :punct
				case tok.raw
				when '('
					nil while ntok = lexer.readtok and ntok.type == :space
					lexer.unreadtok ntok
					val = parse(lexer)
					nil while ntok = lexer.readtok and ntok.type == :space
					raise tok, "syntax error, no ) found after #{val.inspect}, got #{ntok.inspect}" if not ntok or ntok.type != :punct or ntok.raw != ')'
				when '!', '+', '-', '~'
					nil while ntok = lexer.readtok and ntok.type == :space
					lexer.unreadtok ntok
					raise tok, 'need expression after unary operator' if not val = parse_value(lexer)
					val = Expression[tok.raw.to_sym, val]
				when '.'
					parse_intfloat(lexer, tok)
					if not tok.value
						lexer.unreadtok tok
						return
					end
					val = tok.value
				else
					lexer.unreadtok tok
					return
				end
			else
				lexer.unreadtok tok
				return
			end
			nil while tok = lexer.readtok and tok.type == :space
			lexer.unreadtok tok
			val
		end

		# for boolean operators, true is 1 (or anything != 0), false is 0
		def parse(lexer)
			opstack = []
			stack = []

			return if not e = parse_value(lexer)

			stack << e

			while op = readop(lexer)
				nil while ntok = lexer.readtok and ntok.type == :space
				lexer.unreadtok ntok
				until opstack.empty? or Expression::OP_PRIO[op.value][opstack.last]
					stack << Expression.new(opstack.pop, stack.pop, stack.pop)
				end
				
				opstack << op.value
				
				raise op, 'need rhs' if not e = parse_value(lexer)

				stack << e
			end

			until opstack.empty?
				stack << Expression.new(opstack.pop, stack.pop, stack.pop)
			end

			Expression[stack.first]
		end
	end
end
end
