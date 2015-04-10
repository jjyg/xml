# pure ruby library to encode/decode xml
# Y Guillot, 08/2013
# WtfPLv2

module Xml
	# xml entities encoding/decoding
	Entities = {
		'>' => '&gt;',
		'<' => '&lt;',
		'"' => '&quot;',
	}
	EntitiesRE = Regexp.new('(' << Entities.keys.join('|') << ')')
	EntitiesDec = Entities.invert
	EntitiesDecRE = Regexp.new('(' << EntitiesDec.keys.join('|') << ')', Regexp::IGNORECASE)

	def self.entities_encode(str)
		str.to_s.gsub(EntitiesRE) { |x| Entities.fetch(x, x) }
	end

	def self.entities_decode(str)
		str.to_s.gsub(EntitiesDecRE) { |x| EntitiesDec.fetch(x, x) }
	end


# one Xml tag
class Tag
	# name of the tag (eg <body bla="fu"/> => 'body')
	attr_accessor :name
	# hash of attributes for the tag (eg { 'bla' => 'fu' })
	attr_accessor :attrs
	# array of children elements, either strings (String), tags (Xml::Tag) or comments (Xml::Comment)
	attr_accessor :children
	# bool to tell if the tag is <tag/> (true) or <tag></tag> (false)
	attr_accessor :uniq

	def initialize(name, attrs=nil, children=nil)
		@name = name
		@attrs = Hash.new
		attrs.each { |k, v| set_attr(k, v) } if attrs
		if children == false
			@children = Array.new
			@uniq = true
		else
			@children = children ? children : Array.new
			@uniq = false
		end
	end

	# add children
	# if passed an Array, add each element
	# return the tag
	def add(*children)
		children.each { |e|
			if (e.class == Array)
				add(*e)
				next
			end
			@uniq = false
			@children << e
		}
		self
	end

	# alias for #add
	def <<(c)
		add(c)
	end

	# define an attribute
	# return the tag
	def set_attr(k, v)
		@attrs[k] = v
		self
	end

	# read an attribute
	def [](k)
		@attrs[k]
	end

	# define an attribute
	def []=(k, v)
		@attrs[k] = v
	end

	# set the #uniq flag
	def set_uniq(b=true)
		@uniq = b
		self
	end

	# internal function, returns the size of the string representation as one line
	def length(start=nil)
		if start
			l = start.length
		else
			# '<name>'
			l = @name.length + 2
			@attrs.each{ |k, v|
				l += " #{k}=\"#{Xml.entities_encode(v)}\"".length
			}
			l += 2 if @uniq
		end
		@children.each{ |c|
			l += case c
			     when ::String; Xml.entities_encode(c).length
			     else; c.to_s.length
			     end
		}
		# '</name>'
		l += 3+@name.length unless @uniq
		return l
	end

	# renders the xml and children as a String, try to keep the output less than 80cols
	def to_s(indent = '')
		attrs = @attrs.map { |k, v| " #{k}=\"#{Xml.entities_encode(v)}\"" }.join
		s = '' << indent << '<' << @name << attrs << (@uniq ? ' />' : '>')
		if @uniq
			s
		elsif length(s) > 80
			s << @children.map { |c|
				case c
				when Tag; "\n" << c.to_s(indent + '  ')
				when ::String; Xml.entities_encode(c)
				else "\n" << indent << '  ' << c.to_s
				end
			}.join
			s << "\n" << indent unless @children.last.kind_of?(::String)
			s << '</' << @name << '>'
		else
			s << @children.map { |c| c.to_s }.join << '</' << @name << '>'
		end
	end

	def inspect
		'<' << @name << (@children.empty? ? '/' : @children.map { |c| "\n " << c.inspect.gsub("\n", "\n ") }.join << "\n /" << @name) << '>'
	end

	# iterate
	include Enumerable
	def each(name=nil, &b)
		b.call(self) if !name or @name == name
		@children.each { |c| c.each(name, &b) if c.kind_of?(Tag) }
	end

	def find(name=nil, &b)
		each(name) { |t| return t if !b or b.call(t) }
		nil
	end

	def find_all(name=nil, &b)
		ret = []
		each(name) { |t| ret << t if !b or b.call(t) }
		ret
	end
