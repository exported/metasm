#    This file is part of Metasm, the Ruby assembly manipulation suite
#    Copyright (C) 2006-2009 Yoann GUILLOT
#
#    Licence is LGPL, see LICENCE in the top-level directory

require 'gtk2'

module Metasm
module GtkGui
class CdecompListingWidget < Gtk::DrawingArea
	attr_accessor :hl_word, :curaddr, :caret_x, :caret_y, :tabwidth

	def initialize(dasm, parent_widget)
		bug_me_not = Decompiler	# sometimes gtk fails to autorequire dcmp during expose_event, do it now
		@dasm = dasm
		@parent_widget = parent_widget
		@hl_word = nil
		@oldcaret_x = @oldcaret_y = @caret_x = @caret_y = 0	# caret position in characters coordinates (column/line)
		@view_x = @view_y = 0	# coord of corner of view in characters
		@width = @height = 1	# widget size in chars
		@layout = Pango::Layout.new Gdk::Pango.context
		@color = {}
		@line_text = []
		@line_text_col = []	# each line is [[:col, 'text'], [:col, 'text']]
		@curaddr = nil
		@tabwidth = 8

		super()

		# receive mouse/kbd events
		set_events Gdk::Event::ALL_EVENTS_MASK
		set_can_focus true
		set_font 'courier 10'

		signal_connect('expose_event') { paint ; true }
		signal_connect('button_press_event') { |w, ev|
			case ev.event_type
			when Gdk::Event::Type::BUTTON_PRESS
				grab_focus
				case ev.button
				when 1; click(ev)
				when 3; rightclick(ev)
				end
			when Gdk::Event::Type::BUTTON2_PRESS
				case ev.button
				when 1; doubleclick(ev)
				end
			end
		}
		signal_connect('key_press_event') { |w, ev| # keyboard
			keypress(ev)
		}
		signal_connect('size_allocate') { redraw }
		signal_connect('realize') { # one-time initialize
			# raw color declaration
			{ :white => 'fff', :palegrey => 'ddd', :black => '000', :grey => '444',
			  :red => 'f00', :darkred => '800', :palered => 'fcc',
			  :green => '0f0', :darkgreen => '080', :palegreen => 'cfc',
			  :blue => '00f', :darkblue => '008', :paleblue => 'ccf',
			  :yellow => 'cc0', :darkyellow => '660', :paleyellow => 'ff0',
			}.each { |tag, val|
				@color[tag] = Gdk::Color.new(*val.unpack('CCC').map { |c| (c.chr*4).hex })
			}
			# register colors
			@color.each_value { |c| window.colormap.alloc_color(c, true, true) }

			# map functionnality => color
			set_color_association :text => :black, :keyword => :blue, :caret => :black,
			  :bg => :white, :hl_word => :palered, :localvar => :darkred, :globalvar => :darkgreen,
			  :intrinsic => :darkyellow
		}
	end

	def curfunc
		@dasm.c_parser and (@dasm.c_parser.toplevel.symbol[@curaddr] or @dasm.c_parser.toplevel.struct[@curaddr])
	end

	def click(ev)
		@caret_x = (ev.x-1).to_i / @font_width
		@caret_y = ev.y.to_i / @font_height
		update_caret
	end

	def rightclick(ev)
		click(ev)
		if @dasm.c_parser and @dasm.c_parser.toplevel.symbol[@hl_word]
			@parent_widget.clone_window(@hl_word, :decompile)
		elsif @hl_word
			@parent_widget.clone_window(@hl_word)
		end
	end

	def doubleclick(ev)
		@parent_widget.focus_addr(@hl_word)
	end

	def paint
		w = window
		gc = Gdk::GC.new(w)

		a = allocation
		@width = a.width/@font_width
		@height = a.height/@font_height

		# adjust viewport to cursor
		sz_x = @line_text.map { |l| l.length }.max.to_i + 1
		sz_y = @line_text.length.to_i + 1
		@view_x = @caret_x - @width + 1 if @caret_x > @view_x + @width - 1
		@view_x = @caret_x if @caret_x < @view_x
		@view_x = sz_x - @width - 1 if @view_x >= sz_x - @width
		@view_x = 0 if @view_x < 0

		@view_y = @caret_y - @height + 1 if @caret_y > @view_y + @height - 1
		@view_y = @caret_y if @caret_y < @view_y
		@view_y = sz_y - @height - 1 if @view_y >= sz_y - @height
		@view_y = 0 if @view_y < 0

		# current cursor position
		x = 1
		y = 0

		# renders a string at current cursor position with a color
		# must not include newline
		render = lambda { |str, color|
			# function ends when we write under the bottom of the listing
			if @hl_word
				stmp = str
				pre_x = 0
				while stmp =~ /^(.*?)(\b#{Regexp.escape @hl_word}\b)/
					s1, s2 = $1, $2
					@layout.text = s1
					pre_x += @layout.pixel_size[0]
					@layout.text = s2
					hl_w = @layout.pixel_size[0]
					gc.set_foreground @color[:hl_word]
					w.draw_rectangle(gc, true, x+pre_x, y, hl_w, @font_height)
					pre_x += hl_w
					stmp = stmp[s1.length+s2.length..-1]
				end
			end
			@layout.text = str
			gc.set_foreground @color[color]
			w.draw_layout(gc, x, y, @layout)
			x += @layout.pixel_size[0]
		}

		@line_text_col[@view_y, @height + 1].each { |l|
			cx = 0
			l.each { |c, t|
				cx += t.length
				if cx-t.length > @view_x + @width + 1
				elsif cx < @view_x
				else
					t = t[(@view_x - cx + t.length)..-1] if cx-t.length < @view_x
					render[t, c]
				end
			}
			x = 1
			y += @font_height
		}

		if focus?
			# draw caret
			gc.set_foreground @color[:caret]
			cx = (@caret_x-@view_x)*@font_width+1
			cy = (@caret_y-@view_y)*@font_height
			w.draw_line(gc, cx, cy, cx, cy+@font_height-1)
		end
	
		@oldcaret_x, @oldcaret_y = @caret_x, @caret_y
	end

	include Gdk::Keyval
	# n: rename variable
	# t: retype variable (persistent)
	def keypress(ev)
		case ev.state & Gdk::Window::CONTROL_MASK
		when 0; keypress_simple(ev)
		else @parent_widget.keypress(ev)
		end
	end

	def keypress_simple(ev)
		case ev.keyval
		when GDK_Left
			if @caret_x >= 1
				@caret_x -= 1
				update_caret
			end
		when GDK_Up
			if @caret_y > 0
				@caret_y -= 1
				update_caret
			end
		when GDK_Right
			if @caret_x < @line_text[@caret_y].to_s.length
				@caret_x += 1
				update_caret
			end
		when GDK_Down
			if @caret_y < @line_text.length
				@caret_y += 1
				update_caret
			end
		when GDK_Home
			@caret_x = @line_text[@caret_y].to_s[/^\s*/].length
			update_caret
		when GDK_End
			@caret_x = @line_text[@caret_y].to_s.length
			update_caret
		when GDK_n	# rename local/global variable
			f = curfunc.initializer if curfunc and curfunc.initializer.kind_of? C::Block
			n = @hl_word
			if (f and f.symbol[n]) or @dasm.c_parser.toplevel.symbol[n]
				@parent_widget.inputbox("new name for #{n}", :text => n) { |v|
					if v !~ /^[a-z_$][a-z_0-9$]*$/i
						@parent_widget.messagebox("invalid name #{v.inspect} !")
						next
					end
					if f and f.symbol[n]
						# TODO add/update comment to the asm instrs
						s = f.symbol[v] = f.symbol.delete(n)
						s.name = v
						f.decompdata[:stackoff_name][s.stackoff] = v if s.stackoff
					elsif @dasm.c_parser.toplevel.symbol[n]
						@dasm.rename_label(n, v)
						@curaddr = v if @curaddr == n                   
					end
					gui_update
				}
			end
		when GDK_r # redecompile
			@parent_widget.decompile(@curaddr)
		when GDK_t	# change variable type (you'll want to redecompile after that)
			f = curfunc.initializer if curfunc.kind_of? C::Variable and curfunc.initializer.kind_of? C::Block
			n = @hl_word
			cp = @dasm.c_parser
			if (f and s = f.symbol[n]) or s = cp.toplevel.symbol[n] or s = cp.toplevel.symbol[@curaddr]
				s_ = s.dup
				s_.initializer = nil if s.kind_of? C::Variable	# for static var, avoid dumping the initializer in the textbox
				s_.attributes &= C::Attributes::DECLSPECS if s_.attributes
				@parent_widget.inputbox("new type for #{s.name}", :text => s_.dump_def(cp.toplevel)[0].to_s) { |t|
					if t == ''
						if s.type.kind_of? C::Function and s.initializer and s.initializer.decompdata
							s.initializer.decompdata[:stackoff_type].clear
							s.initializer.decompdata.delete :return_type
						elsif s.kind_of? C::Variable and s.stackoff
							f.decompdata[:stackoff_type].delete s.stackoff
						end
						next
					end
					begin
						cp.lexer.feed(t)
						raise 'bad type' if not v = C::Variable.parse_type(cp, cp.toplevel, true)
						v.parse_declarator(cp, cp.toplevel)
						if s.type.kind_of? C::Function and s.initializer and s.initializer.decompdata
							# updated type of a decompiled func: update stack
							vt = v.type.untypedef
							vt = vt.type.untypedef if vt.kind_of? C::Pointer
							raise 'function forever !' if not vt.kind_of? C::Function
							# TODO _declspec
							ao = 1
							vt.args.to_a.each { |a|
								next if a.has_attribute_var('register')
								ao = (ao + [cp.sizeof(a), cp.typesize[:ptr]].max - 1) / cp.typesize[:ptr] * cp.typesize[:ptr]
								s.initializer.decompdata[:stackoff_name][ao] = a.name if a.name
								s.initializer.decompdata[:stackoff_type][ao] = a.type
								ao += cp.sizeof(a)
							}
							s.initializer.decompdata[:return_type] = vt.type
							s.type = v.type
						else
							f.decompdata[:stackoff_type][s.stackoff] = v.type if f and s.kind_of? C::Variable and s.stackoff
							s.type = v.type
						end
						gui_update
					rescue Object
						@parent_widget.messagebox([$!.message, $!.backtrace].join("\n"), "error")
					end
					cp.readtok until cp.eos?
				}
			end
		else
			return @parent_widget.keypress(ev)
		end
		true
	end

	def get_cursor_pos
		[@curaddr, @caret_x, @caret_y]
	end

	def set_cursor_pos(p)
		focus_addr p[0]
		@caret_x, @caret_y = p[1, 2]
		update_caret
	end

	def set_font(descr)
		@layout.font_description = Pango::FontDescription.new(descr)
		@layout.text = 'x'
		@font_width, @font_height = @layout.pixel_size
		redraw
	end

	def set_color_association(hash)
		hash.each { |k, v| @color[k] = @color[v] }
		modify_bg Gtk::STATE_NORMAL, @color[:bg]
		redraw
	end

	# hint that the caret moved
	# redraws the caret, change the hilighted word, redraw if needed
	def update_caret
		return if @oldcaret_x == @caret_x and @oldcaret_y == @caret_y
		return if not window

		redraw if @caret_x < @view_x or @caret_x >= @view_x + @width or @caret_y < @view_y or @caret_y >= @view_y + @height

		x = (@oldcaret_x-@view_x)*@font_width+1
		y = (@oldcaret_y-@view_y)*@font_height
		window.invalidate Gdk::Rectangle.new(x-1, y, 2, @font_height), false
		x = (@caret_x-@view_x)*@font_width+1
		y = (@caret_y-@view_y)*@font_height
		window.invalidate Gdk::Rectangle.new(x-1, y, 2, @font_height), false
		@oldcaret_x = @caret_x
		@oldcaret_y = @caret_y

		return if not l = @line_text[@caret_y]
		word = l[0...@caret_x].to_s[/\w*$/] << l[@caret_x..-1].to_s[/^\w*/]
		word = nil if word == ''
		if @hl_word != word
			@hl_word = word
			redraw
		end
	end

	# focus on addr
	# returns true on success (address exists & decompiled)
	def focus_addr(addr)
		if @dasm.c_parser and (@dasm.c_parser.toplevel.symbol[addr] or @dasm.c_parser.toplevel.struct[addr])
			@curaddr = addr
			@caret_x = @caret_y = 0
			gui_update
			return true
		end

		return if not addr = @parent_widget.normalize(addr)

		# scan up to func start/entrypoint
		todo = [addr]
		done = []
		ep = @dasm.entrypoints.to_a.inject({}) { |h, e| h.update @dasm.normalize(e) => true }
		while addr = todo.pop
			addr = @dasm.normalize(addr)
			next if not @dasm.decoded[addr].kind_of? DecodedInstruction
			addr = @dasm.decoded[addr].block.address
			next if done.include?(addr) or not @dasm.decoded[addr].kind_of? DecodedInstruction
			done << addr
			break if @dasm.function[addr] or ep[addr]
			empty = true
			@dasm.decoded[addr].block.each_from_samefunc(@dasm) { |na| empty = false ; todo << na }
			break if empty
		end
		@dasm.auto_label_at(addr, 'loc') if @dasm.get_section_at(addr) and not @dasm.get_label_at(addr)
		return if not l = @dasm.get_label_at(addr)
		@curaddr = l
		@caret_x = @caret_y = 0
		gui_update
		true
	end

	def redraw
		window.invalidate Gdk::Rectangle.new(0, 0, 100000, 100000), false if window
	end

	# returns the address of the data under the cursor
	def current_address
		@curaddr
	end

	def update_line_text
		@line_text = curfunc.dump_def(@dasm.c_parser.toplevel)[0].map { |l| l.gsub("\t", ' '*@tabwidth) }
		@line_text_col = []

		if f = curfunc and f.kind_of? C::Variable and f.initializer.kind_of? C::Block
			keyword_re = /\b(#{C::Keyword.keys.join('|')})\b/
			intrinsic_re = /\b(intrinsic_\w+)\b/
			lv = f.initializer.symbol.keys
			lv << '00' if lv.empty?
			localvar_re = /\b(#{lv.join('|')})\b/
			globalvar_re = /\b(#{f.initializer.outer.symbol.keys.join('|')})\b/
		end

		@line_text.each { |l|
			lc = []
			if f
				while l and l.length > 0
					if (i_k = (l =~ keyword_re)) == 0
						m = $1.length
						col = :keyword
					elsif (i_i = (l =~ intrinsic_re)) == 0
						m = $1.length
						col = :intrinsic
					elsif (i_l = (l =~ localvar_re)) == 0
						m = $1.length
						col = :localvar
					elsif (i_g = (l =~ globalvar_re)) == 0
						m = $1.length
						col = :globalvar
					else
						m = ([i_k, i_i, i_l, i_g, l.length] - [nil, false]).min
						col = :text
					end
					lc << [col, l[0, m]]
					l = l[m..-1]
				end
			else
				lc << [:text, l]
			end
			@line_text_col << lc
		}
	end

	def gui_update
		if not curfunc and not @decompiling ||= false
			@line_text = ['please wait']
			@line_text_col = [[[:text, 'please wait']]]
			redraw
			@decompiling = true
			@dasm.decompile_func(@curaddr)
			@decompiling = false
		end
		if curfunc
			update_line_text
			@oldcaret_x = @caret_x + 1
			update_caret
		end
		redraw
	end
end
end
end
