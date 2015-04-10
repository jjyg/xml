CC=gcc
CCOPTS=-W -Wall -O2
RUBY_INCLUDE=$(shell ruby ./ruby_makegen.rb '-I $$(rubyhdrdir) -I $$(rubyhdrdir)/$$(arch) -I $$(rubyarchhdrdir)')

xml_parser.so: xml_parser.c
	$(CC) $(CCOPTS) $(RUBY_INCLUDE) -fPIC -shared -o $@ $<