end

# same as an xml node, but add a '<?xml ?>' header to the tag
class Document < Tag
	attr_accessor :encoding, :version, :misc
	def to_s
		"<?xml version=\"#{Xml.entities_encode(version || '1.0')}\" encoding=\"#{Xml.entities_encode(encoding || 'us-ascii')}\"?>\n"+
		misc.to_a.map { |m| "#{m}\n" }.join +
		super()
	end
end

# xml comment
class Comment
	attr_accessor :text
	def initialize(text)
		@text = text
	end

	def to_s
		'<!-- ' << @text.gsub('-->', '--|') << ' -->'
	end
end

# parse an Xml document stored in a ruby String
def self.parse_string(str)
	Parser.new(str).parse_xml
end

# parse an Xml document from a file descriptor
def self.parse_io(io)
	parse_string(io.read)
end

# parse an Xml document from a file name
def self.parse_file(path)
	File.open(path, 'rb') { |fd| parse_io fd }
end

# Xml parser
class Parser
	def initialize(str=nil)
		@str = ''
		@off = 0
		@lineno = 1
		@root = nil
		feed(str) if str
	end

	# add data to be parsed
	def feed(str)
		@str << str
		@str.force_encoding('binary') if @str.respond_to?(:force_encoding)
		if @off == 0 and @str[0, 3] == [0xef, 0xbb, 0xbf].pack('C*')
			# discard UTF-8 BOM marker
			@off = 3
		elsif @off == 0 and (@str[0, 2] == [0xff, 0xfe].pack('C*') or @str[0, 2] == [0x3c, 0x00].pack('C*'))
			# downgrade UTF-16
			if @str[0, 2] == [0xff, 0xfe].pack('C*')
				# discard BOM
				@str = @str[2..-1]
			end

			if @str.respond_to?(:encoding)
				@str = @str.force_encoding('utf-16le').encode('utf-8').force_encoding('binary')
			else
				# rb1.8 compat
				@str = @str.unpack('v*').map { |c| (c < 0 || c > 255) ? 63 : c }.pack('C*')
			end
		end
		self
	end

	# parse the Xml document
	# return the root tag
	# raise on syntax errors
	def parse_xml
		parse_stack = []
		@root = Document.new(nil)
		seen_root = false

		while @off < @str.length
			case e = parse_element
			when String
				# ignore newlines / indentation between tags
				next if e =~ /\A\s*\Z/m
				if parse_stack.empty?
					(@root.misc ||= []) << e.strip
				else
					parse_stack.last.children << e.strip
				end

			when Comment
				if parse_stack.empty?
					(@root.misc ||= []) << e
				else
					parse_stack.last.children << e
				end

			when Tag
				case e.name
				when '?xml'
					raise self, "invalid <?xml> tag" if not parse_stack.empty?
					raise self, "multiple <?xml> root tags" if seen_root
					seen_root = true

					@root.version  = e['version']  if e['version']
					@root.encoding = e['encoding'] if e['encoding']

					puts "unhandled root xml attributes #{e}" unless (e.attrs.keys - ['version', 'encoding']).empty?

				when /^\//
					raise self, "unexpected #{e}" if parse_stack.empty?
					raise self, "invalid tag #{e}" if not e.attrs.empty?
					raise self, "unexpected #{e}, expected </#{parse_stack.last.name}>" if e.name != '/' + parse_stack.last.name

					parse_stack.pop

				else
					raise self, "invalid tag name #{e}" if e.name !~ /^[a-zA-Z][\w:-]*$/

					if parse_stack.empty?
						raise self, "multiple roots?" if @root.name
						@root.name = e.name
						@root.attrs = e.attrs
						@root.uniq = e.uniq
						e = @root
					else
						parse_stack.last.children << e
					end

					parse_stack << e if not e.uniq
				end
			end
		end

		@root
	end

	WhiteSpaces = { ?\  => true, ?\n => true, ?\r => true, ?\t => true }
	WSTagName = WhiteSpaces.merge ?/ => true, ?> => true
	WSAttrName = WSTagName.merge ?= => true
	# parse one xml element (string or <> thing)
	# allows anything as tag name
	def parse_element
		if @str[@off] == ?<
			# new tag
			tag = Tag.new('')
			getc
			c = parser_skipspaces

			# allow / as 1st byte only, to handle </tag> and <tag/>
			tag.name << getc if c == ?/
			tag.name << parser_readuntil(WSTagName)

			if tag.name == '!--'
				# xml comment
				cmt = '' << getc << getc
				while @off < @str.length and @str[@off-3, 3] != '-->'
					cmt << parser_readuntil(?> => true)
					cmt << getc
				end
				cmt.chop! ; cmt.chop! ; cmt.chop!
				return Comment.new(cmt.strip)
			end

			while @off < @str.length
				parse_attribute(tag)
				case @str[@off]
				when nil
					# EOF
					raise self, "unterminated tag #{tag.name}"
				when ?>
					getc
					break
				end
			end

			tag

		else
			# string, read everything until next tag opening
			Xml.entities_decode(parser_readuntil(?< => true))
		end
	end

	# parse one tag attribute
	# also handle the uniq /> close tag
	def parse_attribute(tag)
		case parser_skipspaces
		when nil
			return
		when ?>
			# done
		when ?/
			# ensure what follows is '>'
			getc
			c = parser_skipspaces
			raise self, "expected /> in <#{tag.name}" if c != ?>
			tag.set_uniq

		when ?a..?z, ?A..?Z
			# attribute
			attr_name = parser_readuntil(WSAttrName)
			raise self, "invalid attribute #{attr_name.inspect} in <#{tag.name}" if attr_name !~ /^[a-zA-Z0-9_$:.-]+$/

			case parser_skipspaces
			when ?=
				# attribute = "value"
				getc	# consume '='
				case parser_skipspaces
				when ?', ?"
					sep = getc	# consume sep
					attr_value = parser_readuntil(sep => true)
					sep = getc	# consume closing sep
					raise self, "unclosed quote in <#{tag.name} #{attr_name}=" if sep == ''
				else
					attr_value = parser_readuntil(WSTagName)
				end
			else
				attr_value = attr_name
			end

			tag[attr_name] = Xml.entities_decode(attr_value)

		when ??
			raise self, "invalid '?' in <#{tag.name}" unless tag.name[0] == ??
			getc
		else
			raise self, "invalid attribute for <#{tag.name}"
		end
	end

	# advance @off until @str[@off] is not whitespace
	# return first non-whitespace (nonconsumed) character
	def parser_skipspaces
		while @off < @str.length
			c = @str[@off]
			return c if not WhiteSpaces[c]
			@off += 1
			@lineno += 1 if c == ?\n
		end
		nil
	end

	# return the string formed by any char except those in the hash argument
	def parser_readuntil(charlist)
		start_off = @off
		while @off < @str.length
			c = @str[@off]
			break if charlist[c]
			@off += 1
			@lineno += 1 if c == ?\n
		end
		@str[start_off...@off]
	end

	# read one byte, advance @off
	# return empty string after EOF
	# count lineno
	def getc
		return '' if not c = @str[@off]
		@off += 1
		@lineno += 1 if c == ?\n
		c
	end

	class ParseError < RuntimeError
	end

	def exception(msg)
		ParseError.new("Xml syntax error near line #@lineno, before #{@str[@off, 8].inspect}: #{msg}")
	end
end
end

begin
	require File.expand_path('../xml_parser', __FILE__)
rescue LoadError
end
