require 'rbconfig'

def expand(s)
	s.gsub(/\$\((\w+)\)/) {
		expand RbConfig::MAKEFILE_CONFIG.fetch($1) { |k|
			if k == 'rubyhdrdir'
				expand('$(topdir)')
			else
				k
			end
		}
	}
end

puts expand ARGV.join(' ')
